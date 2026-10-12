#!/usr/bin/env node

/**
 * Script Pengujian Security Rules Cloud Firestore
 * Memvalidasi kepatuhan firestore.rules di warunglupi-staging-fa841
 *
 * Penggunaan:
 *   node tools/migrate/test_rules.js
 */

const https = require('https');

const PROJECT_ID = 'warunglupi-staging-fa841';
const API_KEY = 'AIzaSyBlViJLEEtem32nJ_lupYxRqW6zwd2Xmlw';
const BASE_FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function httpRequest(url, options = {}, postData = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        let json = null;
        try {
          json = JSON.parse(body || '{}');
        } catch (_) {}
        resolve({
          status: res.statusCode,
          headers: res.headers,
          data: json,
          raw: body,
        });
      });
    });
    req.on('error', reject);
    if (postData) {
      req.write(typeof postData === 'string' ? postData : JSON.stringify(postData));
    }
    req.end();
  });
}

async function getAnonymousToken() {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
  const res = await httpRequest(url, { method: 'POST', headers: { 'Content-Type': 'application/json' } }, { returnSecureToken: true });
  if (res.status !== 200 || !res.data.idToken) {
    throw new Error(`Gagal mendapatkan anonymous token (${res.status}): ${res.raw}`);
  }
  return res.data.idToken;
}

async function run() {
  console.log('='.repeat(70));
  console.log('PENGUJIAN SECURITY RULES CLOUD FIRESTORE');
  console.log(`Target: ${PROJECT_ID} (asia-southeast2)`);
  console.log('='.repeat(70));

  let anonToken = null;
  try {
    process.stdout.write('Mendapatkan Anonymous User Token dari Firebase Auth... ');
    anonToken = await getAnonymousToken();
    console.log('SUKSES.');
  } catch (err) {
    console.error('GAGAL:', err.message);
    process.exit(1);
  }

  const results = [];

  async function testCase(name, fn) {
    process.stdout.write(`- [UJI] ${name}... `);
    try {
      const pass = await fn();
      if (pass) {
        console.log('LULUS (PASSED)');
        results.push({ name, status: 'PASSED' });
      } else {
        console.log('GAGAL (FAILED)');
        results.push({ name, status: 'FAILED' });
      }
    } catch (e) {
      console.log(`ERROR: ${e.message}`);
      results.push({ name, status: 'ERROR', error: e.message });
    }
  }

  // 1. Unauthenticated Read ditolak
  await testCase('Unauthenticated GET /customers ditolak (403 PERMISSION_DENIED)', async () => {
    const res = await httpRequest(`${BASE_FIRESTORE}/customers`);
    return res.status === 403;
  });

  // 2. Unauthenticated Write ditolak
  await testCase('Unauthenticated POST /transactions ditolak (403 PERMISSION_DENIED)', async () => {
    const res = await httpRequest(
      `${BASE_FIRESTORE}/transactions`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' } },
      { fields: { number: { stringValue: 'INV-20261012-999' } } }
    );
    return res.status === 403;
  });

  // 3. Authenticated Read diizinkan
  await testCase('Authenticated Anonymous GET /customers diizinkan (200 OK)', async () => {
    const res = await httpRequest(`${BASE_FIRESTORE}/customers`, {
      headers: { Authorization: `Bearer ${anonToken}` },
    });
    return res.status === 200;
  });

  await testCase('Authenticated Anonymous GET /products diizinkan (200 OK)', async () => {
    const res = await httpRequest(`${BASE_FIRESTORE}/products`, {
      headers: { Authorization: `Bearer ${anonToken}` },
    });
    return res.status === 200;
  });

  await testCase('Authenticated Anonymous GET /transactions diizinkan (200 OK)', async () => {
    const res = await httpRequest(`${BASE_FIRESTORE}/transactions`, {
      headers: { Authorization: `Bearer ${anonToken}` },
    });
    return res.status === 200;
  });

  // 4. Schema Validation: Harga negatif ditolak
  await testCase('Validasi Skema: POST /products dengan harga negatif ditolak (403)', async () => {
    const res = await httpRequest(
      `${BASE_FIRESTORE}/products`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${anonToken}`,
          'Content-Type': 'application/json',
        },
      },
      {
        fields: {
          name: { stringValue: 'Produk Uji Tidak Valid' },
          defaultPrice: { integerValue: '-5000' },
          unit: { stringValue: 'pcs' },
          isActive: { booleanValue: true },
        },
      }
    );
    return res.status === 403;
  });

  // 5. Schema Validation: Format nomor bon tidak sesuai ditolak
  await testCase('Validasi Skema: POST /transactions dengan format invoice salah ditolak (403)', async () => {
    const res = await httpRequest(
      `${BASE_FIRESTORE}/transactions`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${anonToken}`,
          'Content-Type': 'application/json',
        },
      },
      {
        fields: {
          number: { stringValue: 'BON-SALAH-FORMAT' },
          date: { stringValue: '2026-10-12' },
          totalAmount: { integerValue: '50000' },
          status: { stringValue: 'draft' },
          paymentStatus: { stringValue: 'unpaid' },
        },
      }
    );
    return res.status === 403;
  });

  // 6. Schema Validation: Format tanggal salah ditolak
  await testCase('Validasi Skema: POST /transactions dengan format tanggal salah (12-10-2026) ditolak (403)', async () => {
    const res = await httpRequest(
      `${BASE_FIRESTORE}/transactions`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${anonToken}`,
          'Content-Type': 'application/json',
        },
      },
      {
        fields: {
          number: { stringValue: 'INV-20261012-099' },
          date: { stringValue: '12-10-2026' }, // Format salah, harus yyyy-MM-dd
          totalAmount: { integerValue: '50000' },
          status: { stringValue: 'draft' },
          paymentStatus: { stringValue: 'unpaid' },
        },
      }
    );
    return res.status === 403;
  });

  // 7. Pembuatan dokumen valid diizinkan
  let testCustDocName = null;
  await testCase('Pembuatan Pelanggan Valid oleh Auth diizinkan (200 OK)', async () => {
    const res = await httpRequest(
      `${BASE_FIRESTORE}/customers`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${anonToken}`,
          'Content-Type': 'application/json',
        },
      },
      {
        fields: {
          name: { stringValue: 'Test Pelanggan Rules Valid' },
          isActive: { booleanValue: true },
        },
      }
    );
    if (res.status === 200 && res.data && res.data.name) {
      testCustDocName = res.data.name;
      return true;
    }
    return false;
  });

  // Pembersihan dokumen uji pelanggan
  if (testCustDocName) {
    const docPath = testCustDocName.split('/documents/').pop();
    await httpRequest(`${BASE_FIRESTORE}/${docPath}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${anonToken}` },
    });
  }

  // 8. Proteksi Mutasi Langsung Expense Potongan Bon
  await testCase('Proteksi Integritas: Update langsung pada expense bon ditolak (403)', async () => {
    // Ambil sample expense bon yang sudah ada
    const list = await httpRequest(`${BASE_FIRESTORE}/expenses`, {
      headers: { Authorization: `Bearer ${anonToken}` },
    });
    if (!list.data || !list.data.documents || list.data.documents.length === 0) {
      return false;
    }
    const bonExp = list.data.documents.find((d) => d.fields && d.fields.source && d.fields.source.stringValue === 'bon');
    if (!bonExp) return false;

    const docPath = bonExp.name.split('/documents/').pop();
    const updateRes = await httpRequest(
      `${BASE_FIRESTORE}/${docPath}`,
      {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${anonToken}`,
          'Content-Type': 'application/json',
        },
      },
      {
        fields: {
          ...bonExp.fields,
          title: { stringValue: 'Judul Diubah Ilegal' },
        },
      }
    );
    return updateRes.status === 403;
  });

  // 9. Koleksi tidak terdaftar ditolak
  await testCase('Fallback Whitelist: Write ke koleksi asing ditolak (403 PERMISSION_DENIED)', async () => {
    const res = await httpRequest(
      `${BASE_FIRESTORE}/_koleksi_rahasia_ilegal`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${anonToken}`,
          'Content-Type': 'application/json',
        },
      },
      {
        fields: {
          rahasia: { stringValue: 'bocor' },
        },
      }
    );
    return res.status === 403;
  });

  console.log('\n' + '='.repeat(70));
  console.log('RINGKASAN HASIL PENGUJIAN SECURITY RULES');
  console.log('='.repeat(70));
  console.table(results);

  const allPassed = results.every((r) => r.status === 'PASSED');
  if (allPassed) {
    console.log('\n[HASIL]: SEMUA 9 SKENARIO SECURITY RULES LULUS 100%!');
  } else {
    console.error('\n[HASIL]: ADA SKENARIO YANG GAGAL!');
    process.exit(1);
  }
}

run().catch((err) => {
  console.error('\n[FATAL ERROR]:', err);
  process.exit(1);
});
