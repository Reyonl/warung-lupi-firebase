# Rekapan Warung — Warung Lupi (Firebase Edition)

Aplikasi mobile kasir & pencatatan keuangan **Warung Lupi** (Flutter) untuk pencatatan bon/kuitansi, pelanggan, katalog produk, pengeluaran, laporan penjualan, serta cetak struk thermal via printer Bluetooth.

Aplikasi ini telah dimigrasikan dari backend VPS Laravel/MySQL ke **Google Cloud Firestore (Firebase Spark Free Tier)** dengan arsitektur serverless mandiri, otentikasi aman anonim, dan sinkronisasi real-time antar-perangkat tanpa perlu mengelola server VPS.

---

## Teknologi

- **Flutter:** 3.47.5 (Channel Stable, Dart 3.13.4)
- **Database:** Google Cloud Firestore (Jakarta `asia-southeast2`)
- **Keamanan:** Firestore Security Rules + Anonymous Firebase Authentication
- **State Management:** Provider
- **Pencetakan:** Bluetooth Thermal ESC/POS (58mm & 80mm) via `print_bluetooth_thermal`
- **Cadangan Fallback:** Dual-mode repository (dukungan REST API Laravel bila diperlukan)

---

## Fitur Utama

- **Dashboard Real-Time:** Ringkasan omset harian, total bon, pengeluaran, saldo kas bersih, dan hutang belum lunas.
- **Buat & Edit Bon:** Penomoran otomatis berurutan `INV-YYYYMMDD-NNN`, drag-and-drop urutan item, dan promo otomatis:
  - Item mengandung `gorengan` ➔ Tiap 3 pcs = Rp 5.000.
  - Item mengandung `donat` / `nagasari` / `lemper` / `jajanan` ➔ Tiap 2 pcs = Rp 5.000.
- **Potongan Bon & Pengeluaran:** Item bertanda minus di bon otomatis disinkronkan ke modul Pengeluaran secara idempoten (`sync_key: bon:{tid}:{iid}`).
- **Riwayat & Detail Bon:** Filter tanggal, status lunas/belum, preview struk thermal, share PNG struk, cetak Bluetooth, copy teks, dan cetak via RawBT.
- **Manajemen Pelanggan & Produk:** 155 produk terindeks cepat, riwayat bon per pelanggan, dan proteksi integritas data.
- **Laporan Rokok:** Rekapan otomatis penjualan produk kategori rokok.
- **Ekspor Data Mandiri:** Script ekspor seluruh transaksi dan pengeluaran ke file CSV/Excel lokal.

---

## Struktur Proyek

```
lib/
├── core/
│   ├── api/          # ApiConfig + Dio client (legacy REST)
│   ├── config/       # FeatureFlags (pengatur mode Firestore vs REST)
│   ├── storage/      # SharedPreferences helpers
│   └── theme/        # AppTheme & AppColors
├── models/           # Domain Model + Serialization Firestore/JSON
├── providers/        # State Management (Provider)
├── repositories/     # Repository Factory & Firestore Repositories
├── screens/          # Layar UI (Dashboard, Bon, Pelanggan, Produk, Pengeluaran, Pengaturan)
├── services/         # Printer Service & Business Logic
└── widgets/          # Komponen UI & Preview Struk Thermal
tools/
├── export_csv.js     # Script ekspor data Firestore ke CSV (arsip offline)
└── migrate/          # Script migrasi & pengujian rules Firestore
```

---

## Pengembangan & Pengujian

```bash
# Pasang dependensi
flutter pub get

# Jalankan analisis linter (0 errors, 0 warnings)
flutter analyze --no-fatal-infos --no-fatal-warnings

# Jalankan 105 unit tests (100% pass)
flutter test

# Kompilasi APK Rilis (default: Cloud Firestore)
flutter build apk --release

# Kompilasi APK dengan Rollback paksa ke REST API (bila darurat)
flutter build apk --release --dart-define=USE_FIRESTORE_ALL=false
```

---

## Utilitas Ekspor Data (CSV)

Untuk mencadangkan seluruh data transaksi dan pengeluaran ke komputer/laptop:

```bash
node tools/export_csv.js
```
File CSV akan otomatis tersimpan di folder `exports/`:
- `exports/transaksi_YYYYMMDD.csv`
- `exports/item_transaksi_YYYYMMDD.csv`
- `exports/pengeluaran_YYYYMMDD.csv`

---

## CI / CD

Aplikasi terhubung ke **GitHub Actions** (`.github/workflows/flutter-ci.yml`):
Setiap push ke branch `main` secara otomatis memvalidasi dependensi, kode (`analyze`), 105 pengujian (`test`), serta menghasilkan file instalasi APK rilis `app-release.apk` siap unduh di tab Actions.
