# Laporan Fase 2: Setup Firebase (Staging)

**Branch:** `feat/firebase-migration`  
**Tanggal Eksekusi:** 2026-10-12 22:31 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai Tahap Dependensi & Emulator (Menunggu login CLI & izin commit kredensial)

---

## 2.1 Penambahan Dependensi Flutter

Dependensi Firebase resmi ditambahkan ke `pubspec.yaml` via `flutter pub add`:

- `firebase_core: ^4.15.0`
- `firebase_auth: ^6.7.0`
- `cloud_firestore: ^6.10.0`

### Hasil Verifikasi Pengujian
- `flutter pub get`: Berhasil (Exit code: 0).
- `flutter test`: **64/64 tests passed (100% pass)**. Tidak ada regresi pada model, provider, maupun widget eksisting setelah penambahan dependensi Firebase.

---

## 2.2 Tooling CLI & Setup Lingkungan

- **`firebase-tools`:** Terpasang versi **15.33.0** secara global via npm.
- **`flutterfire_cli`:** Terpasang versi **1.4.1** via Dart pub global.
- **Java Runtime Emulator:** Menggunakan OpenJDK Temurin-17 (`D:\toolchain\jdk-17.0.20.1+1`).

---

## 2.3 Aturan Keamanan Awal (Security Rules)

Dibuat file `firestore.rules` dengan aturan deny-all (menolak semua akses baca & tulis) sesuai spesifikasi Fase 2:

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

## 2.4 Konfigurasi Firebase Emulator Suite

Dibuat file `firebase.json` dan `firestore.indexes.json` untuk pengujian lokal:

- **Firestore Emulator:** Port `8080` (binary `cloud-firestore-emulator-v1.22.0.jar` terunduh dan teruji).
- **Auth Emulator:** Port `9099`.
- **Emulator UI:** Port `4000` (binary `ui-v1.15.0.zip` terunduh).
- **Pengujian Emulator Startup:** Telah diuji dengan `firebase emulators:exec` dan berjalan sukses (Exit code: 0).

---

## 2.5 Langkah Lanjutan: Penghubungan Project Staging

Sesuai aturan keras nomor 3 dan instruksi Fase 2:
1. `firebase login` memerlukan autentikasi browser interaktif satu kali oleh pemilik akun Google.
2. Sebelum `google-services.json` atau `firebase_options.dart` di-commit, agen wajib meminta izin pengguna terlebih dahulu.
