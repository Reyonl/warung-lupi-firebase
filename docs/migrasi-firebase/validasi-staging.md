# Laporan Validasi Data Firestore Staging (Fase 6)

**Project Firebase:** `warunglupi-staging-fa841`  
**Lokasi/Region:** `asia-southeast2` (Jakarta)  
**Database Sumber:** MySQL `warung_migrasi_snapshot` (Laragon Localhost)  
**Tanggal Validasi:** 12 Oktober 2026  
**Status Validasi:** **COCOK 100% (IDENTIK TANPA SELISIH)**

---

## 1. Tabel Perbandingan & Integritas Data

| No | Entitas / Koleksi | Sumber MySQL Snapshot | Cloud Firestore Staging | Status Validasi |
|:---|:---|:---|:---|:---:|
| 1 | **Kategori (`categories`)** | 5 baris | 5 dokumen (`legacy_1` s.d. `legacy_5`) | **COCOK 100%** |
| 2 | **Produk (`products`)** | 155 baris | 155 dokumen (`legacy_1` s.d. `legacy_157`) | **COCOK 100%** |
| 3 | **Pelanggan (`customers`)** | 38 baris | 38 dokumen (`legacy_1` s.d. `legacy_39`) | **COCOK 100%** |
| 4 | **Transaksi (`transactions`)** | 14 baris | 14 dokumen | **COCOK 100%** |
| 5 | **Subkoleksi Item (`items`)** | 195 baris | 195 dokumen | **COCOK 100%** |
| 6 | **Total Omset Bon** | **Rp 2.435.000** | **Rp 2.435.000** | **COCOK 100%** |
| 7 | **Jumlah Subtotal Item** | **Rp 2.435.000** | **Rp 2.435.000** | **COCOK 100%** |
| 8 | **Pengeluaran Potongan Bon** | 7 baris (Rp 326.000) | 7 dokumen (`bon_{txId}_{itemId}`) | **COCOK 100%** |
| 9 | **Ringkasan Harian (`daily_summary`)** | 6 tanggal bisnis | 6 dokumen (Total Omset: Rp 2.435.000) | **COCOK 100%** |
| 10 | **Counter Penomoran (`counters`)** | 6 tanggal bisnis | 6 dokumen (`inv_YYYYMMDD`) | **COCOK 100%** |

---

## 2. Rincian Transaksi & Omset per Tanggal Bisnis

| Tanggal | Jumlah Bon | Nomor Bon Terakhir | Max Sequence (`inv_YYYYMMDD`) | Omset Harian | Status Pembayaran |
|:---|:---:|:---|:---:|:---:|:---:|
| **2026-09-27** | 1 | `INV-20260927-013` | 13 | Rp 338.000 | 1 unpaid |
| **2026-10-05** | 1 | `INV-20261005-001` | 1 | Rp 108.000 | 1 unpaid |
| **2026-10-07** | 2 | `INV-20261007-011` | 11 | Rp 573.000 | 2 unpaid |
| **2026-10-08** | 3 | `INV-20261008-011` | 11 | Rp 888.000 | 3 unpaid |
| **2026-10-09** | 2 | `INV-20261009-010` | 10 | Rp 145.000 | 2 unpaid |
| **2026-10-12** | 5 | `INV-20261012-013` | 13 | Rp 383.000 | 5 unpaid |
| **TOTAL** | **14** | - | - | **Rp 2.435.000** | **14 unpaid** |

---

## 3. Rincian Potongan Bon (Sinkronisasi ke `expenses`)

Tujuh item dengan `subtotal < 0` berhasil disinkronkan ke koleksi `expenses` dengan `source: 'bon'`:

| ID Item | ID Bon | Nomor Bon | Nama Item | Subtotal | Dokumen Firestore |
|:---|:---|:---|:---|:---:|:---|
| 1357 | 51 | `INV-20260927-013` | TITIP BON | -Rp 50.000 | `expenses/bon_51_1357` |
| 2191 | 166 | `INV-20261005-001` | TITIP BON | -Rp 100.000 | `expenses/bon_166_2191` |
| 2208 | 203 | `INV-20261008-003` | IKAN KEMBUNG | -Rp 50.000 | `expenses/bon_203_2208` |
| 2301 | 256 | `INV-20261012-003` | TITIP | -Rp 40.000 | `expenses/bon_256_2301` |
| 2302 | 258 | `INV-20261012-005` | SIMPAN | -Rp 6.000 | `expenses/bon_258_2302` |
| 2320 | 228 | `INV-20261009-010` | TITIP BON | -Rp 50.000 | `expenses/bon_228_2320` |
| 2353 | 261 | `INV-20261012-008` | SIMPAN | -Rp 30.000 | `expenses/bon_261_2353` |
| **TOTAL** | - | - | - | **-Rp 326.000** | **7 Dokumen (Rp 326.000)** |

---

## 4. Pengujian Idempotensi
Script migrasi telah dijalankan sebanyak dua kali berturut-turut:
- Eksekusi ke-1: 426 dokumen ditulis (2 batch).
- Eksekusi ke-2: 426 dokumen di-update ulang secara aman tanpa ada duplikasi dokumen, tanpa error, dan jumlah hitungan seluruh koleksi tetap identik 100%.
- Semua dokumen NoSQL menggunakan deterministic key (`legacy_{id}` dan `bon_{txId}_{itemId}`).
