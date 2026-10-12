# Laporan Fase 3: Desain Data Cloud Firestore

**Branch:** `feat/firebase-migration`  
**Tanggal Eksekusi:** 2026-10-12 23:06 WIB (UTC+7)  
**Pelaksana:** Engineer Migrasi Firebase  
**Status Gate:** Selesai (Menunggu Persetujuan Pengguna untuk Fase 4)

---

## 3.1 Prinsip dan Aturan Desain Data

Desain data NoSQL Firestore ini dirancang untuk menggantikan database relasional MariaDB tanpa mengorbankan performa, konsistensi data bon, dan tetap aman dalam batas kuota gratis Firebase Spark (50.000 read, 20.000 write, 20.000 delete per hari).

### 4 Aturan Wajib (Invarian)
1. **Nilai Uang Selalu `int` Rupiah (Tidak Pernah `double`):**
   - Semua nilai rupiah (`totalAmount`, `unitPrice`, `subtotal`, `amount`, `defaultPrice`) adalah bilangan bulat (`int` 64-bit).
   - Menghilangkan bug pembulatan desimal (*floating-point rounding error*).
2. **Tanggal Bisnis String ISO `yyyy-MM-dd`:**
   - Tanggal operasional warung (`date`, `expenseDate`, `month`) disimpan sebagai `String` berformat `yyyy-MM-dd` (misal: `"2026-10-12"`).
   - Memungkinkan pengurutan leksikografis langsung tanpa terpengaruh pergeseran zona waktu perangkat.
3. **Waktu Sistem Server Timestamp:**
   - Waktu audit sistem (`createdAt`, `updatedAt`) menggunakan `FieldValue.serverTimestamp()` di sisi client saat data ditulis/disinkronkan.
4. **Pelacakan Data Warisan (Legacy Tracking):**
   - Setiap dokumen hasil impor dari MariaDB wajib memiliki field `legacyId: int` (ID primary key asli) dan `migratedAt: Timestamp`. Dokumen baru yang dibuat di aplikasi memiliki `legacyId: null` dan `migratedAt: null`.

---

## 3.2 Struktur Koleksi dan Dokumen

### 1. Koleksi `customers`
Menyimpan master data pelanggan warung.
- **Path:** `/customers/{docId}`
- **Pola ID Dokumen:** `legacy_{id}` (data migrasi) atau Auto-ID Firestore (pelanggan baru).
- **Struktur Field:**
  ```typescript
  {
    name: string,                 // Nama pelanggan (wajib)
    phone: string | null,         // Nomor WhatsApp/telepon
    notes: string | null,         // Catatan khusus
    isActive: boolean,            // true = aktif, false = nonaktif (soft-delete)
    legacyId: number | null,      // misal: 41
    migratedAt: Timestamp | null,
    createdAt: Timestamp,
    updatedAt: Timestamp
  }
  ```
- **Relasi & Aturan Bisnis:**
  - Pelanggan yang masih memiliki riwayat bon tidak boleh dihapus (dicek via query `transactions` sebelum operasi hapus dilakukan).

---

### 2. Koleksi `categories`
Master kategori produk (misal: Minuman, Makanan, Rokok, Sembako).
- **Path:** `/categories/{docId}`
- **Pola ID Dokumen:** `legacy_{id}` atau Auto-ID.
- **Struktur Field:**
  ```typescript
  {
    name: string,                 // Nama kategori
    legacyId: number | null,
    migratedAt: Timestamp | null,
    createdAt: Timestamp,
    updatedAt: Timestamp
  }
  ```

---

### 3. Koleksi `products`
Master produk barang dagangan.
- **Path:** `/products/{docId}`
- **Pola ID Dokumen:** `legacy_{id}` atau Auto-ID.
- **Struktur Field:**
  ```typescript
  {
    categoryId: string,           // docId referensi ke /categories/{id}
    name: string,                 // Nama produk
    defaultPrice: number,         // int Rupiah (misal: 15000)
    unit: string,                 // "pcs", "bks", "gelas", dll. (default: "pcs")
    isActive: boolean,            // Status aktif
    legacyId: number | null,
    migratedAt: Timestamp | null,
    createdAt: Timestamp,
    updatedAt: Timestamp
  }
  ```
- **Optimasi Kuota:**
  - Total produk saat ini ~155 dokumen. Seluruh koleksi dimuat satu kali saat aplikasi dibuka dan disimpan dalam cache memori lokal untuk pencarian cepat saat membuat bon (*zero Firestore read per keystroke*).

---

### 4. Koleksi `transactions` (Header Bon)
Menyimpan ringkasan transaksi bon warung.
- **Path:** `/transactions/{docId}`
- **Pola ID Dokumen:** `legacy_{id}` (migrasi) atau Auto-ID / Invoice-based.
- **Struktur Field:**
  ```typescript
  {
    customerId: string,           // docId referensi ke /customers/{id}
    customerName: string,         // Denormalisasi nama pelanggan saat transaksi dibuat
    number: string,               // Nomor invoice unik (misal: "INV-20261012-001")
    date: string,                 // Tanggal transaksi ("yyyy-MM-dd")
    totalAmount: number,          // int Rupiah (net total = SUM subtotal items)
    status: "draft" | "completed",
    paymentStatus: "unpaid" | "paid",
    type: "sale" | "purchase",    // Default: "sale"
    notes: string | null,
    itemCount: number,            // Jumlah baris item pada bon
    legacyId: number | null,
    migratedAt: Timestamp | null,
    createdAt: Timestamp,
    updatedAt: Timestamp
  }
  ```

---

### 5. Sub-koleksi `transactions/{transactionId}/items` (Detail Item Bon)
Setiap baris item transaksi disimpan di sub-koleksi dokumen transaksinya.
- **Path:** `/transactions/{transactionId}/items/{docId}`
- **Pola ID Dokumen:** `legacy_{id}` atau Auto-ID.
- **Struktur Field:**
  ```typescript
  {
    productId: string | null,     // docId produk jika dari master, null jika manual
    productName: string,          // Snapshot nama produk saat bon dibuat (imutable)
    description: string | null,   // Catatan tambahan item (misal: nama orang, tgl bon)
    quantity: number,             // int (default: 1)
    unit: string,                 // default: "pcs"
    unitPrice: number,            // int Rupiah (bisa negatif untuk POTONGAN/retur)
    subtotal: number,             // int Rupiah (quantity * unitPrice)
    sortOrder: number,            // Urutan baris di tampilan struk
    legacyId: number | null,
    migratedAt: Timestamp | null,
    createdAt: Timestamp,
    updatedAt: Timestamp
  }
  ```
- **Invarian Metode Potongan (Minus):**
  - Item potongan/pengurangan dicatat dengan `unitPrice < 0` dan `subtotal < 0`.
  - Net total transaksi di header selalu sama dengan `SUM(subtotal)` item.

---

### 6. Koleksi `expenses`
Mencatat pengeluaran warung (baik input manual maupun sinkronisasi otomatis dari potongan bon).
- **Path:** `/expenses/{docId}`
- **Pola ID Dokumen:**
  - Manual: `legacy_{id}` atau Auto-ID.
  - Otomatis dari Bon: `bon_{transactionId}_{itemId}` (Idempotent Doc ID).
- **Struktur Field:**
  ```typescript
  {
    date: string,                 // "yyyy-MM-dd"
    title: string,                // Nama pengeluaran
    category: string | null,      // "Belanja Warung", "Operasional", dll.
    amount: number,               // int Rupiah (nilai absolut positif)
    source: "manual" | "bon",     // Sumber pengeluaran
    transactionId: string | null, // docId transaksi jika sumber = "bon"
    syncKey: string | null,       // "bon_{transactionId}_{itemId}"
    notes: string | null,
    legacyId: number | null,
    migratedAt: Timestamp | null,
    createdAt: Timestamp,
    updatedAt: Timestamp
  }
  ```

---

### 7. Dokumen Rollup `daily_summary` (Denormalisasi Dashboard)
Mencegah query agregasi `COUNT` dan `SUM` ke seluruh dokumen transaksi setiap kali dashboard dibuka.
- **Path:** `/daily_summary/{yyyy-MM-dd}`
- **ID Dokumen:** Tanggal hari terkait (misal: `"2026-10-12"`).
- **Struktur Field:**
  ```typescript
  {
    date: string,                 // "yyyy-MM-dd"
    saleTotal: number,            // Total penjualan bersih hari ini (Rp)
    saleCount: number,            // Jumlah transaksi bon hari ini
    paidTotal: number,            // Total bon lunas hari ini (Rp)
    unpaidTotal: number,          // Total bon belum lunas hari ini (Rp)
    expenseTotal: number,         // Total pengeluaran hari ini (Rp)
    expenseManual: number,        // Pengeluaran manual (Rp)
    expenseBon: number,           // Pengeluaran dari potongan bon (Rp)
    updatedAt: Timestamp
  }
  ```
- **Cara Kerja:**
  - Diperbarui via batch write atomik saat bon baru dibuat, diubah status pembayarannya, atau saat pengeluaran dicatat.

---

### 8. Dokumen Rollup `cigarette_sales` (Laporan Rokok Materialized)
Menyimpan agregasi penjualan rokok bulanan agar laporan rokok tidak perlu memindai ribuan item transaksi.
- **Path:** `/cigarette_sales/{yyyy-MM}`
- **ID Dokumen:** Bulan terkait (misal: `"2026-10"`).
- **Struktur Field:**
  ```typescript
  {
    month: string,                // "yyyy-MM"
    bonCount: number,             // Jumlah transaksi yang memuat rokok
    totalQuantity: number,        // Total bungkus terjual
    totalAmount: number,          // Total nominal penjualan rokok (Rp)
    perProduct: {
      [productName: string]: {
        quantity: number,         // Jumlah terjual per merek
        amount: number            // Subtotal nominal per merek
      }
    },
    updatedAt: Timestamp
  }
  ```

---

## 3.3 Indeks Komposit (`firestore.indexes.json`)

Telah didefinisikan 4 indeks komposit untuk mendukung penyaringan dan pengurutan di aplikasi:

1. **`transactions` (Filter Pelanggan + Urutan Tanggal):**
   - Fields: `customerId ASC`, `date DESC`
   - Kegunaan: Layar Riwayat Bon Pelanggan (`where customerId == x order by date desc`).
2. **`transactions` (Filter Status Bayar + Urutan Tanggal):**
   - Fields: `paymentStatus ASC`, `date DESC`
   - Kegunaan: Layar Daftar Hutang Belum Lunas (`where paymentStatus == 'unpaid' order by date desc`).
3. **`expenses` (Filter Sumber + Urutan Tanggal):**
   - Fields: `source ASC`, `date DESC`
   - Kegunaan: Filter Pengeluaran Manual vs Bon (`where source == 'manual' order by date desc`).
4. **`expenses` (Filter Kategori + Urutan Tanggal):**
   - Fields: `category ASC`, `date DESC`
   - Kegunaan: Rekap Pengeluaran berdasarkan kategori.

---

## 3.4 Matriks Pemetaan dari MariaDB Snapshot ke Firestore

| Tabel MariaDB | Koleksi Firestore | docId Migrasi | Catatan Khusus Tipe Data |
|---|---|---|---|
| `customers` | `/customers` | `legacy_{id}` | `is_active` (`TINYINT 1`) ➔ `isActive` (`boolean`) |
| `categories` | `/categories` | `legacy_{id}` | string `name` |
| `products` | `/products` | `legacy_{id}` | `default_price` (`DECIMAL`) ➔ `defaultPrice` (`int`) |
| `transactions` | `/transactions` | `legacy_{id}` | `total_amount` (`DECIMAL`) ➔ `totalAmount` (`int`), `type` dipertahankan |
| `transaction_items`| `/transactions/{tId}/items` | `legacy_{id}` | `quantity` ➔ `int`, `unit_price` ➔ `int`, `subtotal` ➔ `int` |
| `expenses` | `/expenses` | `legacy_{id}` / `bon_{tid}_{iid}` | `amount` ➔ `int` positif |
