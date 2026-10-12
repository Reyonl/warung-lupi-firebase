# Laporan Fase 8: Cutover Produksi & Persiapan Rilis

**Branch:** `main`  
**Repositori:** `Reyonl/warung-lupi-firebase`  
**Tanggal Eksekusi:** 2026-10-13 00:27 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai (Siap Masuk Fase 9)

---

## 8.1 Status Cutover Produksi

Pada Fase 8 ini, pengalihan utama arsitektur backend selesai dilakukan:
1. **Peralihan Bawaan (Default) ke Cloud Firestore:**
   - File konfigurasi `lib/core/config/feature_flags.dart` kini menetapkan nilai bawaan `USE_FIRESTORE_ALL=true`.
   - Tanpa perlu menyertakan flag `--dart-define` saat build, aplikasi secara otomatis berjalan 100% di atas arsitektur Google Cloud Firestore (Staging/Production instance).
   - Seluruh modul data beroperasi via Firestore Repository:
     - **Pelanggan (`customers`):** Pengelolaan pelanggan, sinkronisasi real-time, validasi aturan bisnis (tidak bisa hapus pelanggan dengan transaksi aktif).
     - **Kategori (`categories`):** Pengelompokan produk dan urutan display.
     - **Produk (`products`):** Katalog 155 produk in-memory cache dengan filter real-time.
     - **Transaksi & Bon (`transactions` & `items`):** Pembuatan bon, penomoran berurutan atomik `INV-YYYYMMDD-NNN`, perhitungan promo donat/gorengan, potong bon.
     - **Pengeluaran (`expenses`):** Sinkronisasi idempoten otomatis untuk item potongan bon minus (`sync_key: bon:{tid}:{iid}`).
     - **Dashboard (`daily_summary`):** Ringkasan omset harian, total bon, pengeluaran, sisa kas bersih, dan hutang belum lunas.
     - **Laporan Rokok (`cigarette_sales`):** Agregasi otomatis penjualan kategori rokok.

2. **Otentikasi Aman:**
   - Anonymous Authentication aktif secara otomatis di `lib/main.dart`.
   - Seluruh operasi database dilindungi oleh Firestore Security Rules yang membatasi hak akses dan menjaga integritas invarian nominal uang (integer non-negatif, format tanggal `yyyy-MM-dd`, dan nomor faktur resmi).

---

## 8.2 Prosedur Rollback Darurat (Emergency Rollback)

Untuk menjamin keandalan operasional toko tanpa risiko downtime, telah disediakan **2 mekanisme rollback darurat**:

### Opsi A: Runtime Rollback Langsung dari Aplikasi (Tanpa Perlu Build Ulang)
Jika terjadi kendala koneksi Google Firebase atau kebutuhan pemeliharaan darurat:
1. Buka aplikasi di HP ➔ Masuk ke menu **Pengaturan**.
2. Gulir ke bawah hingga kartu **CLOUD FIRESTORE (PRODUCTION & FEATURE FLAGS)**.
3. Geser tombol toggle **"Semua Modul (Override Global)"** ke posisi **Nonaktif**.
   *(Atau nonaktifkan hanya modul spesifik yang bermasalah, misalnya hanya modul Pengeluaran atau Transaksi)*.
4. Restart aplikasi. Aplikasi akan seketika mengalihkan komunikasi jaringan kembali ke REST API Laravel lama (`warunglupi.tplp004.com` atau EC2 `13.212.177.233`).

### Opsi B: Build-Time Rollback (Kompilasi Ulang APK)
Jika ingin merilis APK khusus yang memaksa penggunaan backend REST API tanpa opsi Firestore:
```bash
flutter build apk --release --dart-define=USE_FIRESTORE_ALL=false
```

---

## 8.3 Verifikasi Build Rilis & Pipeline GitHub Actions CI

Pipeline CI di GitHub Actions pada repositori `Reyonl/warung-lupi-firebase` telah berjalan penuh dan terbukti **100% HIJAU (SUCCESS)**:

- **Run ID:** `38282896721`
- **Workflow:** `Flutter CI` (`.github/workflows/flutter-ci.yml`)
- **Durasi Eksekusi:** 9 menit 17 detik
- **Hasil Tahapan:**
  1. `Set up job`: PASSED
  2. `Checkout`: PASSED
  3. `Setup Java 17`: PASSED (Temurin 17)
  4. `Setup Flutter 3.47.5`: PASSED (Stable channel 3.47.5, Dart 3.13.4)
  5. `Install dependencies`: PASSED (`flutter pub get`)
  6. `Analyze`: PASSED (`flutter analyze --no-fatal-infos --no-fatal-warnings`, 0 errors, 0 warnings)
  7. `Test`: PASSED (105 tests passed, 0 failed, 4 skipped live)
  8. `Build release APK`: PASSED (`flutter build apk --release` sukses menghasilkan binari APK teroptimasi)
  9. `Upload APK artifact`: PASSED (Artefak `app-release-apk` berhasil diunggah ke GitHub)

---

## 8.4 SOP Instalasi & Pengujian Operasional di Perangkat

1. **Unduh APK:**
   - Masuk ke GitHub ➔ Repositori `Reyonl/warung-lupi-firebase` ➔ Tab **Actions** ➔ Pilih workflow run terakhir ➔ Unduh file artefak `app-release-apk.zip` dan ekstrak `app-release.apk`.
2. **Instalasi di HP Kasir / Toko:**
   - Pasang file APK di HP Android operasional.
3. **Pemeriksaan Fungsi Dasar:**
   - Buka aplikasi, pastikan 155 produk muncul seketika di daftar katalog.
   - Buka menu **Pengaturan**, periksa status modul bertuliskan `Cloud Firestore (Aktif)`.
   - Lakukan tes koneksi printer Bluetooth thermal (printer yang sudah terpasang tetap tersambung normal).
4. **Transaksi Uji Coba:**
   - Buat 1 transaksi bon baru di HP 1, periksa penomoran faktur format `INV-YYYYMMDD-NNN`.
   - Periksa ringkasan di dashboard harian.
