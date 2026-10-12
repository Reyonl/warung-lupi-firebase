# Laporan Fase 4: Port Logika Laravel ke Dart Murni

**Branch:** `feat/firebase-migration`  
**Tanggal Eksekusi:** 2026-10-12 23:20 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai (Menunggu Persetujuan Pengguna untuk Fase 5)

---

## 4.1 Ringkasan Logika yang Di-porting

Seluruh logika bisnis dari repositori Laravel `D:\laragon\www\Rekapan_Warung` telah dibaca secara *read-only* dan di-porting menjadi kode Dart murni tanpa dependensi eksternal yang tidak perlu.

### 1. Penomoran Invoice Bon (`InvoiceNumberService`)
- **File Sumber:** `app/Models/Transaction.php` (`generateTransactionNumber`)
- **File Hasil Porting:** [`lib/services/invoice_number_service.dart`](file:///d:/laragon/www/warung_lupi_firebase/lib/services/invoice_number_service.dart)
- **Implementasi:**
  - Penomoran resmi `INV-YYYYMMDD-NNN` dengan urutan 3 digit nol di depan (`padLeft(3, '0')`).
  - Penomoran draft offline (Opsi B): `DRAFT-YYYYMMDD-XXX` yang dibuat saat perangkat offline.
  - Saat perangkat kembali online, transaksi Firestore atomik membaca dokumen counter `counters/invoice_{yyyyMMdd}`, menaikkan `currentSequence`, dan mengonversi nomor sementara menjadi nomor resmi final.

### 2. Klasifikasi & Agregasi Laporan Rokok (`CigaretteClassifier`)
- **File Sumber:** `app/Services/CigaretteReportService.php` (baris 20–81 & 140–241)
- **File Hasil Porting:** [`lib/services/cigarette_classifier.dart`](file:///d:/laragon/www/warung_lupi_firebase/lib/services/cigarette_classifier.dart)
- **Implementasi:**
  - Normalisasi teks: `toLowerCase()`, `trim()`, dan regex `\s+` dirapikan.
  - Aturan prioritas penentuan item rokok:
    1. Kategori produk (relasi master): Jika nama kategori mengandung `"rokok"` ➔ **Pasti Rokok** (contoh: kategori "Rokok" + produk "Bang Lee").
    2. Snapshot `product_name`: Jika nama produk mengandung `"rokok"`.
    3. Snapshot `description`: Fallback jika catatan item memuat `"rokok"`.
  - Agregasi Laporan: Hanya menghitung transaksi dengan status `completed` (unpaid tetap dihitung karena merupakan penjualan).
  - Menghasilkan ringkasan agregat (`cigarette_quantity`, `cigarette_sales`, `bon_count`, `paid_sales`, `unpaid_sales`), rincian item terurut penjualan tertinggi, daftar transaksi terkait, dan daftar produk unik untuk filter.

### 3. Sinkronisasi Potongan Bon ke Pengeluaran (`ExpenseSyncService`)
- **File Sumber:** `app/Services/ExpenseSyncService.php`
- **File Hasil Porting:** [`lib/services/expense_sync_service.dart`](file:///d:/laragon/www/warung_lupi_firebase/lib/services/expense_sync_service.dart)
- **Implementasi:**
  - Invarian metode minus: `subtotal < 0` menandakan potongan belanja/bon yang wajib disinkronkan ke pengeluaran.
  - Idempotensi: `syncKey = 'bon:${transactionId}:${itemId}'` dan `docId = 'bon_${transactionId}_${itemId}'`.
  - Nilai pengeluaran disimpan sebagai integer absolut positif (`subtotal.abs()`).

### 4. Agregasi Dashboard & Ringkasan Harian (`DashboardAggregateService`)
- **File Sumber:** `app/Http/Controllers/Api/DashboardController.php`
- **File Hasil Porting:** [`lib/services/dashboard_aggregate_service.dart`](file:///d:/laragon/www/warung_lupi_firebase/lib/services/dashboard_aggregate_service.dart)
- **Implementasi:**
  - Agregasi harian untuk dokumen `daily_summary/{yyyy-MM-dd}`: `saleTotal`, `saleCount`, `paidTotal`, `unpaidTotal`, `expenseTotal`, `expenseManual`, `expenseBon`.
  - Agregasi statistik dashboard (`bon_hari_ini`, `total_hari_ini`, `lunas_hari_ini`, `lunas_total`, `masih_hutang`, `pengeluaran_hari_ini`, `pengeluaran_total`, `total_pelanggan`).

### 5. Aturan Bisnis Pelanggan (`CustomerRulesService`)
- **File Sumber:** `app/Http/Controllers/Api/CustomerController.php` (`destroy`)
- **File Hasil Porting:** [`lib/services/customer_rules_service.dart`](file:///d:/laragon/www/warung_lupi_firebase/lib/services/customer_rules_service.dart)
- **Implementasi:**
  - Pelanggan yang memiliki riwayat bon (`transactionCount > 0`) dilarang dihapus dan melempar `CustomerDeletionException` ("Pelanggan tidak dapat dihapus karena memiliki riwayat bon.").

---

## 4.2 Validasi Golden Test Laporan Rokok vs Live EC2

Fixture API asli diambil langsung dari live EC2 melalui perintah read-only:
`GET http://127.0.0.1/api/reports/cigarettes` (disimpan di `test/fixtures/cigarette_report_fixture.json`).

Dataset input 14 transaksi snapshot EC2 diekspor ke `test/fixtures/snapshot_dataset.json`.

### Hasil Perbandingan Golden Test
| Metrik | Output EC2 Laravel | Output Dart Porting | Status |
|---|---|---|---|
| `cigarette_quantity` | 15 bungkus | 15 bungkus | **Identik 100%** |
| `cigarette_sales` | Rp 480.000 | Rp 480.000 | **Identik 100%** |
| `bon_count` | 7 bon | 7 bon | **Identik 100%** |
| `paid_sales` | Rp 0 | Rp 0 | **Identik 100%** |
| `unpaid_sales` | Rp 480.000 | Rp 480.000 | **Identik 100%** |
| Jumlah Merek Rokok | 6 produk | 6 produk | **Identik 100%** |
| Daftar Transaksi Bon | ID: 266, 260, 258, 211, 204, 194, 166 | ID: 266, 260, 258, 211, 204, 194, 166 | **Identik 100%** |
| Struktur JSON Output | Sesuai API Laravel | Sesuai API Laravel | **Identik 100%** |

---

## 4.3 Hasil Pengujian Suite Unit Test

Pengujian otomatis dijalankan pada seluruh repositori Flutter:
- **Baseline Sebelumnya:** 64 passed
- **Tes Baru Ditambahkan:** 26 tests (unit test services & golden test)
- **Total Pengujian Sekarang:** **90 tests passed (100% pass)**, 4 skipped (live test), **0 failed**.
