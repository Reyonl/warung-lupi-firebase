/// Parsing angka yang tahan terhadap bentuk data dari backend Laravel.
///
/// MySQL mengembalikan hasil agregat (`SUM()`, `AVG()`) pada kolom DECIMAL
/// sebagai **string** JSON (mis. `"2195000"`), bukan number. Konversi
/// `value as num` langsung akan melempar `TypeError` dan mematikan seluruh
/// layar yang bersangkutan (gejala: dashboard gagal memuat / data tidak muncul).
/// Helper ini menerima int, double, maupun String numerik.
int numFrom(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  }
  return fallback;
}

/// Varian nullable dari [numFrom] — null tetap null (untuk kolom opsional).
int? numFromOrNull(dynamic v) => v == null ? null : numFrom(v);

/// Model Kategori — mirror tabel `categories`.
class Category {
  final int id;
  final String name;
  final int? productsCount; // dari withCount('products')
  final List<Product>? products; // dari show()

  const Category({
    required this.id,
    required this.name,
    this.productsCount,
    this.products,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: numFrom(json['id']),
      name: (json['name'] ?? '') as String,
      productsCount: json['products_count'] != null
          ? numFrom(json['products_count'])
          : (json['products'] is List
                ? (json['products'] as List).length
                : null),
      products: json['products'] is List
          ? (json['products'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Product.fromJson)
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {'name': name};

  Map<String, dynamic> toDocument() => {
    'name': name,
    if (id > 0) 'legacyId': id,
  };

  factory Category.fromDocument(String docId, Map<String, dynamic> doc) {
    int parsedId = numFrom(doc['legacyId'] ?? doc['id']);
    if (parsedId == 0 && docId.startsWith('legacy_')) {
      parsedId = int.tryParse(docId.replaceFirst('legacy_', '')) ?? 0;
    }
    return Category(
      id: parsedId,
      name: (doc['name'] ?? '') as String,
      productsCount: numFromOrNull(
        doc['productsCount'] ?? doc['products_count'],
      ),
    );
  }
}

/// Model Produk/Item — mirror tabel `products`.
class Product {
  final int id;
  final int? categoryId;
  final String name;
  final int defaultPrice;
  final String unit;
  final bool isActive;
  final Category? category; // nested dari with('category')

  const Product({
    required this.id,
    this.categoryId,
    required this.name,
    required this.defaultPrice,
    required this.unit,
    required this.isActive,
    this.category,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: numFrom(json['id']),
      categoryId: numFromOrNull(json['category_id']),
      name: (json['name'] ?? '') as String,
      defaultPrice: numFrom(json['default_price']),
      unit: (json['unit'] ?? 'pcs') as String,
      isActive: json['is_active'] == true || json['is_active'] == 1,
      category: json['category'] is Map
          ? Category.fromJson(json['category'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'category_id': categoryId,
    'name': name,
    'default_price': defaultPrice,
    'unit': unit,
    'is_active': isActive,
  };

  Map<String, dynamic> toDocument() => {
    'categoryId': categoryId != null ? 'legacy_$categoryId' : null,
    'name': name,
    'defaultPrice': defaultPrice,
    'unit': unit,
    'isActive': isActive,
    if (id > 0) 'legacyId': id,
  };

  factory Product.fromDocument(
    String docId,
    Map<String, dynamic> doc, {
    Category? category,
  }) {
    int parsedId = numFrom(doc['legacyId'] ?? doc['id']);
    if (parsedId == 0 && docId.startsWith('legacy_')) {
      parsedId = int.tryParse(docId.replaceFirst('legacy_', '')) ?? 0;
    }
    final catRaw = doc['categoryId'] ?? doc['category_id'];
    int? catId;
    if (catRaw is int) {
      catId = catRaw;
    } else if (catRaw is String) {
      catId = int.tryParse(catRaw.replaceFirst('legacy_', ''));
    }
    return Product(
      id: parsedId,
      categoryId: catId,
      name: (doc['name'] ?? '') as String,
      defaultPrice: numFrom(doc['defaultPrice'] ?? doc['default_price']),
      unit: (doc['unit'] ?? 'pcs') as String,
      isActive: doc['isActive'] == true ||
          doc['is_active'] == true ||
          doc['is_active'] == 1,
      category: category,
    );
  }
}

/// Model Pelanggan — mirror tabel `customers`.
class Customer {
  final int id;
  final String name;
  final String? phone;
  final String? notes;
  final bool isActive;
  final int? transactionsCount; // dari loadCount('transactions')

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    required this.isActive,
    this.transactionsCount,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: numFrom(json['id']),
      name: (json['name'] ?? '') as String,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] == true || json['is_active'] == 1,
      transactionsCount: numFromOrNull(json['transactions_count']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': (phone == null || phone!.isEmpty) ? null : phone,
    'notes': (notes == null || notes!.isEmpty) ? null : notes,
  };

  Map<String, dynamic> toDocument() => {
    'name': name,
    'phone': (phone == null || phone!.isEmpty) ? null : phone,
    'notes': (notes == null || notes!.isEmpty) ? null : notes,
    'isActive': isActive,
    if (id > 0) 'legacyId': id,
  };

  factory Customer.fromDocument(
    String docId,
    Map<String, dynamic> doc, {
    int? transactionsCount,
  }) {
    int parsedId = numFrom(doc['legacyId'] ?? doc['id']);
    if (parsedId == 0 && docId.startsWith('legacy_')) {
      parsedId = int.tryParse(docId.replaceFirst('legacy_', '')) ?? 0;
    }
    return Customer(
      id: parsedId,
      name: (doc['name'] ?? '') as String,
      phone: doc['phone'] as String?,
      notes: doc['notes'] as String?,
      isActive: doc['isActive'] == true ||
          doc['is_active'] == true ||
          doc['is_active'] == 1,
      transactionsCount: transactionsCount ??
          numFromOrNull(doc['transactionsCount'] ?? doc['transactions_count']),
    );
  }
}

/// Model Item Bon — mirror tabel `transaction_items`.
class TransactionItem {
  final int id;
  final int? transactionId;
  final int? productId;
  final String productName;
  final String? description;
  final int quantity;
  final String unit;
  final int unitPrice;
  final int subtotal;

  const TransactionItem({
    required this.id,
    this.transactionId,
    this.productId,
    required this.productName,
    this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.subtotal,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: numFrom(json['id']),
      transactionId: numFromOrNull(json['transaction_id']),
      productId: numFromOrNull(json['product_id']),
      productName: (json['product_name'] ?? '') as String,
      description: json['description'] as String?,
      quantity: numFrom(json['quantity'], fallback: 1),
      unit: (json['unit'] ?? 'pcs') as String,
      unitPrice: numFrom(json['unit_price']),
      subtotal: numFrom(json['subtotal']),
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'product_name': productName,
    'description': (description == null || description!.isEmpty)
        ? null
        : description,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'subtotal': subtotal,
  };

  Map<String, dynamic> toDocument() => {
    'productId': productId != null ? 'legacy_$productId' : null,
    'productName': productName,
    'description': (description == null || description!.isEmpty)
        ? null
        : description,
    'quantity': quantity,
    'unit': unit,
    'unitPrice': unitPrice,
    'subtotal': subtotal,
    if (id > 0) 'legacyId': id,
  };

  factory TransactionItem.fromDocument(
    String docId,
    Map<String, dynamic> doc, {
    int? transactionId,
  }) {
    int parsedId = numFrom(doc['legacyId'] ?? doc['id']);
    if (parsedId == 0 && docId.startsWith('legacy_')) {
      parsedId = int.tryParse(docId.replaceFirst('legacy_', '')) ?? 0;
    }
    final prodRaw = doc['productId'] ?? doc['product_id'];
    int? prodId;
    if (prodRaw is int) {
      prodId = prodRaw;
    } else if (prodRaw is String) {
      prodId = int.tryParse(prodRaw.replaceFirst('legacy_', ''));
    }
    return TransactionItem(
      id: parsedId,
      transactionId: transactionId ??
          numFromOrNull(doc['transactionId'] ?? doc['transaction_id']),
      productId: prodId,
      productName:
          (doc['productName'] ?? doc['product_name'] ?? '') as String,
      description: doc['description'] as String?,
      quantity: numFrom(doc['quantity'], fallback: 1),
      unit: (doc['unit'] ?? 'pcs') as String,
      unitPrice: numFrom(doc['unitPrice'] ?? doc['unit_price']),
      subtotal: numFrom(doc['subtotal']),
    );
  }
}

/// Model Transaksi/Bon — mirror tabel `transactions`.
class Transaction {
  final int id;
  final int? customerId;
  final String transactionNumber;
  final String transactionDate; // yyyy-MM-dd (DATE dari Laravel)
  final int totalAmount;
  final String status; // draft | completed
  final String paymentStatus; // unpaid | paid
  final String? notes;
  final Customer? customer; // nested from with('customer')
  final List<TransactionItem> items; // nested from with('items')

  const Transaction({
    required this.id,
    this.customerId,
    required this.transactionNumber,
    required this.transactionDate,
    required this.totalAmount,
    required this.status,
    required this.paymentStatus,
    this.notes,
    this.customer,
    this.items = const [],
  });

  bool get isCompleted => status == 'completed';
  bool get isPaid => paymentStatus == 'paid';

  /// Salinan transaksi dengan item disusun ulang mengikuti [orderedIds]
  /// (id item dari atas ke bawah, hasil reorder manual di layar Buat/Edit Bon).
  ///
  /// Backend TIDAK menyimpan urutan (tabel `transaction_items` tidak punya
  /// kolom order/sort; `GET /transactions/{id}` selalu mengembalikan item
  /// berdasarkan `id`), jadi urutan ini hanya hidup untuk sesi berjalan —
  /// dipakai preview nota, cetak thermal, PDF, PNG, copy, dan RawBT.
  /// Id asing/sudah hilang dibuang; item yang belum punya urutan
  /// manual diletakkan di akhir sesuai urutan server.
  Transaction withItemOrder(List<int> orderedIds) {
    if (orderedIds.isEmpty || items.isEmpty) return this;
    final byId = <int, TransactionItem>{for (final it in items) it.id: it};
    final out = <TransactionItem>[];
    for (final id in orderedIds) {
      final it = byId.remove(id);
      if (it != null) out.add(it);
    }
    out.addAll(byId.values);
    return Transaction(
      id: id,
      customerId: customerId,
      transactionNumber: transactionNumber,
      transactionDate: transactionDate,
      totalAmount: totalAmount,
      status: status,
      paymentStatus: paymentStatus,
      notes: notes,
      customer: customer,
      items: out,
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: numFrom(json['id']),
      customerId: numFromOrNull(json['customer_id']),
      transactionNumber: (json['transaction_number'] ?? '') as String,
      transactionDate: (json['transaction_date'] ?? '').toString().substring(
        0,
        10,
      ),
      totalAmount: numFrom(json['total_amount']),
      status: (json['status'] ?? 'draft') as String,
      paymentStatus: (json['payment_status'] ?? 'unpaid') as String,
      notes: json['notes'] as String?,
      customer: json['customer'] is Map
          ? Customer.fromJson(json['customer'] as Map<String, dynamic>)
          : null,
      items: json['items'] is List
          ? (json['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(TransactionItem.fromJson)
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toDocument() => {
    'customerId': customerId != null ? 'legacy_$customerId' : null,
    'customerName': customer?.name,
    'number': transactionNumber,
    'date': transactionDate,
    'totalAmount': totalAmount,
    'status': status,
    'paymentStatus': paymentStatus,
    'notes': (notes == null || notes!.isEmpty) ? null : notes,
    'itemCount': items.length,
    if (id > 0) 'legacyId': id,
  };

  factory Transaction.fromDocument(
    String docId,
    Map<String, dynamic> doc, {
    Customer? customer,
    List<TransactionItem> items = const [],
  }) {
    int parsedId = numFrom(doc['legacyId'] ?? doc['id']);
    if (parsedId == 0 && docId.startsWith('legacy_')) {
      parsedId = int.tryParse(docId.replaceFirst('legacy_', '')) ?? 0;
    }
    final custRaw = doc['customerId'] ?? doc['customer_id'];
    int? custId;
    if (custRaw is int) {
      custId = custRaw;
    } else if (custRaw is String) {
      custId = int.tryParse(custRaw.replaceFirst('legacy_', ''));
    }
    final rawDate =
        (doc['date'] ?? doc['transaction_date'] ?? '').toString();
    final dateStr = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    return Transaction(
      id: parsedId,
      customerId: custId,
      transactionNumber:
          (doc['number'] ?? doc['transaction_number'] ?? '') as String,
      transactionDate: dateStr,
      totalAmount: numFrom(doc['totalAmount'] ?? doc['total_amount']),
      status: (doc['status'] ?? 'draft') as String,
      paymentStatus:
          (doc['paymentStatus'] ?? doc['payment_status'] ?? 'unpaid')
              as String,
      notes: doc['notes'] as String?,
      customer: customer,
      items: items,
    );
  }
}

/// Item ringan untuk daftar bon (Dashboard recent & Customer transactions).
class TransactionSummary {
  final int id;
  final String transactionNumber;
  final String transactionDate; // sudah 'd M Y' dari backend
  final int totalAmount;
  final String status;
  final String? paymentStatus;
  final String? customerName;

  const TransactionSummary({
    required this.id,
    required this.transactionNumber,
    required this.transactionDate,
    required this.totalAmount,
    required this.status,
    this.paymentStatus,
    this.customerName,
  });

  factory TransactionSummary.fromJson(Map<String, dynamic> json) {
    return TransactionSummary(
      id: numFrom(json['id']),
      transactionNumber: (json['transaction_number'] ?? '') as String,
      transactionDate: (json['transaction_date'] ?? '') as String,
      totalAmount: numFrom(json['total_amount']),
      status: (json['status'] ?? 'draft') as String,
      paymentStatus: json['payment_status'] as String?,
      customerName: json['customer_name'] as String?,
    );
  }
}

/// Helper untuk response Laravel paginator: `{ data: [...], current_page, last_page, ... }`
class Paginated<T> {
  final List<T> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const Paginated({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final items = json['data'] is List
        ? (json['data'] as List)
              .whereType<Map<String, dynamic>>()
              .map(fromJson)
              .toList()
        : <T>[];
    return Paginated(
      data: items,
      currentPage: numFrom(json['current_page'], fallback: 1),
      lastPage: numFrom(json['last_page'], fallback: 1),
      total: numFrom(json['total'], fallback: items.length),
    );
  }
}

// ==================== LAPORAN ROKOK ====================
// Padanan `Api\CigaretteReportController` + `resources/js/pages/CigaretteReport.jsx`.
// Sumber kebenaran klasifikasi ada di server (CigaretteReportService);
// Flutter hanya membaca hasil, TIDAK mengulang rule 'rokok' di sini.

/// Baris item rokok — dipakai breakdown laporan maupun ringkasan satu bon.
/// (`unitPrice` hanya terisi pada respons `bonSummary`.)
class CigaretteItemRow {
  final String productName;
  final int totalQuantity;
  final int totalSales;
  final int? unitPrice;

  const CigaretteItemRow({
    required this.productName,
    required this.totalQuantity,
    required this.totalSales,
    this.unitPrice,
  });

  factory CigaretteItemRow.fromJson(Map<String, dynamic> json) =>
      CigaretteItemRow(
        productName: (json['product_name'] ?? '') as String,
        totalQuantity: numFrom(json['total_quantity'] ?? json['quantity']),
        totalSales: numFrom(json['total_sales'] ?? json['subtotal']),
        unitPrice: json['unit_price'] != null
            ? numFrom(json['unit_price'])
            : null,
      );
}

/// Baris bon yang mengandung penjualan rokok (paginated).
class CigaretteBonRow {
  final int id;
  final String transactionNumber;
  final String transactionDate;
  final String? customerName;
  final String paymentStatus;
  final int cigaretteQuantity;
  final int cigaretteTotal;

  const CigaretteBonRow({
    required this.id,
    required this.transactionNumber,
    required this.transactionDate,
    this.customerName,
    required this.paymentStatus,
    required this.cigaretteQuantity,
    required this.cigaretteTotal,
  });

  factory CigaretteBonRow.fromJson(Map<String, dynamic> json) =>
      CigaretteBonRow(
        id: numFrom(json['id']),
        transactionNumber: (json['transaction_number'] ?? '') as String,
        transactionDate: (json['transaction_date'] ?? '').toString(),
        customerName: json['customer_name'] as String?,
        paymentStatus: (json['payment_status'] ?? 'unpaid') as String,
        cigaretteQuantity: numFrom(json['cigarette_quantity']),
        cigaretteTotal: numFrom(json['cigarette_total']),
      );
}

/// Summary laporan rokok — kolom DECIMAL/SUM bisa datang sebagai String.
class CigaretteSummary {
  final int cigaretteQuantity;
  final int cigaretteSales;
  final int bonCount;
  final int paidSales;
  final int unpaidSales;

  const CigaretteSummary({
    required this.cigaretteQuantity,
    required this.cigaretteSales,
    required this.bonCount,
    required this.paidSales,
    required this.unpaidSales,
  });

  static const empty = CigaretteSummary(
    cigaretteQuantity: 0,
    cigaretteSales: 0,
    bonCount: 0,
    paidSales: 0,
    unpaidSales: 0,
  );

  factory CigaretteSummary.fromJson(Map<String, dynamic> json) =>
      CigaretteSummary(
        cigaretteQuantity: numFrom(json['cigarette_quantity']),
        cigaretteSales: numFrom(json['cigarette_sales']),
        bonCount: numFrom(json['bon_count']),
        paidSales: numFrom(json['paid_sales']),
        unpaidSales: numFrom(json['unpaid_sales']),
      );
}

/// Response lengkap `GET /api/reports/cigarettes`.
class CigaretteReport {
  final CigaretteSummary summary;
  final List<CigaretteItemRow> items;
  final List<CigaretteBonRow> bons;
  final int bonTotal;
  final int currentPage;
  final int lastPage;
  final List<String> products;

  const CigaretteReport({
    required this.summary,
    required this.items,
    required this.bons,
    required this.bonTotal,
    required this.currentPage,
    required this.lastPage,
    required this.products,
  });

  factory CigaretteReport.fromJson(Map<String, dynamic> json) {
    final tx = json['transactions'] is Map
        ? (json['transactions'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CigaretteReport(
      summary: CigaretteSummary.fromJson(
        json['summary'] is Map
            ? (json['summary'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{},
      ),
      items: (json['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CigaretteItemRow.fromJson)
          .toList(),
      bons: (tx['data'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CigaretteBonRow.fromJson)
          .toList(),
      bonTotal: numFrom(tx['total']),
      currentPage: numFrom(tx['current_page'], fallback: 1),
      lastPage: numFrom(tx['last_page'], fallback: 1),
      products: (json['products'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

// ==================== PENGELUARAN ====================
// Padanan `Api\ExpenseController` + `resources/js/pages/expenses/ExpenseList.jsx`.
// `source` = `manual` (input langsung) | `bon` (auto dari item minus).

/// Satu catatan pengeluaran — mirror tabel `expenses`.
class Expense {
  final int id;
  final String expenseDate; // yyyy-MM-dd
  final String title;
  final String? category;
  final int amount; // selalu positif (nominal pengeluaran)
  final String source; // manual | bon
  final int? transactionId;
  final String? transactionNumber; // dari relasi transaction
  final String? notes;

  const Expense({
    required this.id,
    required this.expenseDate,
    required this.title,
    this.category,
    required this.amount,
    required this.source,
    this.transactionId,
    this.transactionNumber,
    this.notes,
  });

  bool get isFromBon => source == 'bon';

  factory Expense.fromJson(Map<String, dynamic> json) {
    final tx = json['transaction'];
    final rawDate = (json['expense_date'] ?? '').toString();
    return Expense(
      id: numFrom(json['id']),
      // datetime DB bisa datang sebagai "2026-10-12 00:00:00" → ambil 10
      // karakter pertama; string kosong / pendek jangan sampai RangeError.
      expenseDate: rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate,
      title: (json['title'] ?? '') as String,
      category: json['category'] as String?,
      amount: numFrom(json['amount']),
      source: (json['source'] ?? 'manual') as String,
      transactionId: tx is Map ? numFromOrNull(tx['id']) : null,
      transactionNumber: tx is Map
          ? (tx['transaction_number'] as String?)
          : null,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'expense_date': expenseDate,
    'title': title,
    if (category != null && category!.isNotEmpty) 'category': category,
    'amount': amount,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };

  Map<String, dynamic> toDocument() => {
    'date': expenseDate,
    'title': title,
    if (category != null && category!.isNotEmpty) 'category': category,
    'amount': amount,
    'source': source,
    if (transactionId != null) 'transactionId': 'legacy_$transactionId',
    if (transactionNumber != null) 'transactionNumber': transactionNumber,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    if (id > 0) 'legacyId': id,
  };

  factory Expense.fromDocument(String docId, Map<String, dynamic> doc) {
    int parsedId = numFrom(doc['legacyId'] ?? doc['id']);
    if (parsedId == 0 && docId.startsWith('legacy_')) {
      parsedId = int.tryParse(docId.replaceFirst('legacy_', '')) ?? 0;
    }
    final rawDate =
        (doc['date'] ?? doc['expense_date'] ?? '').toString();
    final dateStr = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    final txRaw = doc['transactionId'] ?? doc['transaction_id'];
    int? txId;
    if (txRaw is int) {
      txId = txRaw;
    } else if (txRaw is String) {
      txId = int.tryParse(txRaw.replaceFirst('legacy_', ''));
    }

    return Expense(
      id: parsedId,
      expenseDate: dateStr,
      title: (doc['title'] ?? '') as String,
      category: doc['category'] as String?,
      amount: numFrom(doc['amount']),
      source: (doc['source'] ?? 'manual') as String,
      transactionId: txId,
      transactionNumber: doc['transactionNumber'] as String?,
      notes: doc['notes'] as String?,
    );
  }
}

/// Ringkasan pengeluaran — `summary` dari `GET /api/expenses`
/// (mengikuti filter aktif; SUM DECIMAL bisa datang sebagai String).
class ExpenseSummary {
  final int totalAmount;
  final int count;
  final int manualAmount;
  final int bonAmount;

  const ExpenseSummary({
    required this.totalAmount,
    required this.count,
    required this.manualAmount,
    required this.bonAmount,
  });

  static const empty = ExpenseSummary(
    totalAmount: 0,
    count: 0,
    manualAmount: 0,
    bonAmount: 0,
  );

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) {
    final bySource = json['by_source'] is Map
        ? (json['by_source'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return ExpenseSummary(
      totalAmount: numFrom(json['total_amount']),
      count: numFrom(json['count']),
      manualAmount: numFrom(bySource['manual']),
      bonAmount: numFrom(bySource['bon']),
    );
  }
}

/// Response halaman pengeluaran — `GET /api/expenses?page=...`
/// (data paginated + summary mengikuti filter).
class ExpensePage {
  final List<Expense> data;
  final int currentPage;
  final int lastPage;
  final int total;
  final ExpenseSummary summary;

  const ExpensePage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.summary,
  });

  factory ExpensePage.fromJson(Map<String, dynamic> json) {
    final dataJson = json['data'] is List ? json['data'] as List : const [];
    return ExpensePage(
      data: dataJson
          .whereType<Map<String, dynamic>>()
          .map(Expense.fromJson)
          .toList(),
      currentPage: numFrom(json['current_page'], fallback: 1),
      lastPage: numFrom(json['last_page'], fallback: 1),
      total: numFrom(json['total'], fallback: dataJson.length),
      summary: json['summary'] is Map
          ? ExpenseSummary.fromJson(
              (json['summary'] as Map).cast<String, dynamic>(),
            )
          : ExpenseSummary.empty,
    );
  }
}

/// Hasil pemisahan item bon: penambahan vs pengurangan (potongan).
/// Padanan `splitItems()` di CreateTransaction.jsx & TransactionDetail.jsx —
/// item minus = potongan, juga tercatat sebagai pengeluaran di backend.
class ItemSplit {
  final List<TransactionItem> adds;
  final List<TransactionItem> deductions;
  final int totalBefore; // jumlah subtotal item penambahan (+)
  final int totalDeduct; // jumlah |subtotal| item pengurangan

  const ItemSplit({
    required this.adds,
    required this.deductions,
    required this.totalBefore,
    required this.totalDeduct,
  });

  bool get hasDeductions => deductions.isNotEmpty;
  int get finalTotal => totalBefore - totalDeduct;
}

/// Pisahkan item bon: subtotal >= 0 → penambahan, < 0 → pengurangan.
ItemSplit splitItems(List<TransactionItem> items) {
  final adds = <TransactionItem>[];
  final deductions = <TransactionItem>[];
  for (final item in items) {
    if (item.subtotal < 0) {
      deductions.add(item);
    } else {
      adds.add(item);
    }
  }
  final totalBefore = adds.fold<int>(0, (s, i) => s + i.subtotal);
  final totalDeduct = deductions.fold<int>(0, (s, i) => s + i.subtotal.abs());
  return ItemSplit(
    adds: adds,
    deductions: deductions,
    totalBefore: totalBefore,
    totalDeduct: totalDeduct,
  );
}

/// Ringkasan rokok satu bon — `GET /api/transactions/{id}/cigarettes`.
class BonCigaretteSummary {
  final List<CigaretteItemRow> items;
  final int totalQuantity;
  final int totalAmount;

  const BonCigaretteSummary({
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
  });

  factory BonCigaretteSummary.fromJson(Map<String, dynamic> json) =>
      BonCigaretteSummary(
        items: (json['items'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CigaretteItemRow.fromJson)
            .toList(),
        totalQuantity: numFrom(json['total_quantity']),
        totalAmount: numFrom(json['total_amount']),
      );
}
