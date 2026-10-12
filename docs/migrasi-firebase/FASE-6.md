# Laporan Fase 6: Script Migrasi Idempotent & Eksekusi Staging

**Tanggal Eksekusi:** 12 Oktober 2026  
**Branch:** `feat/firebase-migration`  
**Target Environment:** Firebase Staging (`warunglupi-staging-fa841`, Region `asia-southeast2` Jakarta)  
**Status Fase 6:** **SELESAI, TEREKSEKUSI, DAN TERVALIDASI 100%**

---

## 1. Ringkasan Eksekutif

Pada Fase 6, script migrasi database idempoten telah berhasil dibuat di [`tools/migrate/migrate.js`](file:///d:/laragon/www/warung_lupi_firebase/tools/migrate/migrate.js) dan dieksekusi langsung ke project Cloud Firestore Staging (`warunglupi-staging-fa841`).

Seluruh data snapshot dari MySQL lokal `warung_migrasi_snapshot` (14 transaksi, 195 items, omset Rp 2.435.000) telah bermigrasi secara utuh ke Cloud Firestore dengan **kecocokan 100% tanpa selisih data**. Tidak ada kontak ke server produksi EC2, hostinger lama, maupun database lokal `warung_lupi`.

---

## 2. Fitur & Keamanan Script Migrasi

1. **Idempotensi Penuh:**
   - Semua dokumen Firestore menggunakan ID deterministik (`categories/legacy_{id}`, `products/legacy_{id}`, `customers/legacy_{id}`, `transactions/legacy_{id}`, `items/legacy_{id}`, `expenses/bon_{txId}_{itemId}`).
   - Menjalankan script berulang kali dijamin tidak akan pernah membuat data duplikat atau corrupt.
2. **Mode `--dry-run` Wajib:**
   - Menyediakan simulasi pembacaan data, validasi relasi, dan perhitungan ringkasan sebelum penulisan aktual.
3. **Batch Writing Otomatis:**
   - Mengelompokkan operasi tulis maksimal 400 dokumen per batch commit (aman di bawah limit 500 Firestore).
4. **Otomatisasi Potongan Bon & Agregasi:**
   - 7 item bernilai negatif (`subtotal < 0`) otomatis diubah menjadi dokumen `expenses` bersumber `bon`.
   - Ringkasan harian `daily_summary/{yyyy-MM-dd}` dan sequence counter `counters/inv_{yyyyMMdd}` otomatis terisi untuk 6 tanggal transaksi.
5. **Autentikasi Terintegrasi & Nol Kebocoran Kredensial:**
   - Memanfaatkan sesi token OAuth dari Firebase CLI yang sudah login di mesin pengguna. Tidak ada file service account JSON, kata sandi, atau token rahasia yang disimpan atau di-commit.

---

## 3. Rincian Eksekusi & Jumlah Dokumen

- **Total Dokumen Ditulis ke Firestore:** **426 dokumen** dalam 2 batch:
  - Batch 1: 400 dokumen (durasi 1.217 ms)
  - Batch 2: 26 dokumen (durasi 133 ms)
- **Komposisi Dokumen:**
  - `categories`: 5 dokumen
  - `products`: 155 dokumen
  - `customers`: 38 dokumen
  - `transactions`: 14 dokumen
  - `transactions/{id}/items`: 195 dokumen
  - `expenses`: 7 dokumen (potongan bon total Rp 326.000)
  - `daily_summary`: 6 dokumen
  - `counters`: 6 dokumen

---

## 4. Hasil Validasi Otomatis (`validate.js`)

Script validasi [`tools/migrate/validate.js`](file:///d:/laragon/www/warung_lupi_firebase/tools/migrate/validate.js) membandingkan langsung antara isi MySQL snapshot lokal dengan isi Cloud Firestore di `warunglupi-staging-fa841`:

```text
======================================================================
TABEL PERBANDINGAN & VALIDASI: MYSQL SNAPSHOT VS CLOUD FIRESTORE
======================================================================
Entitas                MySQL Snapshot          Firestore Staging        Status
----------------------------------------------------------------------------------
Kategori               5 baris                 5 dokumen                COCOK 100%
Produk                 155 baris               155 dokumen              COCOK 100%
Pelanggan              38 baris                38 dokumen               COCOK 100%
Transaksi (Bon)        14 baris                14 dokumen               COCOK 100%
Item Transaksi         195 baris               195 dokumen              COCOK 100%
Total Omset Bon        Rp 2.435.000            Rp 2.435.000             COCOK 100%
Sum Subtotal Items     Rp 2.435.000            Rp 2.435.000             COCOK 100%
Expense Potongan Bon   7 item (Rp 326.000)     7 dok (Rp 326.000)       COCOK 100%
Rollup daily_summary   6 tanggal transaksi     6 dok (Rp 2.435.000)     COCOK 100%
Counters inv_*         6 tanggal transaksi     6 counter dok            COCOK 100%
======================================================================
[HASIL VALIDASI]: SEMUA DATA IDENTIK & COCOK 100% DENGAN SNAPSHOT!
```

Pengujian idempotensi dijalankan ulang 2 kali dan menghasilkan data yang tetap cocok 100% tanpa ada selisih.

---

## 5. File yang Ditambahkan pada Fase 6
- [`tools/migrate/package.json`](file:///d:/laragon/www/warung_lupi_firebase/tools/migrate/package.json) & [`tools/migrate/package-lock.json`](file:///d:/laragon/www/warung_lupi_firebase/tools/migrate/package-lock.json)
- [`tools/migrate/migrate.js`](file:///d:/laragon/www/warung_lupi_firebase/tools/migrate/migrate.js) (Script migrasi snapshot ke Firestore)
- [`tools/migrate/validate.js`](file:///d:/laragon/www/warung_lupi_firebase/tools/migrate/validate.js) (Script validasi integritas data)
- [`docs/migrasi-firebase/validasi-staging.md`](file:///d:/laragon/www/warung_lupi_firebase/docs/migrasi-firebase/validasi-staging.md)
- [`docs/migrasi-firebase/FASE-6.md`](file:///d:/laragon/www/warung_lupi_firebase/docs/migrasi-firebase/FASE-6.md)
- [`.gitignore`](file:///d:/laragon/www/warung_lupi_firebase/.gitignore) (Ditambahkan `tools/migrate/node_modules/`)
