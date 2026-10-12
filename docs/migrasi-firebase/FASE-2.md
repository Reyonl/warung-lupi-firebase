# Laporan Fase 2: Setup Firebase (Staging)

**Branch:** `feat/firebase-migration`  
**Tanggal Eksekusi:** 2026-10-12 22:55 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai Lengkap (Menunggu persetujuan commit kredensial & lanjut ke Fase 3)

---

## 2.1 Project Firebase Staging & Layanan Cloud

Project Firebase untuk tahap staging telah berhasil dibuat dan dikonfigurasi penuh:

- **Project Display Name:** `warunglupi-staging`
- **Project ID:** `warunglupi-staging-fa841`
- **Project Number:** `408892994802`
- **Cloud Firestore Database:** Aktif di region **`asia-southeast2` (Jakarta)**, mode `FIRESTORE_NATIVE` (Standard edition).
- **Firebase Authentication:** Provider **Anonymous (Anonim)** telah aktif.

---

## 2.2 Penambahan Dependensi Flutter

Dependensi Firebase resmi ditambahkan ke `pubspec.yaml` via `flutter pub add`:

- `firebase_core: ^4.15.0`
- `firebase_auth: ^6.7.0`
- `cloud_firestore: ^6.10.0`

### Hasil Pengujian Repositori
- `flutter pub get`: Berhasil (Exit code: 0).
- `flutter test`: **64/64 tests passed (100% pass)**. Tidak ada regresi pada model, provider, maupun widget eksisting setelah penambahan dependensi Firebase.

---

## 2.3 Tooling CLI & FlutterFire Configuration

- **`firebase-tools`:** Versi **15.33.0** via npm.
- **`flutterfire_cli`:** Versi **1.4.1** via Dart pub global.
- **FlutterFire Configuration:** Berhasil dieksekusi untuk platform Android:
  - Android App ID: `1:408892994802:android:f6edb91f8bd0432ac80c6b`
  - Package Name: `com.warunglupi.rekapan_warung`
  - Plugin Gradle `com.google.gms.google-services` versi 4.4.4 terpasang di `android/settings.gradle.kts` dan `android/app/build.gradle.kts`.
  - Berkas konfigurasi terbentuk: `android/app/google-services.json` dan `lib/firebase_options.dart`.

---

## 2.4 Aturan Keamanan Awal (Security Rules)

File `firestore.rules` disiapkan dengan aturan deny-all (menolak semua akses baca & tulis) sesuai spesifikasi Fase 2:

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // Rules awal Fase 2: menolak semua akses.
    // Rules final dengan validasi skema dan auth anonim ditulis di Fase 7.
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## 2.5 Konfigurasi Firebase Emulator Suite

File `firebase.json` dan `firestore.indexes.json` siap digunakan untuk pengujian lokal:

- **Firestore Emulator:** Port `8080` (binary `cloud-firestore-emulator-v1.22.0.jar` teruji).
- **Auth Emulator:** Port `9099`.
- **Emulator UI:** Port `4000` (binary `ui-v1.15.0.zip` teruji).
- **Java Toolchain:** OpenJDK Temurin-17 (`D:\toolchain\jdk-17.0.20.1+1`).
