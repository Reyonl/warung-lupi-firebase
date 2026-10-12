#!/usr/bin/env node

/**
 * Script Ekspor Data Firestore ke CSV (Warung Lupi)
 * Mengunduh transaksi, item transaksi, dan pengeluaran ke file CSV untuk arsip/analisis offline.
 *
 * Penggunaan:
 *   node tools/export_csv.js
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'warunglupi-staging-fa841';

function getFirebaseToken() {
  const configPath = path.join(
    process.env.USERPROFILE || process.env.HOME || '',
    '.config',
    'configstore',
    'firebase-tools.json'
  );
  if (!fs.existsSync(configPath)) {
    throw new Error('Kredensial Firebase CLI tidak ditemukan. Jalankan `firebase login` terlebih dahulu.');
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  return config.tokens.access_token;
}

function parseFirestoreValue(f) {
  if (!f) return null;
  if ('stringValue' in f) return f.stringValue;
  if ('integerValue' in f) return parseInt(f.integerValue, 10);
  if ('doubleValue' in f) return f.doubleValue;
  if ('booleanValue' in f) return f.booleanValue;
  if ('timestampValue' in f) return f.timestampValue;
  if ('nullValue' in f) return null;
  return null;
}

function parseFirestoreDocument(doc) {
  const data = {};
  if (doc.fields) {
    for (const [k, v] of Object.entries(doc.fields)) {
      data[k] = parseFirestoreValue(v);
    }
  }
  return data;
}

async function fetchCollection(token, collectionPath) {
  let docs = [];
  let pageToken = '';

  do {
    const q = pageToken ? `?pageToken=${pageToken}` : '';
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionPath}${q}`;

    const res = await new Promise((resolve, reject) => {
      https.get(
        url,
        { headers: { Authorization: `Bearer ${token}` } },
        (resp) => {
          let body = '';
          resp.on('data', (c) => (body += c));
          resp.on('end', () => {
            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              resolve(JSON.parse(body || '{}'));
            } else {
              reject(new Error(`Fetch ${collectionPath} gagal (${resp.statusCode}): ${body}`));
            }
          });
        }
      ).on('error', reject);
    });

    if (res.documents) {
      docs = docs.concat(res.documents);
    }
    pageToken = res.nextPageToken;
  } while (pageToken);

  return docs;
}

function escapeCsv(val) {
  if (val === null || val === undefined) return '';
  const str = String(val);
  if (str.includes(',') || str.includes('"') || str.includes('\n') || str.includes('\r')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function toCsv(rows, headers) {
  const headerLine = headers.map(escapeCsv).join(',');
  const lines = rows.map((r) => headers.map((h) => escapeCsv(r[h])).join(','));
  return [headerLine, ...lines].join('\r\n');
}

async function main() {
  const token = getFirebaseToken();
  const exportDir = path.join(__dirname, '..', 'exports');
  if (!fs.existsSync(exportDir)) {
    fs.mkdirSync(exportDir, { recursive: true });
  }

  const dateStr = new Date().toISOString().slice(0, 10).replace(/-/g, '');

  console.log(`Mengambil data dari Cloud Firestore (${PROJECT_ID})...`);

  // 1. Customers map
  const rawCustomers = await fetchCollection(token, 'customers');
  const customerMap = {};
  for (const c of rawCustomers) {
    const d = parseFirestoreDocument(c);
    const id = path.basename(c.name);
    customerMap[id] = d.name || `Pelanggan #${id}`;
  }

  // 2. Transactions
  const rawTransactions = await fetchCollection(token, 'transactions');
  const transactions = [];
  const allItems = [];

  for (const t of rawTransactions) {
    const docId = path.basename(t.name);
    const data = parseFirestoreDocument(t);
    const custId = data.customerId || data.customer_id;
    const custName = data.customerName || (custId ? (customerMap[String(custId)] || `ID ${custId}`) : 'Umum (Tanpa Nama)');

    transactions.push({
      id: docId,
      nomor_invoice: data.number || data.transaction_number || '',
      tanggal: data.date || data.transaction_date || '',
      pelanggan_id: custId || '',
      nama_pelanggan: custName,
      total_amount: data.totalAmount ?? data.total_amount ?? 0,
      status: data.status || '',
      payment_status: data.paymentStatus || data.payment_status || '',
      type: data.type || 'sale',
      catatan: data.notes || '',
    });

    // Subkoleksi items
    const rawItems = await fetchCollection(token, `transactions/${docId}/items`);
    for (const item of rawItems) {
      const iData = parseFirestoreDocument(item);
      allItems.push({
        transaksi_id: docId,
        nomor_invoice: data.number || data.transaction_number || '',
        item_id: path.basename(item.name),
        nama_produk: iData.productName || iData.product_name || '',
        qty: iData.quantity ?? iData.qty ?? 0,
        unit: iData.unit || 'pcs',
        harga_satuan: iData.unitPrice ?? iData.price ?? 0,
        subtotal: iData.subtotal || 0,
        catatan: iData.notes || iData.description || '',
      });
    }
  }

  // 3. Expenses
  const rawExpenses = await fetchCollection(token, 'expenses');
  const expenses = [];
  for (const e of rawExpenses) {
    const d = parseFirestoreDocument(e);
    expenses.push({
      id: path.basename(e.name),
      tanggal: d.date || d.expense_date || '',
      kategori: d.category || '',
      deskripsi: d.description || d.notes || '',
      nominal: d.amount || 0,
      sumber: d.source || '',
      nomor_invoice: d.transactionNumber || d.transaction_number || '',
      sync_key: d.syncKey || d.sync_key || '',
    });
  }

  // Write CSV files
  const txFile = path.join(exportDir, `transaksi_${dateStr}.csv`);
  fs.writeFileSync(
    txFile,
    toCsv(transactions, [
      'id',
      'nomor_invoice',
      'tanggal',
      'pelanggan_id',
      'nama_pelanggan',
      'total_amount',
      'status',
      'payment_status',
      'type',
      'catatan',
    ]),
    'utf8'
  );

  const itemsFile = path.join(exportDir, `item_transaksi_${dateStr}.csv`);
  fs.writeFileSync(
    itemsFile,
    toCsv(allItems, [
      'transaksi_id',
      'nomor_invoice',
      'item_id',
      'nama_produk',
      'qty',
      'unit',
      'harga_satuan',
      'subtotal',
      'catatan',
    ]),
    'utf8'
  );

  const expFile = path.join(exportDir, `pengeluaran_${dateStr}.csv`);
  fs.writeFileSync(
    expFile,
    toCsv(expenses, [
      'id',
      'tanggal',
      'kategori',
      'deskripsi',
      'nominal',
      'sumber',
      'nomor_invoice',
      'sync_key',
    ]),
    'utf8'
  );

  console.log('\n==================================================');
  console.log('EKSPOR CSV BERHASIL SELESAI');
  console.log('==================================================');
  console.log(`1. Transaksi     : ${transactions.length} baris ➔ ${path.relative(process.cwd(), txFile)}`);
  console.log(`2. Item Transaksi: ${allItems.length} baris ➔ ${path.relative(process.cwd(), itemsFile)}`);
  console.log(`3. Pengeluaran   : ${expenses.length} baris ➔ ${path.relative(process.cwd(), expFile)}`);
  console.log('==================================================\n');
}

main().catch((err) => {
  console.error('[ERROR EKSPOR]:', err.message);
  process.exit(1);
});
