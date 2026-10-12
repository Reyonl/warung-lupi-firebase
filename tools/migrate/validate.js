#!/usr/bin/env node

/**
 * Script Validasi Data: Memverifikasi Hasil Migrasi di Cloud Firestore Staging
 * Warung Lupi Staging (warunglupi-staging-fa841)
 *
 * Penggunaan:
 *   node tools/migrate/validate.js
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

function getFirebaseToken() {
  const configPath = path.join(
    process.env.USERPROFILE || process.env.HOME || '',
    '.config',
    'configstore',
    'firebase-tools.json'
  );
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

// Helper: ambil seluruh dokumen dalam sebuah koleksi melalui REST API
async function fetchCollection(token, collectionPath) {
  let docs = [];
  let pageToken = '';

  do {
    const q = pageToken ? `?pageToken=${pageToken}` : '';
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionPath}${q}`;

    const res = await new Promise((resolve, reject) => {
      https.get(
        url,
        {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
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

    if (res.documents && Array.isArray(res.documents)) {
      for (const d of res.documents) {
        const id = d.name.split('/').pop();
        docs.push({ id, ...parseFirestoreDocument(d) });
      }
    }
    pageToken = res.nextPageToken || '';
  } while (pageToken);

  return docs;
}

async function run() {
  console.log('='.repeat(70));
  console.log('VALIDASI INTEGRITAS DATA FIRESTORE STAGING');
  console.log(`Project: ${PROJECT_ID}`);
  console.log('='.repeat(70));

  const token = getFirebaseToken();

  // 1. Ambil data dari MySQL snapshot
  const conn = await mysql.createConnection(DB_CONFIG);
  const [dbCats] = await conn.query('SELECT count(*) as c FROM categories');
  const [dbProds] = await conn.query('SELECT count(*) as c FROM products');
  const [dbCusts] = await conn.query('SELECT count(*) as c FROM customers');
  const [dbTxs] = await conn.query('SELECT count(*) as c, sum(total_amount) as total FROM transactions');
  const [dbItems] = await conn.query('SELECT count(*) as c, sum(subtotal) as total FROM transaction_items');
  const [dbNegItems] = await conn.query('SELECT count(*) as c, sum(abs(subtotal)) as total FROM transaction_items WHERE subtotal < 0');
  await conn.end();

  // 2. Ambil data dari Cloud Firestore
  process.stdout.write('Mengambil koleksi categories dari Firestore... ');
  const fsCats = await fetchCollection(token, 'categories');
  console.log(`${fsCats.length} dokumen.`);

  process.stdout.write('Mengambil koleksi products dari Firestore... ');
  const fsProds = await fetchCollection(token, 'products');
  console.log(`${fsProds.length} dokumen.`);

  process.stdout.write('Mengambil koleksi customers dari Firestore... ');
  const fsCusts = await fetchCollection(token, 'customers');
  console.log(`${fsCusts.length} dokumen.`);

  process.stdout.write('Mengambil koleksi transactions dari Firestore... ');
  const fsTxs = await fetchCollection(token, 'transactions');
  console.log(`${fsTxs.length} dokumen.`);

  process.stdout.write('Mengambil subkoleksi items dari seluruh transaksi... ');
  let fsItemsCount = 0;
  let fsItemsSubtotal = 0;
  for (const tx of fsTxs) {
    const items = await fetchCollection(token, `transactions/${tx.id}/items`);
    fsItemsCount += items.length;
    for (const it of items) {
      fsItemsSubtotal += it.subtotal || 0;
    }
  }
  console.log(`${fsItemsCount} dokumen.`);

  process.stdout.write('Mengambil koleksi expenses dari Firestore... ');
  const fsExpenses = await fetchCollection(token, 'expenses');
  console.log(`${fsExpenses.length} dokumen.`);

  process.stdout.write('Mengambil koleksi daily_summary dari Firestore... ');
  const fsDaily = await fetchCollection(token, 'daily_summary');
  console.log(`${fsDaily.length} dokumen.`);

  process.stdout.write('Mengambil koleksi counters dari Firestore... ');
  const fsCounters = await fetchCollection(token, 'counters');
  console.log(`${fsCounters.length} dokumen.`);

  // Hitung total di Firestore
  let fsTotalOmset = 0;
  for (const tx of fsTxs) {
    fsTotalOmset += tx.totalAmount || 0;
  }

  let fsExpenseTotal = 0;
  for (const exp of fsExpenses) {
    fsExpenseTotal += exp.amount || 0;
  }

  let fsDailySaleTotal = 0;
  let fsDailyExpenseTotal = 0;
  for (const d of fsDaily) {
    fsDailySaleTotal += d.saleTotal || 0;
    fsDailyExpenseTotal += d.expenseTotal || 0;
  }

  console.log('\n' + '='.repeat(70));
  console.log('TABEL PERBANDINGAN & VALIDASI: MYSQL SNAPSHOT VS CLOUD FIRESTORE');
  console.log('='.repeat(70));

  const rows = [
    {
      Entitas: 'Kategori',
      'MySQL Snapshot': `${dbCats[0].c} baris`,
      'Firestore Staging': `${fsCats.length} dokumen`,
      Status: dbCats[0].c === fsCats.length ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Produk',
      'MySQL Snapshot': `${dbProds[0].c} baris`,
      'Firestore Staging': `${fsProds.length} dokumen`,
      Status: dbProds[0].c === fsProds.length ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Pelanggan',
      'MySQL Snapshot': `${dbCusts[0].c} baris`,
      'Firestore Staging': `${fsCusts.length} dokumen`,
      Status: dbCusts[0].c === fsCusts.length ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Transaksi (Bon)',
      'MySQL Snapshot': `${dbTxs[0].c} baris`,
      'Firestore Staging': `${fsTxs.length} dokumen`,
      Status: dbTxs[0].c === fsTxs.length ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Item Transaksi',
      'MySQL Snapshot': `${dbItems[0].c} baris`,
      'Firestore Staging': `${fsItemsCount} dokumen`,
      Status: dbItems[0].c === fsItemsCount ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Total Omset Bon',
      'MySQL Snapshot': `Rp ${Number(dbTxs[0].total).toLocaleString('id-ID')}`,
      'Firestore Staging': `Rp ${fsTotalOmset.toLocaleString('id-ID')}`,
      Status: Number(dbTxs[0].total) === fsTotalOmset ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Sum Subtotal Items',
      'MySQL Snapshot': `Rp ${Number(dbItems[0].total).toLocaleString('id-ID')}`,
      'Firestore Staging': `Rp ${fsItemsSubtotal.toLocaleString('id-ID')}`,
      Status: Number(dbItems[0].total) === fsItemsSubtotal ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Expense Potongan Bon',
      'MySQL Snapshot': `${dbNegItems[0].c} item (Rp ${Number(dbNegItems[0].total).toLocaleString('id-ID')})`,
      'Firestore Staging': `${fsExpenses.length} dok (Rp ${fsExpenseTotal.toLocaleString('id-ID')})`,
      Status: (dbNegItems[0].c === fsExpenses.length && Number(dbNegItems[0].total) === fsExpenseTotal) ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Rollup daily_summary',
      'MySQL Snapshot': '6 tanggal transaksi',
      'Firestore Staging': `${fsDaily.length} dok (Omset: Rp ${fsDailySaleTotal.toLocaleString('id-ID')})`,
      Status: (fsDaily.length === 6 && fsDailySaleTotal === fsTotalOmset) ? 'COCOK 100%' : 'SELISIH',
    },
    {
      Entitas: 'Counters inv_*',
      'MySQL Snapshot': '6 tanggal transaksi',
      'Firestore Staging': `${fsCounters.length} counter dok`,
      Status: fsCounters.length === 6 ? 'COCOK 100%' : 'SELISIH',
    },
  ];

  console.table(rows);

  const allPassed = rows.every((r) => r.Status === 'COCOK 100%');
  if (allPassed) {
    console.log('\n[HASIL VALIDASI]: SEMUA DATA IDENTIK & COCOK 100% DENGAN SNAPSHOT!');
  } else {
    console.error('\n[HASIL VALIDASI]: DITEMUKAN SELISIH DATA!');
    process.exit(1);
  }
}

run().catch((err) => {
  console.error('\n[FATAL ERROR]:', err);
  process.exit(1);
});
