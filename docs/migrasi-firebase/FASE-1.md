# Laporan Fase 1: Baseline Repositori

**Branch:** `feat/firebase-migration`  
**Tanggal Eksekusi:** 2026-10-12 22:18 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai (Menunggu Persetujuan Pengguna untuk Fase 2)

---

## 1.1 Hasil Eksekusi Baseline Tooling

Pengujian baseline repositori Flutter dilakukan pada worktree `D:\laragon\www\warung_lupi_firebase` sebelum ada perubahan kode apa pun untuk migrasi Firebase.

### 1. `flutter pub get`
- **Status:** Berhasil (Exit code: 0)
- **Ringkasan:** Resolusi dependensi berhasil penuh tanpa error. 20 paket memiliki versi rilis baru tetapi terkunci constraint (normal untuk stabilitas).

### 2. `flutter analyze`
- **Status:** Selesai dengan catatan (50 issues `info`, 0 errors, 0 warnings)
- **Rincian temuan baseline:**
  - `use_null_aware_elements`: 12 temuan di `lib/providers/repositories.dart` & `lib/widgets/widgets.dart`
  - `deprecated_member_use`: 3 temuan (ReorderableListView `onReorder`, `Share.shareXFiles` dari share_plus)
  - `prefer_interpolation_to_compose_strings`: 17 temuan di `lib/services/printer_service.dart` & `bon_detail_screen.dart`
  - `curly_braces_in_flow_control_structures`: 8 temuan di `settings_screen.dart`, `category_list_screen.dart`, dll.
  - `use_build_context_synchronously`: 1 temuan di `product_list_screen.dart:399`
  - `unnecessary_underscores`: 3 temuan
- **Kesimpulan:** Tidak ada syntax error atau blocker kompilasi. Semua temuan adalah linter info bawaan repositori yang dipertahankan utuh.

### 3. `flutter test`
- **Status:** **100% PASS** (Exit code: 0)
- **Hasil:** **64 tests passed**, 4 tests skipped (live API test dilewati karena butuh flag `--dart-define=RUN_LIVE_TESTS=true`).
- **Cakupan tes baseline:**
  - Unit test parsing model (`Expense`, `splitItems`, `Transaction`, `Customer`, `Product`)
  - Provider test (`BonDraftProvider`, `DashboardData`)
  - Widget test (`AppFormField`, `StatusBadge`, `CustomerSearchField`, `ProductSearchField`, `calculatePromoSubtotal`, `ThermalReceipt`)
  - Retry mechanism test (`transient_retry_test.dart`)

---

## 1.2 Catatan Versi Toolchain

| Komponen | Target | Terpasang Aktual | Status |
|---|---|---|---|
| **Flutter SDK** | 3.47.5 | **Flutter 3.47.5** (channel stable, revision `6a19cca564`, Dart 3.13.4) di `D:\flutter\bin` | **Sesuai Target** |
| **Java System (PATH)** | 17 | Java 25.0.1 (Oracle LTS) di PATH sistem | Berjalan di Windows |
| **Java Toolchain Gradle** | 17 | **OpenJDK Temurin-17.0.20.1+1** di `D:\toolchain\jdk-17.0.20.1+1` | **Tersedia untuk build Android Gradle** |

---

## 1.3 Verifikasi Invarian & Keamanan Jaringan

1. **`baseUrl` di `lib/core/api/api_client.dart:31`:**
   - Baris 31: `static const String productionBaseUrl = 'https://warunglupi.tplp004.com';`
   - **Status:** **TIDAK DIUBAH** sama sekali, sesuai aturan keras.
2. **Batasan Jaringan Android Release:**
   - Manifest saat ini memuat `android:usesCleartextTraffic="true"`.
   - Pada build rilis Android modern (API 28+), panggilan HTTP tanpa TLS (seperti ke IP langsung `http://13.212.177.233`) diblokir secara default oleh OS Android kecuali ada `network_security_config.xml`.
   - Target migrasi ke Cloud Firestore menggunakan protokol gRPC/HTTPS dengan enkripsi TLS bawaan Google, sehingga rilis APK ke depan otomatis terlindungi dan tidak rentan pemblokiran cleartext HTTP.
