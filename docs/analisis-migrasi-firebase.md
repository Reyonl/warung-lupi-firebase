# Analisis Migrasi: VPS → Firebase (Cloud Firestore + Auth Anonim)

> Repo yang diaudit: `git@github.com:Reyonl/flutter-warungLupi-.git` (`rekapan_warung` 1.2.0+3)
> Tanggal audit: 2026-10-12 · Auditor: Hermes (teknis, read-only — tanpa perubahan kode/data)
> Batasan yang dibaca: kode Flutter lokal (D:), repo Laravel lokal (D:\laragon\www\Rekapan_Warung), VPS EC2 `13.212.177.233` (read-only), endpoint publik `warunglupi.tplp004.com` (read-only GET)

---

## Ringkasan eksekutif

**Layak dengan syarat.** Data tersimpan di backend Laravel + MySQL (bukan lokal per HP), jadi migrasi ke Firestore dimungkinkan. Namun audit menemukan **dua backend berbeda yang berjalan paralel**: (a) server Hostinger `warunglupi.tplp004.com` — ini **default** base URL di kode Flutter, belum punya route `/api/expenses` (fitur Pengeluaran terbaru tidak tersedia di sana), dan (b) VPS EC2 `13.212.177.233` — kode terbaru sudah di-deploy, tabel `expenses` ada tapi masih kosong. Keduanya punya **dataset berbeda** (tplp004: 44 pelanggan; EC2: 38 pelanggan). Sebelum migrasi **wajib** ditentukan mana sumber data kebenarannya — memigrasi yang salah akan kehilangan data.

Risiko terbesar: (1) kehilangan data akibat duplikasi server + perbedaan dataset, (2) aplikasi produksi saat ini memanggil backend yang belum punya endpoint Expense, (3) query agregasi (Laporan Rokok, dashboard, sisa hutang) tidak bisa dipetakan 1:1 ke Firestore tanpa denormalisasi. Estimasi effort: **5–9 hari kerja** (setup 0,5–1; adapter model 1–2; migrasi data + validasi 1–2; cutover per layar 2–3; uji 2 perangkat + rollback 1). Kuota Spark aman untuk skala data saat ini (~24 transaksi, ~342 item).

---

## Arsitektur saat ini

```
HP Pemilik ─┐                          ┌─ Laravel (Hostinger) warunglupi.tplp004.com
HP Adik ────┴─► Flutter (Dio 5.11.1) ─►│     88.223.91.5  ← DEFAULT baseUrl di kode
             lib/core/api/api_client    ├─ Laravel (AWS EC2) 13.212.177.233
             .dart:31                   │     IP-172-31-33-86, nginx + php8.4-fpm
                                        └─     MySQL/MariaDB 10.11 lokal di server
```

- **Client**: Flutter (`dio: ^5.11.1`, `provider`, `shared_preferences`), tanpa storage database lokal (hanya SharedPreferences utk settings: ukuran struk, alamat server API, nama/ID printer — `lib/core/storage/prefs.dart`).
- **`ApiConfig.productionBaseUrl = 'https://warunglupi.tplp004.com'`** — `lib/core/api/api_client.dart:31`. Override runtime via Pengaturan → `Prefs.getApiBaseUrl()` (bisa kosong → default). Prioritas: `--dart-define=API_BASE_URL` > override runtime > default.
- **Backend**: Laravel (2 deployment, lihat temuan). `bootstrap/app.php:16` — **"No auth required for internal tool"**: API publik tanpa login/token/Sanctum.
- **Versi Flutter/Java**: 3.47.5 / Java 17 (CI `flutter-ci.yml` + CD `release.yml` — tag `v*` → build release + GitHub Release).

### TEMUAN UTAMA: dua backend divergen

| Aspek | `warunglupi.tplp004.com` (Hostinger) | `13.212.177.233` (VPS EC2) |
|---|---|---|
| Kode | TIDAK punya route `/api/expenses` (balas HTML SPA) | Terbaru — `git log` = `3f16859` (feat expense sudah include) |
| Dashboard | tanpa key `pengeluaran_hari_ini` (DashboardController lama) | dengan `pengeluaran_hari_ini`/`pengeluaran_total` |
| Pelanggan | 44 | 38 |
| Transaksi (paginate total) | 17 (halaman 1) | 14 live (setelah dump) |
| Tabel `expenses` | tidak ada | ada, 0 baris |
| Migrasi terakhir | — | batch 1000 = `create_expenses_table` |

Flutter v1.2.0 (rilis hari ini, dengan fitur Pengeluaran) **default-nya menunjuk server yang tidak punya endpoint Expense** — layar Pengeluaran di produksi akan error 404/HTML sampai base URL di-Prefs diganti ke EC2. Ini masalah operasional yang harus dibereskan sebelum/kalaupun migrasi.

---

## Pemetaan endpoint → koleksi Firestore

Semua pemanggilan Dio di `lib/providers/repositories.dart` (baris dirujuk). Backend: `routes/api.php` (31 route).

| # | Endpoint (method) | Pemakaian di Flutter | Koleksi Firestore usulan | Catatan |
|---|---|---|---|---|
| 1 | `GET /api/dashboard` | DashboardScreen | `daily_summary/{yyyy-MM-dd}` + `transactions` (recent 10) | Agregasi jadi dokumen harian denormalisasi |
| 2 | `GET/POST/PUT/DELETE /customers`, `GET /customers/{id}/transactions` | CustomerList/Form, riwayat | `customers/{id}` | id asli legacy |
| 3 | `GET/POST/PUT/DELETE /categories` | CategoryList | `categories/{id}` | |
| 4 | `GET /products` (**tanpa paginate**, `->get()`, ProductController.php:29) | ProductList + pencarian in-memory di BonCreate | `products/{id}` | ~155 dokumen, muat 1x |
| 5 | `GET/POST/PUT/DELETE /transactions` (index paginate 20, filter tgl/status/customer/search — TransactionController.php:14-42) | BonList | `transactions/{id}` + sub-collection `items` | |
| 6 | `POST /transactions/{id}/items`, `PUT/DELETE /transaction-items/{id}` | BonCreate edit item | `transactions/{id}/items/{itemId}` | |
| 7 | `GET/POST/PUT/DELETE /expenses` (index paginate 20 + summary by_source — ExpenseController.php:42-54) | ExpenseList | `expenses/{id}` + agregat di `daily_summary` | |
| 8 | `GET /reports/cigarettes` (JOIN items+transactions, SUM, GROUP BY — CigaretteReportService.php:156-187) | CigaretteReport | `cigarette_sales/{yyyy-MM}` materialized ATAU query items + filter | **Berat → perlu desain khusus** |
| 9 | `GET /transactions/{id}/cigarettes` | Detail bon | dari `transactions/{id}/items` | |

Endpoint `categories.show`, `products.show` ada di backend tapi tidak dipakai client → "Tidak ditemukan pemakaian" (tidak perlu dimigrasikan khusus).

---

## Desain data Firestore usulan

### Koleksi & dokumen

```
customers/{legacyId}            { name, phone?, notes?, isActive, createdAt }
categories/{legacyId}           { name, createdAt }
products/{legacyId}             { categoryId, name, defaultPrice:int, unit, isActive, createdAt }
transactions/{legacyId}         { customerId, number, date:"yyyy-MM-dd", totalAmount:int,
                                  status:"draft|completed", paymentStatus:"paid|unpaid",
                                  notes?, createdAt, updatedAt }
transactions/{id}/items/{itemId}{ productId?, productName(snapshot), description?, quantity:int,
                                  unit, unitPrice:int, subtotal:int }   // key quantity=INTEGER
expenses/{legacyId}             { date, title, category?, amount:abs, source:"manual|bon",
                                  transactionId?, syncKey? unik, notes? }
daily_summary/{yyyy-MM-dd}      { saleTotal, saleCount, paidTotal, unpaidTotal, expenseTotal,
                                  expenseManual, expenseBon, updatedAt }
cigarette_sales/{yyyy-MM}       { perProduct: { "nama": {qty, amount} }, bonCount }   // materialized
```

### Relasi & denormalisasi yang harus diputuskan

| Relasi SQL saat ini | Masalah di Firestore | Solusi |
|---|---|---|
| `transaction_items.product_id` → `products` (FK `set null`) | NoSQL tanpa JOIN | snapshot `productName`/`unitPrice` sudah ada di item (migrasi `2026_09_22_213422`); cukup pertahankan |
| `products.category_id → categories` (FK `restrict`) | item→product→category traversal 3 level utk laporan rokok | `cigarette_sales` materialized per bulan (dihitung saat bon disimpan) |
| `transactions.customer_id` FK `restrict` | hapus pelanggan | aturan aplikasi: cek `transactions` sub-kueri sebelum delete (mirror validasi Laravel "masih memiliki riwayat bon") |
| `expenses.transaction_id` + `sync_key unik` (bon:{tid}:{iid}) | idempotensi sync otomatis | jadikan `syncKey` sebagai prefix docId (`bon_{tid}_{iid}`) → upsert idempotent |
| Dashboard SUM per hari / sisa hutang total | read semua transaksi | `daily_summary` + `counter` (mis. `stats/lutangTotal`) diperbarui di transaksi yang sama (batch write) |

### Composite index yang dibutuhkan
1. `transactions`: `customerId ASC, date DESC`
2. `transactions`: `date DESC, paymentStatus ASC`
3. `expenses`: `date ASC, source ASC`
4. `transactions/{id}/items`: otomatis terindeks per dokumen induk
5. HINDARI query lintas koleksi (`where('transaction.status', ...)` pada items) — itu penyebab utama butuh `cigarette_sales` materialized.

---

## Auth dan Security Rules

**Saat ini tidak ada auth sama sekali** (`bootstrap/app.php:16`; tidak ada `routes/auth.php` aktif, tidak ada Sanctum/token di `routes/api.php`; aplikasi tidak pernah menampilkan login).

Usulan:
- **Firebase Auth anonim** di kedua HP: setiap perangkat dapat `uid` acak. Cocok untuk "tanpa login" seperti sekarang.
- Karena kedua HP harus melihat **data yang sama** (bukan data per-user), rules tidak memakai `uid` untuk isolasi data — hanya memastikan `request.auth != null`:

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /{document=**} {
      // Hanya perangkat yang sudah auth anonim (kebetulan siapa pun yg punya
      // Firebase project key bisa daftar anonim) — ini SEKURITI SEMU.
      // Layak hanya utk skala keluarga. Untuk publik: tambah server-side
      // check PIN/secret atau pindah ke custom token dari Cloud Function.
      allow read, write: if request.auth != null;
    }
  }
}
```

Peringatan: Firebase API key Android bersifat publik (bisa diekstrak dari APK) → siapa pun yang klaim project ini bisa daftar anonim dan baca/tulis semua data. Untuk 2 perangkat keluarga ini acceptable, tapi tuliskan sebagai risiko. Alternatif lebih aman dengan effort kecil: secret token (mis. `app_secret` di `Prefs`) diverifikasi di Cloud Function, atau `allow if` membatasi berdasarkan `request.auth.token.app` + rules deny write pada koleksi yang hanya dibaca kalkulasi.

---

## Perilaku offline dan penanganan konflik

**Saat ini app TIDAK offline-first:**
- Setiap layar langsung `GET` ke server; `initState` memanggil provider `load()` (contoh `DashboardScreen` → `DashboardProvider.load()`).
- Tidak ada antrean tulis lokal, tidak ada cache data (hanya SharedPreferences utk settings).
- `TransientFailureRetry` (`api_client.dart:90-144`): GET/HEAD retry ≤2, PUT/DELETE ≤1, **POST tidak pernah** (mencegah bon rangkap). Backoff 600→1500ms.
- Tidak ada penanganan konflik edit dari 2 HP: last-write-wins di server (Laravel Pakai `updated_at`; tidak ada versi/optimistic concurrency).
- Timestamp: `transaction_date` memakai **jam perangkat** (`bon_create_screen.dart:34` `DateTime _transactionDate = DateTime.now()`), sedangkan `created_at`/`updated_at` dari server. `expenses.expense_date` juga dikirim dari client.

Perubahan yang dibutuhkan di Firestore:
- Aktifkan **offline persistence** (`FirebaseFirestore.instance.settings = PersistenceSettings(...)`) → baca dari cache saat offline, tulis masuk antrean lokal.
- Tambahkan **antrean tulis eksplisit** (opsional) bila ingin skema "draft bon tersimpan offline": simpan bon utuh sebagai `pending_ops/{uuid}` saat offline, replay saat online.
- Konflik: tetap last-write-wins per dokumen, TAPI karena app memakai `transaction_date` jam perangkat, dua HP yang buat bon tanggal berbeda saat offline akan menghasilkan urutan salah → pertimbangkan `serverTimestamp()` untuk `createdAt` dan aturan "tanggal bisnis" (tanggal warung) tetap dikirim client.
- Catatan migration: karena sekarang tidak ada offline, menambah offline-first adalah **fitur baru**, bukan penggantian — effort tambahan.

---

## Estimasi kuota dan biaya

Skala saat ini (server EC2, live): 38 pelanggan, 155 produk, 5 kategori, 14–24 transaksi, 195–342 item, expense 0–3. Angka "warung kecil".

**Pemakaian per buka-aplikasi (2 perangkat):**
- Startup/home: `dashboard` 1 read + produk 1 read + kategori 1 read (+ customers bila layar dibuka) ≈ **3–5 reads**.
- Buka BonList: 1 read (20 doc). Buka Detail bon: 1 read + item sub-koleksi 1.
- Buat bon (5 item): 1 write header + 5 writes item + 1 update `daily_summary` + 1 update counter = **~7–8 writes**, 0 reads.
- Expense: 1 write + update daily_summary.
- Laporan Rokok buka: 1 read `cigarette_sales/{bulan}` (setelah materialized) — tanpa materialized bisa **ratusan read** (semua item periode).

**Estimasi harian (2 HP, mis. 15 buka app + 20 bon/hari @ 5 item):**
| Sumber | Reads | Writes | Deletes |
|---|---|---|---|
| Buka app (15×2 × 4) | ~120 | — | — |
| Bon (20 × 7–8) | ~40 | ~150 | — |
| Expense (5 × 2) | 10 | 10 | ~2 |
| Laporan rokok (5×) | ~10–500 | — | — |
| **Total** | **~180–700** | **~160** | **~2** |

Kuota Spark: 50.000 read, 20.000 write, 20.000 delete/hari → **sangat aman**, faktor ~60–250×. Storage 1 GiB: dokumen kecil (transaksi ~1–2 KB) → 100.000+ transaksi baru penuh 1 GiB. Transfer keluar 10 GiB/bln aman (app mobile, tanpa aset besar). **Kesimpulan: kuota bukan penghambat** untuk skala warung ini.

---

## Rencana migrasi bertahap dan rollback

### Fase 0 (prasyarat — 0,5–1 hari)
1. **Putuskan sumber kebenaran**: tplp004 (44 pelanggan, tanpa expense) vs EC2 (38 pelanggan, dengan expense, expenses kosong). Tangani pertanyaan terbuka #1–#4. **Jangan mulai migrasi sebelum ini.**
2. Selaraskan kode: pastikan server yang benar punya fitur expense; fix default base URL di Flutter bila perlu.

### Fase 1 — Setup Firebase (1–2 jam)
- Buat project Firebase, aktifkan Auth anonim + Firestore (region terdekat), buat rules awal.
- Tambah `firebase_core` + `firebase_auth` + `cloud_firestore` (via `flutter pub add`), `google-services.json` (direktori `android/app/`), versi minimal SDK sesuai.
- Catatan: tidak ada folder `ios/` di repo → iOS tidak didukung saat ini; Firebase di-Android saja.

### Fase 2 — Adapter data paralel (1–2 hari)
- Bangun `FirestoreRepository` paralel di belakang interface yang sama dengan `DioRepository`; feature-flag per layar (`di FirebaseLayer.enabled` dari `--dart-define` / Prefs).
- Port model Dart apa adanya (semua field sudah cocok dengan snapshot). Tambahkan `Map<String,dynamic> toDocument()` + `fromDocument()`.
- Konversi: `quantity`/`subtotal`/`amount` **int** (jangan double); tanggal simpan `"yyyy-MM-dd"`; `numFrom` tetap dipakai untuk toleransi string DECIMAL.

### Fase 3 — Migrasi data historis + validasi (1–2 hari)
- Script (Node.js/Python + `mysql2` + `@google-cloud/firestore`): baca dump SQL, tulis Firestore idempotent.
- **Idempotency**: docId = `legacy_<id>` untuk customers/categories/products/transactions/expenses; items = `legacy_<id>`; expenses bon = `bon_{tid}_{iid}` (kolom `syncKey`). Setiap doc menyimpan `legacyId` + `migratedAt`.
- **Validasi sebelum/ sesudah** (wajib catat di log):
  - jumlah baris per tabel: `count(*)` MySQL vs `list.docs.length` koleksi (dan sub-koleksi items).
  - total nominal: `SUM(total_amount)` transactions, `SUM(amount)` expenses, `SUM(subtotal)` items (per bulan).
  - sample: 5 transaksi diambil acak, bandingkan field lengkap doc vs baris SQL.
- **Penanganan ID lama**: pertahankan `transaction_number` (INV-...) persis; urutan `generateTransactionNumber` (hitung per tanggal + 1) dipindah ke sisi client/Cloud Function dengan pendekatan transaksi Firestore (counter per tanggal) agar dua HP tidak bentrok.

### Fase 4 — Cutover per layar (2–3 hari)
- Urutan: kategori+produk+pembeli (baca master) → bon (baca+tulis) → expense → dashboard/report.
- Tiap layar diuji di 2 HP: tulis bareng, hapus, edit, offline (flight mode), konflik.
- Laporan Rokok: hitung ulang `cigarette_sales` dari data migrasi (migrasi classifier yang sama — PHP) — validasi angka vs laporan lama.
- Setelah semua layar hijau: alihkan default ke Firestore, nonaktifkan tulis ke VPS (read-only).

### Fase 5 — Nonaktifkan VPS (0,5 hari)
- Matikan akses tulis aplikasi (atau hentikan server bila disetujui). Amankan backup final VPS (dump terakhir + arsip).

### Rollback
- **Selalu mungkin**: VPS dibiarkan utuh (read-only) selama fase 4; begitu bug kritis, balik feature-flag ke `DioRepository` (base URL lama) → app kembali online dalam hitungan menit.
- Data yang ditulis ke Firestore selama fase 4 (jika sudah ada) perlu di-replay manual ke VPS bila rollback total — karena itu **jangan** nonaktifkan VPS sebelum fase 4 selesai semua layar.
- Backup: simpan 2 dump terakhir VPS (sudah ada `backup-warung-lupi` cron 2×/hari → Google Drive, `/var/backups/warung_lupi`, retensi 14 hari lokal / 30 hari Drive — terverifikasi di server).

---

## Tabel risiko

| Risiko | Dampak | Kemungkinan | Mitigasi |
|---|---|---|---|
| Sumber kebenaran salah (2 server beda dataset) | Data hilang/duplikat permanen | Tinggi | Fase 0 wajib; bandingkan dump sebelum migrasi; jangan hapus VPS |
| App produksi default ke server tanpa expense (tplp004) | Fitur Pengeluaran error 404 di HP | Tinggi (sudah terjadi) | Fix default base URL; keputusan di Fase 0 |
| Query agregasi (rokok, dashboard, hutang) tanpa materialized | Reads membengkak / UI lambat | Sedang | `daily_summary` + `cigarette_sales` + counter; hitung ulang via Cloud Function/migration |
| Security rules longgar + kunci API publik | Siapa pun baca/tulis data | Sedang | Rules `auth != null` cukup utk keluarga; secret token bila publik |
| Konflik 2 HP saat offline | Last-write-wins, tanggal kacau | Sedang (fitur baru offline) | `serverTimestamp`, antrean tulis, aturan tanggal bisnis |
| Nomor invoice bentrok saat cutover | Duplikat `INV-...` | Sedang | Counter per tanggal via transaksi Firestore |
| Migrasi tidak idempotent / terputus | Doc dobel / parsial | Sedang | docId=legacyId, detect `migratedAt`, retry aman |
| Jumlah doc > 1 GiB | Biaya storage | Rendah | Skala kecil; kompresi item lama bila perlu |
| Fitur non-Firebase (PDF/BT) rusak pasca migrasi | Struk kenapa-kenapa | Rendah | Fitur tsb lokal, tak bergantung backend (lihat bawah) |

---

## Peta endpoint yang TIDAK dipakai aplikasi

- `GET /categories/{category}` — "Tidak ditemukan" pemakaian di client.
- `GET /products/{product}` — "Tidak ditemukan".
- `GET /transactions/{id}/cigarettes` → dipakai `BonDetailScreen` (Laporan rokok per bon) — terkonfirmasi via `BonCigaretteSummary`.
- `PUT /transactions/{id}` → dipakai `TransactionRepository.update` (perbarui status/hutang, `repositories.dart:276`).
- Tidak ada endpoint autentikasi; tidak ada upload.

---

## Temuan lain yang penting

1. **Skema server ≠ skema repo lokal (indikasi drift)**: migrasi `2026_09_27...add_payment_status` di server ber-batch **999**, `create_expenses_table` batch 1000 — migrasi dijalankan manual dengan batch ganjil. File `database/restore-4bon-20261012.sql` (repo lokal) berisi kolom transaksi `'sale'` (kolom ke-8: `...,'completed','paid','sale',NULL,...`) yang **tidak ada di migrasi repo lokal** — kemungkinan ada kolom/versi skema di server yang belum di-sync ke repo. Harus diverifikasi sebelum dump dipakai.
2. **Dump `warung_lupi-vps-20261012.sql` (16:47 WIB) TIDAK memuat tabel `expenses`** (tidak ada `CREATE TABLE expenses`, tidak ada insert), sedangkan live EC2 saat audit punya tabel `expenses` (0 baris) + migrasi batch 1000. Artinya dump lebih tua dari kondisi DB → migrasi data harus dibuat ulang dari **dump baru**.
3. **Data dump ≠ data live**: dump 24 transaksi/342 item vs live EC2 14 transaksi/195 item. Ada penghapusan/penggantian data setelah dump (file `database/restore-4bon-20261012.sql` menunjukkan restore 4 bon dari snapshot 16:47 di lingkungan lokal). Verifikasi ulang sebelum migrasi.
4. **Cache framework Laravel jalan** (`cache`, `cache_locks`, `jobs` di DB) — normal, tidak relevan utk Firebase.
5. **Keamanan**: tidak ada auth sama sekali di API publik → data warung bisa dibaca siapa pun yang tahu URL. Ini risiko **saat ini juga**, terlepas dari migrasi. Firebase (auth anonim + rules) sebenarnya **memperbaiki** ini.
6. Kualitas kode: repository pattern rapi, model mirror backend, snapshot product_name/price di item (denormalisasi sudah benar). Tidak ada blok kinerja bermasalah di sisi client (hanya `products` di-load penuh — 155 item fine).

---

## Fitur non-Firebase (tidak terpengaruh migrasi)

| Fitur | Lokasi | Dampak migrasi | Catatan |
|---|---|---|---|
| Cetak Bluetooth ESC/POS | `print_bluetooth_thermal ^1.2.5` (`lib/services/printer_service.dart`) | **Tidak terpengaruh** — lokal | Izin `BLUETOOTH_SCAN/CONNECT` sudah ada (AndroidManifest baris 7-11) |
| Preview struk + QRIS (statis) | `qr_flutter`, `thermal_receipt.dart` | Tidak terpengaruh | QRIS hardcoded (`ThermalReceiptData.qrisValue`) |
| Export PDF | `pdf ^3.13.1` + `printing ^5.15.1` | Tidak terpengaruh | |
| Bagikan PNG struk | `share_plus ^13.3.0` + `path_provider` | Tidak terpengaruh | file ke `getApplicationDocumentsDirectory()` |
| Print intent / copy struk | RawBT intent | Tidak terpengaruh | |
| iOS | — | Tidak relevan | **Tidak ada folder `ios/`** → app Android-only; Firebase Android saja |

Izin Android yang ada: INTERNET, ACCESS_NETWORK_STATE, BLUETOOTH(+ADMIN ≤30), BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION(≤30). Firebase Android menambah keperluan google-services.json; tidak ada izin baru.

---

## Kecocokan: Firestore vs alternatif

**Firestore cocok** utk kasus ini dengan syarat desain materialized. Skala data sangat kecil (ratusan dokumen), kebutuhan realtime antar 2 HP dipenuhi (listener), offline persistence gratis, kuota Spark cukup. Yang tidak gratis: query agregasi SQL (JOIN+GROUP BY Laporan Rokok, SUM dashboard) — harus di-denormalisasi. Ini pekerjaan desain, bukan blocker.

**Alternatif dibandingkan:**
- **Supabase (Postgres + auth + realtime)**: SQL 1:1 dengan Laravel sekarang — migrasi data trivial, laporan rokok/dashboard tinggal query sama. Kelemahan: offline-first di Flutter **belum matang** (realtime memerlukan online; koneksi listrik putus = UI error), self-host = tetap urus server (tidak menghilangkan tujuan "tidak perlu kelola VPS"), cloud = perlu bayar/daftar akun + data di luar kontrol. Free tier: 500 MB, 2 project, pause setelah 1 minggu idle — berisiko utk app warung yang dipakai harian tapi bisa dianggap OK.
- **Tetap PostgreSQL di VPS + endpoint sinkronisasi**: tanpa perubahan arsitektur, tapi tidak menyelesaikan tujuan (masih kelola VPS, offline tetap tidak ada).
- **Dual-write (VPS + Firestore)** sebagai jembatan: kompleks, hanya utk transisi.

Rekomendasi jujur: **Firestore cocok** bila kebutuhan utamanya (a) sama data di 2 HP, (b) offline, (c) tanpa kelola VPS — dan pemilik siap menerima pekerjaan denormalisasi agregat. **Supabase lebih murah effort-nya** jika laporan rokok/dashboard jadi prioritas tinggi dan offline bisa dikompromikan. Keputusan ada di pemilik.

---

## Pertanyaan terbuka untuk pemilik

1. **Mana server yang benar / data kebenaran?** tplp004.com (44 pelanggan, tanpa expense) vs EC2 13.212.177.233 (38 pelanggan, dengan expense, expenses 0). HP pemilik & adik masing-masing mengarah ke mana?
2. Data mana yang mau dipindahkan (transaksi di tplp004 tampak lebih banyak dari EC2)?
3. Kenapa dump (24 tx) ≠ live EC2 (14 tx)? Ada penghapusan setelah dump? File `restore-4bon-20261012.sql` di repo lokal — apa itu proses produksi?
4. Kolom `transactions.source='sale'` (di restore SQL) tidak ada di migrasi repo lokal — skema server beda?
5. Rencana offline: cukup offline-read (lihat data lama) atau juga offline-write (buat bon tanpa internet baru disinkron)?
6. Laporan Rokok: setuju dijadikan materialized (rekap bulanan dihitung ulang) atau harus tetap bisa "query fleksibel" periode sebarang?
7. Security: cukup "siapa pun dengan app ini bisa akses" atau perlu PIN/secret tambahan?
8. Nomor invoice `INV-YYYYMMDD-NNN` harus tetap kontinu tanpa lubang? (migrasi bisa menghasilkan ulang urutan)
9. Apakah ada data lain di luar 8 tabel (mis. riwayat pembayaran hutang bertahap) yang belum terpetakan?
10. Usia data: berapa bulan sejarah yang wajib dimigrasi? (sisanya bisa diarsip)

---

## Daftar file yang dibaca (path + referensi)

**Flutter (repo `rekapan_warung_flutter`):**
- `lib/core/api/api_client.dart` (287 baris; baseUrl :31, retry :90-144, timeout :179-181)
- `lib/core/storage/prefs.dart` (shared_preferences: thermal size, apiBaseUrl, printer)
- `lib/providers/repositories.dart` (517 baris; semua repo + `DashboardData`, `ExpenseRepository`)
- `lib/providers/providers.dart` (`ExpenseProvider`, `BonDraftProvider`, retry/provider lain)
- `lib/models/models.dart` (673 baris; 17 kelas model + `splitItems`/`ItemSplit`, `numFrom` :8)
- `lib/screens/` — `dashboard_screen.dart`, `bon/bon_create_screen.dart` (:34 timestamp perangkat), `bon/bon_detail_screen.dart` (:99 show, :382 share PNG), `bon/bon_list_screen.dart`, `customers/*`, `expenses/expense_list_screen.dart` (973 baris), `products/cigarette_report_screen.dart`, `settings/settings_screen.dart`, `home_shell.dart`
- `lib/services/printer_service.dart` (ESC/POS), `lib/widgets/thermal_receipt.dart` (QRIS statis)
- `lib/main.dart` (`ExpenseProvider` registrasi), `lib/core/navigation.dart`, `lib/utils/format.dart`, `lib/utils/promo.dart`
- `pubspec.yaml` (deps), `pubspec.lock` (tidak ada firebase)
- `android/app/src/main/AndroidManifest.xml` (izin)
- `.github/workflows/flutter-ci.yml`, `.github/workflows/release.yml`
- `docs/AUDIT.md` (275 baris, audited 2026-09-29)
- Tidak ada folder `ios/`; tidak ada sqflite/Hive/Isar (storage lokal hanya SharedPreferences)
- Tidak ada `google-services.json`, tidak ada dependency firebase → "Tidak ditemukan Firebase di project"

**Laravel (web, repo `Rekapan_Warung` — kode sumber):**
- `routes/api.php` (31 route)
- `app/Http/Controllers/Api/` — DashboardController, CustomerController, CategoryController, ProductController, TransactionController, TransactionItemController, ExpenseController, CigaretteReportController
- `app/Services/CigaretteReportService.php` (JOIN+SUM+groupBy :156-187), `app/Services/ExpenseSyncService.php` (sync_key `bon:{tid}:{iid}` idempotent)
- `app/Models/Transaction.php` (`generateTransactionNumber`, event `deleting`), `app/Models/User.php`
- `bootstrap/app.php` (:16 "No auth required")
- `database/migrations/` — 10 file (users/cache/jobs base, categories, customers, products, transactions, transaction_items, add_payment_status 2026-09-27, create_expenses 2026-10-12)
- `database/warung_lupi-vps-20261012.sql` (dump 119.041 B — **tidak memuat expenses**)
- `database/restore-4bon-20261012.sql`, `database/import-report-20261012.txt` (artefak lokal)
- `.env` (hanya jenis/lokasi — DB lokal root, lihat baris DSN; **kredensial tidak dicatat di laporan ini**)

**VPS EC2 `13.212.177.233` (read-only):**
- `/var/www/warung_lupi/.env` (DB_PASSWORD → **tidak dicetak**; hanya jenis `DB_HOST/PORT/DATABASE/USERNAME`, APP_ENV, APP_URL)
- `/var/www/warung_lupi/database/migrations/` (ada `2026_10_12_000000_create_expenses_table.php`)
- `git -C /var/www/warung_lupi log` (HEAD `3f16859` — expense sudah include)
- MySQL live: `SHOW TABLES`, `SELECT COUNT(*)` per tabel, `SELECT MAX/MIN(transaction_date)`, `migrations` batch 999/1000, `expenses` 0 baris
- `ss -tlnp` (MariaDB listen 127.0.0.1:3306), `/run/mysqld/` (socket)
- `/etc/nginx/sites-enabled/warung_lupi` (server_name `13.212.177.233 warunglupi.tplp004.com` — **nginx di EC2 melayani domain yang SAMA dengan Hostinger!** → konflik DNS/routing perlu klarifikasi)
- `crontab` (backup `backup-warung-lupi` 2×/hari → /var/backups + rclone gdrive; retensi 14/30 hari)
- `/usr/local/bin/backup-warung-lupi`

**Endpoint publik (read-only GET):**
- `https://warunglupi.tplp004.com/api/dashboard` → stats TANPA `pengeluaran_hari_ini`, 44 pelanggan, recent tx id=176
- `https://warunglupi.tplp004.com/api/expenses` → `text/html` (route tidak ada → SPA fallback)
- `https://warunglupi.tplp004.com/api/products` → JSON array (route ada)
- `http://13.212.177.233/api/dashboard` → stats DENGAN `pengeluaran_hari_ini`, 38 pelanggan
- `http://13.212.177.233/api/expenses` → JSON paginated, data [] (0 baris)
- `nslookup warunglupi.tplp004.com` → 88.223.91.5 (Hostinger), bukan EC2

---

*Laporan dibuat read-only. Tidak ada kode, branch, commit, push, dependency, firebase init/deploy, atau penulisan data yang dilakukan.*