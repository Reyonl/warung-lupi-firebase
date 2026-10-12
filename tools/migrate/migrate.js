#!/usr/bin/env node

/**
 * Script Migrasi Idempoten: MySQL Snapshot (warung_migrasi_snapshot) ➔ Cloud Firestore
 * Warung Lupi Staging (warunglupi-staging-fa841)
 *
 * Penggunaan:
 *   node tools/migrate/migrate.js --dry-run   (Hanya membaca dan memverifikasi hitungan)
 *   node tools/migrate/migrate.js             (Eksekusi migrasi ke Cloud Firestore)
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const mysql = require('mysql2/promise');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'warunglupi-staging-fa841';
const DB_CONFIG = {
  host: process.env.MYSQL_HOST || '127.0.0.1',
  port: parseInt(process.env.MYSQL_PORT || '3306', 10),
  user: process.env.MYSQL_USER || 'root',
  password: process.env.MYSQL_PASSWORD || '',
  database: process.env.MYSQL_DATABASE || 'warung_migrasi_snapshot',
};

const BATCH_SIZE = 400; // Aman di bawah batas 500 Firestore
const isDryRun = process.argv.includes('--dry-run');

// Helper: ambil token OAuth Firebase CLI dari configstore
function getFirebaseToken() {
  const configPath = path.join(
    process.env.USERPROFILE || process.env.HOME || '',
    '.config',
    'configstore',
    'firebase-tools.json'
  );
  if (!fs.existsSync(configPath)) {
    throw new Error(`File kredensial Firebase CLI tidak ditemukan di: ${configPath}`);
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  if (!config.tokens || !config.tokens.access_token) {
    throw new Error('Access token tidak ditemukan di firebase-tools.json. Jalankan: firebase login');
  }
  return config.tokens.access_token;
}

// Helper: format nilai JavaScript ke tipe data Cloud Firestore REST API
function toFirestoreValue(val) {
  if (val === null || val === undefined) {
    return { nullValue: null };
  }
  if (typeof val === 'boolean') {
    return { booleanValue: val };
  }
  if (typeof val === 'number') {
    if (Number.isInteger(val)) {
      return { integerValue: val.toString() };
    }
    return { doubleValue: val };
  }
  if (val instanceof Date) {
    return { timestampValue: val.toISOString() };
  }
  return { stringValue: val.toString() };
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    fields[k] = toFirestoreValue(v);
  }
  return fields;
}

// Helper: format tanggal ISO atau string DB ke ISO String
function formatIso(dt) {
  if (!dt) return new Date().toISOString();
  if (dt instanceof Date) return dt.toISOString();
  try {
    const parsed = new Date(dt);
    if (!isNaN(parsed.getTime())) return parsed.toISOString();
  } catch (_) {}
  return new Date().toISOString();
}

function formatDateStr(dt) {
  if (!dt) return '';
  if (dt instanceof Date) {
    const y = dt.getFullYear();
    const m = String(dt.getMonth() + 1).padStart(2, '0');
    const d = String(dt.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  const str = dt.toString();
  return str.length >= 10 ? str.substring(0, 10) : str;
}

// Kirim batch writes ke Firestore REST API
async function commitBatch(token, writes) {
  if (writes.length === 0) return;

  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:commit`;
  const postData = JSON.stringify({ writes });

  return new Promise((resolve, reject) => {
    const req = https.request(
      url,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData),
        },
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(JSON.parse(body || '{}'));
          } else {
            reject(new Error(`Firestore commit gagal (${res.statusCode}): ${body}`));
          }
        });
      }
    );

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function run() {
  console.log('='.repeat(70));
  console.log(`WARUNG LUPI — SCRIPT MIGRASI DATABASE KE CLOUD FIRESTORE`);
  console.log(`Target Project: ${PROJECT_ID} (asia-southeast2)`);
  console.log(`Sumber Data   : MySQL [${DB_CONFIG.database}] @ ${DB_CONFIG.host}:${DB_CONFIG.port}`);
  console.log(`Mode Operasi  : ${isDryRun ? 'DRY RUN (Hanya Validasi & Hitungan)' : 'EKSEKUSI PENULISAN AKTIF'}`);
  console.log('='.repeat(70));

  let token = null;
  if (!isDryRun) {
    token = getFirebaseToken();
    console.log('Token autentikasi Firebase CLI berhasil diverifikasi.');
  }

  // 1. Koneksi ke MySQL Snapshot
  const conn = await mysql.createConnection(DB_CONFIG);
  console.log('Koneksi ke database snapshot MySQL berhasil.');

  const migrationTimestamp = new Date().toISOString();

  // 2. Baca seluruh data tabel
  const [categories] = await conn.query('SELECT * FROM categories ORDER BY id ASC');
  const [products] = await conn.query('SELECT * FROM products ORDER BY id ASC');
  const [customers] = await conn.query('SELECT * FROM customers ORDER BY id ASC');
  const [transactions] = await conn.query('SELECT * FROM transactions ORDER BY transaction_date ASC, id ASC');
  const [transactionItems] = await conn.query('SELECT * FROM transaction_items ORDER BY id ASC');
  const [expenses] = await conn.query('SELECT * FROM expenses ORDER BY id ASC');

  await conn.end();

  console.log('\n--- HASIL PEMBACAAN SNAPSHOT LOKAL ---');
  console.log(`Kategori          : ${categories.length} baris`);
  console.log(`Produk            : ${products.length} baris`);
  console.log(`Pelanggan         : ${customers.length} baris`);
  console.log(`Transaksi (Bon)   : ${transactions.length} baris`);
  console.log(`Item Transaksi    : ${transactionItems.length} baris`);
  console.log(`Pengeluaran Manual: ${expenses.length} baris`);

  // 3. Mapping data relasional ke NoSQL
  const writes = [];

  // A. Kategori -> categories/legacy_{id}
  for (const c of categories) {
    const docPath = `projects/${PROJECT_ID}/databases/(default)/documents/categories/legacy_${c.id}`;
    const fields = {
      name: c.name,
      legacyId: c.id,
      migratedAt: migrationTimestamp,
      createdAt: formatIso(c.created_at),
      updatedAt: formatIso(c.updated_at),
    };
    writes.push({
      update: { name: docPath, fields: toFirestoreFields(fields) },
    });
  }

  // B. Produk -> products/legacy_{id}
  for (const p of products) {
    const docPath = `projects/${PROJECT_ID}/databases/(default)/documents/products/legacy_${p.id}`;
    const fields = {
      categoryId: p.category_id ? `legacy_${p.category_id}` : null,
      name: p.name,
      defaultPrice: Math.round(Number(p.default_price || 0)),
      unit: p.unit || 'pcs',
      isActive: p.is_active === 1 || p.is_active === true,
      legacyId: p.id,
      migratedAt: migrationTimestamp,
      createdAt: formatIso(p.created_at),
      updatedAt: formatIso(p.updated_at),
    };
    writes.push({
      update: { name: docPath, fields: toFirestoreFields(fields) },
    });
  }

  // C. Pelanggan -> customers/legacy_{id}
  const customerMap = new Map();
  for (const cust of customers) {
    customerMap.set(cust.id, cust.name);
    const docPath = `projects/${PROJECT_ID}/databases/(default)/documents/customers/legacy_${cust.id}`;
    const fields = {
      name: cust.name,
      phone: cust.phone ? cust.phone.trim() : null,
      notes: cust.notes ? cust.notes.trim() : null,
      isActive: cust.is_active === 1 || cust.is_active === true,
      legacyId: cust.id,
      migratedAt: migrationTimestamp,
      createdAt: formatIso(cust.created_at),
      updatedAt: formatIso(cust.updated_at),
    };
    writes.push({
      update: { name: docPath, fields: toFirestoreFields(fields) },
    });
  }

  // Mapping items per transaction
  const itemsByTx = new Map();
  let negativeItemsCount = 0;
  let negativeTotalAmount = 0;

  for (const item of transactionItems) {
    const txId = item.transaction_id;
    if (!itemsByTx.has(txId)) itemsByTx.set(txId, []);
    itemsByTx.get(txId).push(item);

    const subtotal = Math.round(Number(item.subtotal || 0));
    if (subtotal < 0) {
      negativeItemsCount++;
      negativeTotalAmount += Math.abs(subtotal);
    }
  }

  // Tracking rollup agregasi harian & sequence counters
  const dailyRollup = new Map(); // dateStr => { saleCount, saleTotal, paidTotal, unpaidTotal, expenseCount, expenseTotal }
  const dailyCounters = new Map(); // dateStr => maxSequence

  let totalOmset = 0;

  // D. Transaksi & Subkoleksi Items
  for (const tx of transactions) {
    const txDocPath = `projects/${PROJECT_ID}/databases/(default)/documents/transactions/legacy_${tx.id}`;
    const txItems = itemsByTx.get(tx.id) || [];
    const dateStr = formatDateStr(tx.transaction_date);
    const totalAmount = Math.round(Number(tx.total_amount || 0));
    totalOmset += totalAmount;

    // Hitung counter sequence dari nomor bon (contoh: INV-20261012-005 -> 5)
    const match = (tx.transaction_number || '').match(/INV-\d{8}-(\d+)/);
    if (match) {
      const seq = parseInt(match[1], 10);
      const curr = dailyCounters.get(dateStr) || 0;
      if (seq > curr) dailyCounters.set(dateStr, seq);
    }

    // Hitung rollup daily_summary
    if (!dailyRollup.has(dateStr)) {
      dailyRollup.set(dateStr, {
        date: dateStr,
        saleCount: 0,
        saleTotal: 0,
        paidTotal: 0,
        unpaidTotal: 0,
        expenseCount: 0,
        expenseTotal: 0,
      });
    }
    const r = dailyRollup.get(dateStr);
    r.saleCount += 1;
    r.saleTotal += totalAmount;
    if (tx.payment_status === 'paid') {
      r.paidTotal += totalAmount;
    } else {
      r.unpaidTotal += totalAmount;
    }

    const txFields = {
      number: tx.transaction_number,
      date: dateStr,
      customerId: tx.customer_id ? `legacy_${tx.customer_id}` : null,
      customerName: tx.customer_id ? (customerMap.get(tx.customer_id) || null) : null,
      totalAmount: totalAmount,
      status: tx.status || 'draft',
      paymentStatus: tx.payment_status || 'unpaid',
      type: tx.type || 'sale',
      notes: tx.notes ? tx.notes.trim() : null,
      itemCount: txItems.length,
      legacyId: tx.id,
      migratedAt: migrationTimestamp,
      createdAt: formatIso(tx.created_at),
      updatedAt: formatIso(tx.updated_at),
    };
    writes.push({
      update: { name: txDocPath, fields: toFirestoreFields(txFields) },
    });

    // Subkoleksi items
    for (const it of txItems) {
      const itemDocPath = `${txDocPath}/items/legacy_${it.id}`;
      const subtotal = Math.round(Number(it.subtotal || 0));
      const itemFields = {
        productId: it.product_id ? `legacy_${it.product_id}` : null,
        productName: it.product_name,
        description: it.description ? it.description.trim() : null,
        quantity: Math.round(Number(it.quantity || 1)),
        unit: it.unit || 'pcs',
        unitPrice: Math.round(Number(it.unit_price || 0)),
        subtotal: subtotal,
        legacyId: it.id,
        migratedAt: migrationTimestamp,
        createdAt: formatIso(it.created_at),
        updatedAt: formatIso(it.updated_at),
      };
      writes.push({
        update: { name: itemDocPath, fields: toFirestoreFields(itemFields) },
      });

      // E. Sinkronisasi Potongan Bon (subtotal < 0) ke koleksi `expenses`
      if (subtotal < 0) {
        const expDocPath = `projects/${PROJECT_ID}/databases/(default)/documents/expenses/bon_${tx.id}_${it.id}`;
        const absAmount = Math.abs(subtotal);
        const expFields = {
          date: dateStr,
          title: it.product_name,
          category: 'Potongan Bon',
          amount: absAmount,
          source: 'bon',
          transactionId: `legacy_${tx.id}`,
          transactionNumber: tx.transaction_number,
          syncKey: `bon:${tx.id}:${it.id}`,
          notes: it.description ? it.description.trim() : null,
          legacyId: null,
          migratedAt: migrationTimestamp,
          createdAt: formatIso(it.created_at),
          updatedAt: formatIso(it.updated_at),
        };
        writes.push({
          update: { name: expDocPath, fields: toFirestoreFields(expFields) },
        });

        // Tambah ke rollup expense harian
        r.expenseCount += 1;
        r.expenseTotal += absAmount;
      }
    }
  }

  // F. Pengeluaran Manual dari tabel `expenses`
  for (const exp of expenses) {
    const expDocPath = `projects/${PROJECT_ID}/databases/(default)/documents/expenses/legacy_${exp.id}`;
    const dateStr = formatDateStr(exp.expense_date);
    const amount = Math.round(Number(exp.amount || 0));

    if (!dailyRollup.has(dateStr)) {
      dailyRollup.set(dateStr, {
        date: dateStr,
        saleCount: 0,
        saleTotal: 0,
        paidTotal: 0,
        unpaidTotal: 0,
        expenseCount: 0,
        expenseTotal: 0,
      });
    }
    const r = dailyRollup.get(dateStr);
    r.expenseCount += 1;
    r.expenseTotal += amount;

    const expFields = {
      date: dateStr,
      title: exp.title,
      category: exp.category ? exp.category.trim() : null,
      amount: amount,
      source: 'manual',
      transactionId: null,
      syncKey: null,
      notes: exp.notes ? exp.notes.trim() : null,
      legacyId: exp.id,
      migratedAt: migrationTimestamp,
      createdAt: formatIso(exp.created_at),
      updatedAt: formatIso(exp.updated_at),
    };
    writes.push({
      update: { name: expDocPath, fields: toFirestoreFields(expFields) },
    });
  }

  // G. Dokumen Rollup `daily_summary/{yyyy-MM-dd}`
  for (const [dStr, rollup] of dailyRollup.entries()) {
    const summaryDocPath = `projects/${PROJECT_ID}/databases/(default)/documents/daily_summary/${dStr}`;
    const summaryFields = {
      date: rollup.date,
      saleCount: rollup.saleCount,
      saleTotal: rollup.saleTotal,
      paidTotal: rollup.paidTotal,
      unpaidTotal: rollup.unpaidTotal,
      expenseCount: rollup.expenseCount,
      expenseTotal: rollup.expenseTotal,
      updatedAt: migrationTimestamp,
    };
    writes.push({
      update: { name: summaryDocPath, fields: toFirestoreFields(summaryFields) },
    });
  }

  // H. Dokumen Counter Penomoran `counters/inv_{yyyyMMdd}`
  for (const [dStr, maxSeq] of dailyCounters.entries()) {
    const counterDocId = `inv_${dStr.replace(/-/g, '')}`;
    const counterDocPath = `projects/${PROJECT_ID}/databases/(default)/documents/counters/${counterDocId}`;
    const counterFields = {
      currentSequence: maxSeq,
      updatedAt: migrationTimestamp,
    };
    writes.push({
      update: { name: counterDocPath, fields: toFirestoreFields(counterFields) },
    });
  }

  console.log('\n--- RENCANA OPERASI DOKUMEN FIRESTORE ---');
  console.log(`Total Dokumen yang Ditulis: ${writes.length} dokumen`);
  console.log(`- Kategori               : ${categories.length}`);
  console.log(`- Produk                 : ${products.length}`);
  console.log(`- Pelanggan              : ${customers.length}`);
  console.log(`- Transaksi (Bon)        : ${transactions.length}`);
  console.log(`- Item Transaksi         : ${transactionItems.length}`);
  console.log(`- Pengeluaran Manual     : ${expenses.length}`);
  console.log(`- Pengeluaran PotonganBon: ${negativeItemsCount} (Total: Rp ${negativeTotalAmount.toLocaleString('id-ID')})`);
  console.log(`- Ringkasan Harian       : ${dailyRollup.size} hari`);
  console.log(`- Counter Invoice        : ${dailyCounters.size} hari`);
  console.log(`- Total Omset Bon        : Rp ${totalOmset.toLocaleString('id-ID')}`);

  if (isDryRun) {
    console.log('\n[DRY RUN BERHASIL] Validasi data selesai. Tidak ada data yang ditulis ke Firestore.');
    console.log('Untuk mengeksekusi penulisan aktual, jalankan tanpa parameter --dry-run:');
    console.log('  node tools/migrate/migrate.js');
    return;
  }

  // 4. Eksekusi Batch Writing Idempoten ke Firestore
  console.log('\n--- MEMULAI PENULISAN BATCH KE CLOUD FIRESTORE ---');
  const totalBatches = Math.ceil(writes.length / BATCH_SIZE);
  console.log(`Jumlah Batch: ${totalBatches} batch (maks ${BATCH_SIZE} per commit)\n`);

  for (let i = 0; i < totalBatches; i++) {
    const chunk = writes.slice(i * BATCH_SIZE, (i + 1) * BATCH_SIZE);
    process.stdout.write(`Menulis Batch ${i + 1}/${totalBatches} (${chunk.length} dokumen)... `);
    const start = Date.now();
    await commitBatch(token, chunk);
    const dur = Date.now() - start;
    console.log(`SELESAI (${dur} ms)`);
  }

  console.log('\n' + '='.repeat(70));
  console.log(`MIGRASI DATA KE CLOUD FIRESTORE SELESAI DENGAN SUKSES!`);
  console.log(`Total dokumen tersimpan: ${writes.length}`);
  console.log('='.repeat(70));
}

run().catch((err) => {
  console.error('\n[FATAL ERROR]:', err);
  process.exit(1);
});
