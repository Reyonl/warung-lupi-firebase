# Laporan Fase 0: Snapshot dan Verifikasi

**Branch:** `feat/firebase-migration`  
**Tanggal Eksekusi:** 2026-10-12 21:52 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai (Menunggu Persetujuan Pengguna untuk Fase 1)

---

## 0.1 Snapshot EC2 (Read-Only)

Snapshot database MariaDB di server EC2 `13.212.177.233` (`/var/www/warung_lupi`) berhasil dieksekusi secara read-only menggunakan user khusus `warung_migrasi_ro` (izin hanya `SELECT, SHOW VIEW` pada `warung_lupi.*` dan `SELECT` pada `mysql.proc`).

- **Lokasi Dump:** `D:\warung-backups\migrasi-20261012-2152\warung_lupi.sql`
- **Ukuran File:** 115.749 bytes
- **SHA256:** `2f23451e42ed47d2b73d84e631a14822afd60f6b70b6d7d48c40f9619fd0a22f`
- **Snapshot Counts Metadata:** `D:\warung-backups\migrasi-20261012-2152\snapshot-counts.json`
- **Git HEAD EC2:** `3f16859 test(e2e): de-flake Kemarin preset by polling instead of fixed sleep`

### Jumlah Baris per Tabel (EC2 Snapshot)

| Tabel | Jumlah Baris (COUNT) | Catatan |
|---|---|---|
| `categories` | 5 | Master kategori produk |
| `customers` | 38 | Master pelanggan |
| `products` | 155 | Master produk warung |
| `transactions` | 14 | Bon aktif di EC2 live |
| `transaction_items` | 195 | Baris item transaksi |
| `expenses` | 0 | Tabel pengeluaran (masih kosong) |
| `users` | 0 | Aplikasi internal tanpa user tabel |
| `migrations` | 10 | Riwayat migrasi Laravel |
| *Framework (cache, jobs, sessions)* | 7 tabel | Tabel sistem Laravel |
| **Total Tabel** | **15** | |

### Agregasi Nilai Uang (SUM)

- `transactions.total_amount`: **Rp 2.435.000**
- `transaction_items.subtotal`: **Rp 2.435.000** (sinkron 100% antara header dan detail item)
- `expenses.amount`: **Rp 0**
- Rentang tanggal transaksi: `2026-09-27` s/d `2026-10-12`

### Status Backup & Migrasi di Server

- **Cron Backup:** Aktif 2× sehari (`0 5 * * *` dan `0 12 * * *`) via `/usr/local/bin/backup-warung-lupi` ke `/var/backups/warung_lupi/` dan tersinkron ke Google Drive melalui `rclone`.
- **Tabel `migrations` EC2:**
  - Batch 1: `0001_01_01_000000_create_users_table`, `0001_01_01_000001_create_cache_table`, `0001_01_01_000002_create_jobs_table`
  - Batch 2: `2026_09_22_213418_create_categories_table`, `2026_09_22_213419_create_customers_table`, `2026_09_22_213420_create_products_table`, `2026_09_22_213421_create_transactions_table`, `2026_09_22_213422_create_transaction_items_table`
  - Batch 999: `2026_09_27_151230_add_payment_status_to_transactions_table`
  - Batch 1000: `2026_10_12_000000_create_expenses_table`

---

## 0.2 Impor Snapshot ke Database Lokal (`warung_migrasi_snapshot`)

Database lokal baru `warung_migrasi_snapshot` dibuat di MySQL lokal Laragon (8.0.30) dan diimpor dari file snapshot tanpa menyentuh database arsip `warung_lupi`.

### Hasil Verifikasi Konsistensi

- **Tabel:** 15 tabel berhasil dibuat.
- **Validasi Baris:**
  - `categories`: 5 (sama persis)
  - `customers`: 38 (sama persis)
  - `products`: 155 (sama persis)
  - `transactions`: 14 (sama persis)
  - `transaction_items`: 195 (sama persis)
  - `expenses`: 0 (sama persis)
  - `migrations`: 10 (sama persis)
- **Validasi Nominal:**
  - `SUM(total_amount)` = Rp 2.435.000 (cocok)
  - `SUM(subtotal)` = Rp 2.435.000 (cocok)
  - `SUM(amount)` = Rp 0 (cocok)
- **Database Arsip Lokal `warung_lupi`:** Tidak tersentuh sama sekali (tetap 24 transaksi, 342 item, 38 pelanggan).

---

## 0.3 Investigasi Selisih Transaksi (Dump Lama vs Snapshot Baru)

Pembandingan dilakukan antara dump lama `database/warung_lupi-vps-20261012.sql` (diambil 16:47 WIB) dengan snapshot EC2 baru (21:52 WIB):

- **Master Data (Categories, Customers, Products):** 100% IDENTIK (tidak ada penambahan/pengurangan pelanggan maupun produk).
- **Transaksi:** Dump lama berisi **24 transaksi** (Rp 3.987.000, 342 item), sedangkan snapshot live EC2 hanya berisi **14 transaksi** (Rp 2.435.000, 195 item).
- **Selisih Bersih:** Tepat **10 transaksi** (147 item, total Rp 1.552.000) ada di dump lama tetapi TIDAK ADA di snapshot live EC2.

### Daftar 10 Transaksi yang Tidak Ada di Snapshot EC2

| ID | Nomor Invoice | Tanggal | Total Amount (Rp) | Status | Payment Status | Type |
|---|---|---|---|---|---|---|
| 205 | INV-20261008-005 | 2026-10-08 | 412.000 | completed | paid | sale |
| 206 | INV-20261008-006 | 2026-10-08 | 227.000 | completed | paid | sale |
| 251 | INV-20261011-006 | 2026-10-11 | 82.000 | completed | paid | sale |
| 254 | INV-20261012-001 | 2026-10-12 | 18.000 | completed | unpaid | sale |
| 257 | INV-20261012-004 | 2026-10-12 | 78.000 | completed | paid | sale |
| 259 | INV-20261012-006 | 2026-10-12 | 93.000 | completed | unpaid | sale |
| 262 | INV-20261012-009 | 2026-10-12 | 241.000 | completed | unpaid | sale |
| 263 | INV-20261012-010 | 2026-10-12 | 65.000 | completed | unpaid | sale |
| 264 | INV-20261012-011 | 2026-10-12 | 79.000 | completed | unpaid | sale |
| 265 | INV-20261012-012 | 2026-10-12 | 257.000 | completed | unpaid | sale |
| **TOTAL** | **10 transaksi** | | **Rp 1.552.000** | *(147 items)* | | |

> **Catatan Kritis:**
> 4 transaksi pertama (ID 205, 206, 251, 254) persis sama dengan yang ada di file artefak `database/restore-4bon-20261012.sql` ("Restore 4 bon (205,206,251,254) dari snapshot 16:47").
> Sesuai aturan keras, ke-10 transaksi ini **TIDAK dimasukkan ke target migrasi** sebelum ada konfirmasi eksplisit dari pemilik.

---

## 0.4 Pemeriksaan Drift Skema

1. **Integritas File Migrasi Laravel:**
   - 10 file migrasi di repo lokal `Rekapan_Warung/database/migrations` memiliki SHA256 checksum yang **identik 100%** dengan 10 file migrasi di server EC2 `/var/www/warung_lupi/database/migrations`.
   - Tidak ada perbedaan kode file migrasi antara lokal dan VPS.

2. **Drift Kolom `transactions.type` (Bukan `source`):**
   - Di database live EC2 dan kedua dump SQL, tabel `transactions` memiliki kolom:
     ```sql
     `type` enum('sale','purchase') DEFAULT 'sale'
     ```
   - Di seluruh file migrasi Laravel (baik lokal maupun VPS), **TIDAK ADA** deklarasi kolom `type` ini (bahkan di `create_transactions_table` hanya ada `id`, `customer_id`, `transaction_number`, `transaction_date`, `total_amount`, `status`, `notes`, `timestamps`). Kolom `payment_status` ditambahkan oleh migrasi batch 999.
   - Kolom `type` ditambahkan secara manual via perintah DDL langsung di database server tanpa melalui file migrasi Laravel.
   - Semua baris data yang ada saat ini bernilai `'sale'`.
   - *Klarifikasi Catatan Audit:* Pada analisis awal dokumen audit disebutkan indikasi kolom `transactions.source='sale'`. Pemeriksaan struktur database membuktikan bahwa nama kolom sesungguhnya adalah `type` dengan nilai `'sale'`.

3. **Status Tabel `expenses`:**
   - File migrasi `2026_10_12_000000_create_expenses_table.php` ada di lokal dan VPS (batch 1000).
   - Tabel `expenses` ada di live snapshot (0 baris).
   - Tabel ini belum ada di dump lama 16:47 WIB (karena dump lama diambil sesaat sebelum migrasi batch 1000 dijalankan).

---

## 0.5 Status Pertanyaan Terbuka #1 sampai #10

Mengacu pada bagian akhir dokumen `docs/analisis-migrasi-firebase.md`:

| # | Pertanyaan | Status & Jawaban Hasil Fase 0 |
|---|---|---|
| 1 | **Sumber kebenaran data?** | **TERJAWAB:** Diputuskan EC2 `13.212.177.233` adalah satu-satunya sumber. Domain Hostinger tidak dipakai lagi. |
| 2 | **Data mana yang dimigrasikan?** | **TERJAWAB:** Dataset snapshot EC2 (38 pelanggan, 155 produk, 14 transaksi, 195 item). |
| 3 | **Kenapa dump 24 tx vs live EC2 14 tx?** | **BELUM TERJAWAB (Perlu Konfirmasi):** 10 transaksi (ID 205, 206, 251, 254, 257, 259, 262–265, Rp 1.552.000) ada di dump 16:47 tapi hilang di snapshot 21:52. 4 di antaranya cocok dengan file `restore-4bon-20261012.sql`. Apakah 10 transaksi ini memang transaksi uji coba / dibatalkan sehingga tidak perlu dimigrasi, atau harus dipulihkan? |
| 4 | **Drift kolom `transactions.source` / `type`?** | **TERJAWAB TEKNIS:** Kolom bernama `type` (`enum('sale','purchase') default 'sale'`), nilainya `'sale'` semua. Ditambahkan manual di MariaDB tanpa file migrasi. Apakah field `type` perlu disimpan di Firestore? (Rekomendasi: simpan sebagai `type: "sale"` untuk kompatibilitas masa depan). |
| 5 | **Perilaku offline (read vs write)?** | **BELUM TERJAWAB (GATE FASE 4):** Firestore transaction tidak bisa offline. Apakah pembuatan bon baru WAJIB bisa saat HP offline? Jika ya, bagaimana penomoran invoice sementara diubah saat online? |
| 6 | **Laporan Rokok materialized?** | **BELUM TERJAWAB:** Apakah setuju memakai koleksi rollup bulanan `cigarette_sales/{yyyy-MM}` (dihitung saat bon tersimpan) demi menghemat kuota Spark (50k baca/hari)? |
| 7 | **Keamanan / Security Rules?** | **BELUM TERJAWAB:** Apakah aturan Firebase Auth anonim (`allow read, write: if request.auth != null`) sudah cukup aman untuk 2 HP keluarga, atau butuh proteksi PIN/secret tambahan? |
| 8 | **Nomor invoice kontinu tanpa lubang?** | **BELUM TERJAWAB:** Di Firestore, penomoran `INV-YYYYMMDD-NNN` akan memakai counter per tanggal via transaksi. Apakah urutan wajib tanpa jeda jika ada draft bon dibatalkan? |
| 9 | **Ada data lain di luar tabel utama?** | **TERJAWAB TEKNIS:** Tidak ada tabel lain. Tidak ada riwayat pembayaran cicilan/hutang bertahap terpisah; status pembayaran hanya `paid`/`unpaid` pada `transactions`. |
| 10 | **Rentang usia data yang dimigrasikan?** | **BELUM TERJAWAB:** Data transaksi aktif di EC2 hanya mencakup tanggal 2026-09-27 s/d 2026-10-12 (sekitar 16 hari kalender). Apakah semua 14 transaksi ini dimigrasikan? |

---

## Kesimpulan Gate Fase 0

Fase 0 telah selesai secara penuh:
- Snapshot EC2 read-only tersimpan aman di luar repo (`D:\warung-backups\migrasi-20261012-2152\`).
- Database lokal `warung_migrasi_snapshot` terverifikasi 100% identik dengan server.
- Database lokal arsip `warung_lupi` dan folder produksi tidak tersentuh.
- Selisih 10 transaksi dan drift skema kolom `type` telah terpetakan secara presisi.
- Git worktree dan `.gitignore` siap untuk fase selanjutnya.
