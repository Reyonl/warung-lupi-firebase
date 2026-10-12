# Laporan Fase 5: Implementasi Repository Firestore Paralel & Feature Flag

**Tanggal Eksekusi:** 12 Oktober 2026  
**Branch:** `feat/firebase-migration`  
**Target Environment:** Firebase Staging (`warunglupi-staging-fa841`, Region `asia-southeast2`)  
**Status Fase 5:** **SELESAI & TERVERIFIKASI**

---

## 1. Ringkasan Eksekutif

Pada Fase 5, seluruh layer repository Cloud Firestore diimplementasikan secara berdampingan (paralel) dengan repository Dio/REST API asli. Seluruh kode backend Laravel yang ada di Flutter dipertahankan 100% tanpa modifikasi merusak, dan transisi dikendalikan penuh oleh **Feature Flag System** bertingkat:
1. Override runtime pengguna via penyimpanan preferensi lokal (`SharedPreferences`).
2. Antarmuka UI interaktif di menu **Pengaturan** aplikasi (*toggle switches*).
3. Nilai compile-time via `--dart-define` (`USE_FIRESTORE_*`).
4. Default fallback: `false` (selalu menggunakan Dio / REST API backend Laravel yang stabil).

---

## 2. Arsitektur Repository Paralel

### A. Repository Factory (`lib/repositories/repository_factory.dart`)
Setiap modul dihubungkan melalui `RepositoryFactory` yang mengembalikan instance yang tepat berdasarkan status feature flag:
- `CustomerRepository` ➔ `FirestoreCustomerRepository` vs `CustomerRepository` (Dio)
- `CategoryRepository` ➔ `FirestoreCategoryRepository` vs `CategoryRepository` (Dio)
- `ProductRepository` ➔ `FirestoreProductRepository` vs `ProductRepository` (Dio)
- `TransactionRepository` ➔ `FirestoreTransactionRepository` vs `TransactionRepository` (Dio)
- `ExpenseRepository` ➔ `FirestoreExpenseRepository` vs `ExpenseRepository` (Dio)
- `DashboardRepository` ➔ `FirestoreDashboardRepository` vs `DashboardRepository` (Dio)
- `CigaretteReportRepository` ➔ `FirestoreCigaretteReportRepository` vs `CigaretteReportRepository` (Dio)

### B. Implementasi Firestore (`lib/repositories/firestore_repositories.dart`)
Seluruh repository Firestore mengimplementasikan (`implements`) kontrak interface repository terkait:
- **`FirestoreCustomerRepository`**: Pencarian case-insensitive, pembuatan auto-ID Firestore, audit relasi bon aktif sebelum penghapusan (`CustomerRulesService`).
- **`FirestoreCategoryRepository`**: CRUD kategori dengan pengurutan alfabet.
- **`FirestoreProductRepository`**: Filter kategori dan status aktif, pencarian instan.
- **`FirestoreTransactionRepository`**: Penomoran atomik bon (`INV-YYYYMMDD-NNN` via Firestore transaction online, atau fallback `DRAFT-YYYYMMDD-XXX` offline Opsi B), subkoleksi `items`, hitung ulang total otomatis, dan sinkronisasi otomatis potongan bon (`subtotal < 0`) ke `expenses`.
- **`FirestoreExpenseRepository`**: CRUD pengeluaran manual, proteksi mutasi langsung pada pengeluaran bersumber `bon`.
- **`FirestoreDashboardRepository`**: Membaca rekapitulasi cepat harian dari `daily_summary/{today}` atau fallback kalkulasi agregasi langsung via `DashboardAggregateService`.
- **`FirestoreCigaretteReportRepository`**: Query transaksi completed, klasifikasi rokok berjenjang via `CigaretteClassifier`, dan pembuatan laporan omset rokok identik dengan API Laravel.

---

## 3. Serialisasi Dokumen Model (`lib/models/models.dart`)

Setiap model kini dilengkapi dengan metode konversi Firestore yang aman dan idempoten:
- `toDocument()`: Menghasilkan `Map<String, dynamic>` dengan format NoSQL Firestore (konversi ID legacy menjadi `legacyId` dan referensi string seperti `legacy_12`).
- `fromDocument(String docId, Map<String, dynamic> doc)`: Membaca dokumen Firestore dengan fallback cerdas untuk `legacyId` dari `docId` atau payload, serta mempertahankan tipe data mata uang Rupiah integer murni (`numFrom`).

Model yang dimutakhirkan:
- `Category`
- `Product`
- `Customer`
- `TransactionItem`
- `Transaction`
- `Expense`

---

## 4. Feature Flag & Pengaturan UI

### A. Konfigurasi (`lib/core/config/feature_flags.dart`)
Mendukung compile-time flags:
- `USE_FIRESTORE_ALL`
- `USE_FIRESTORE_CUSTOMERS`
- `USE_FIRESTORE_CATEGORIES`
- `USE_FIRESTORE_PRODUCTS`
- `USE_FIRESTORE_TRANSACTIONS`
- `USE_FIRESTORE_EXPENSES`
- `USE_FIRESTORE_DASHBOARD`
- `USE_FIRESTORE_CIGARETTES`

### B. UI Pengaturan (`lib/screens/settings/settings_screen.dart`)
Menambahkan kartu pengaturan **MIGRASI FIREBASE (STAGING FEATURE FLAGS)** dengan toggle switches interaktif untuk setiap modul maupun sakelar master (*Override Global*).

---

## 5. Hasil Verifikasi & Pengujian

### A. Unit Tests (`flutter test`)
- Total test berjalan: **102 tests**
- Status: **100% Passed (0 Failed, 0 Error)**
- Rincian pengujian baru Fase 5:
  - `test/firestore_models_test.dart`: 6 pengujian serialisasi/deserialisasi model Firestore.
  - `test/feature_flags_test.dart`: 3 pengujian hirarki dan override flags.
  - `test/repository_factory_test.dart`: 3 pengujian pengalihan dinamis Dio vs Firestore.
  - Seluruh 90 pengujian sebelumnya (golden tests rokok, invoice service, aggregate service, item order, transient retry) tetap lulus 100%.

### B. Static Analysis (`flutter analyze`)
- **0 Compile Errors**
- **0 Warnings**
- Semua warning `unused_import` dan `unnecessary_non_null_assertion` telah dibersihkan sepenuhnya.

---

## 6. Git Status & Commit
Seluruh perubahan berada di worktree `d:\laragon\www\warung_lupi_firebase` pada branch `feat/firebase-migration`. Belum ada `git push` yang dilakukan sesuai batasan keselamatan.
