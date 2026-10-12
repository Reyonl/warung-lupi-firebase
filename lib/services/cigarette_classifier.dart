/// Model data item rokok untuk laporan.
class CigaretteItemReport {
  final String productName;
  final int totalQuantity;
  final int totalSales;

  const CigaretteItemReport({
    required this.productName,
    required this.totalQuantity,
    required this.totalSales,
  });

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'total_quantity': totalQuantity,
        'total_sales': totalSales,
      };
}

/// Model data bon yang memuat item rokok.
class CigaretteTransactionReport {
  final int id;
  final String transactionNumber;
  final String transactionDate;
  final String customerName;
  final String paymentStatus;
  final int cigaretteQuantity;
  final int cigaretteTotal;

  const CigaretteTransactionReport({
    required this.id,
    required this.transactionNumber,
    required this.transactionDate,
    required this.customerName,
    required this.paymentStatus,
    required this.cigaretteQuantity,
    required this.cigaretteTotal,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'transaction_number': transactionNumber,
        'transaction_date': transactionDate,
        'customer_name': customerName,
        'payment_status': paymentStatus,
        'cigarette_quantity': cigaretteQuantity,
        'cigarette_total': cigaretteTotal,
      };
}

/// Model ringkasan laporan rokok.
class CigaretteSummaryReport {
  final int cigaretteQuantity;
  final int cigaretteSales;
  final int bonCount;
  final int paidSales;
  final int unpaidSales;

  const CigaretteSummaryReport({
    required this.cigaretteQuantity,
    required this.cigaretteSales,
    required this.bonCount,
    required this.paidSales,
    required this.unpaidSales,
  });

  Map<String, dynamic> toJson() => {
        'cigarette_quantity': cigaretteQuantity,
        'cigarette_sales': cigaretteSales,
        'bon_count': bonCount,
        'paid_sales': paidSales,
        'unpaid_sales': unpaidSales,
      };
}

/// Hasil lengkap laporan rokok.
class CigaretteReportResult {
  final CigaretteSummaryReport summary;
  final List<CigaretteItemReport> items;
  final List<CigaretteTransactionReport> transactions;
  final List<String> products;

  const CigaretteReportResult({
    required this.summary,
    required this.items,
    required this.transactions,
    required this.products,
  });

  Map<String, dynamic> toJson() => {
        'summary': summary.toJson(),
        'items': items.map((e) => e.toJson()).toList(),
        'transactions': {
          'data': transactions.map((e) => e.toJson()).toList(),
          'total': transactions.length,
          'per_page': 20,
          'current_page': 1,
          'last_page': 1,
        },
        'products': products,
      };
}

/// Klasifikasi & agregasi penjualan rokok (porting persis dari Laravel [CigaretteReportService]).
class CigaretteClassifier {
  CigaretteClassifier._();

  static const List<String> keywords = ['rokok'];

  /// Normalisasi teks: lowercase, trim, spasi ganda dirapikan menjadi satu.
  static String normalize(String? value) {
    if (value == null) return '';
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Mengecek apakah teks mengandung keyword 'rokok'.
  static bool textIsCigarette(String? value) {
    final text = normalize(value);
    if (text.isEmpty) return false;

    for (final keyword in keywords) {
      if (text.contains(normalize(keyword))) {
        return true;
      }
    }
    return false;
  }

  /// Canonical classifier untuk 1 item (persis baris 63-81 CigaretteReportService.php).
  /// Prioritas:
  /// 1. Category name (sumber utama jika ada category)
  /// 2. Snapshot productName
  /// 3. Snapshot description
  static bool isCigarette({
    String? categoryName,
    required String productName,
    String? description,
  }) {
    if (categoryName != null && categoryName.isNotEmpty) {
      if (textIsCigarette(categoryName)) {
        return true;
      }
    }

    if (textIsCigarette(productName)) {
      return true;
    }

    return textIsCigarette(description);
  }

  /// Menghitung laporan agregasi rokok dari sekumpulan transaksi completed (persis baris 140-241).
  /// [transactions]: daftar map transaksi yang memuat header dan items.
  static CigaretteReportResult generateReport(
    List<Map<String, dynamic>> transactionsData, {
    String? dateFrom,
    String? dateTo,
    String? productFilter,
    String? search,
  }) {
    // 1. Filter hanya transaksi completed
    var validTransactions = transactionsData.where((tx) {
      final status = tx['status']?.toString().toLowerCase();
      if (status != 'completed') return false;

      final txDate = tx['transaction_date']?.toString() ?? tx['date']?.toString() ?? '';
      if (dateFrom != null && dateFrom.isNotEmpty && txDate.compareTo(dateFrom) < 0) return false;
      if (dateTo != null && dateTo.isNotEmpty && txDate.compareTo(dateTo) > 0) return false;

      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        final num = (tx['transaction_number'] ?? tx['number'] ?? '').toString().toLowerCase();
        final cust = (tx['customer_name'] ?? '').toString().toLowerCase();
        if (!num.contains(q) && !cust.contains(q)) return false;
      }

      return true;
    }).toList();

    int totalQuantity = 0;
    int totalSales = 0;
    int paidSales = 0;
    final Set<String> bonIds = {};
    final Map<String, _ProductAccumulator> itemMap = {};
    final List<CigaretteTransactionReport> txReports = [];
    final Set<String> distinctProducts = {};

    for (final tx in validTransactions) {
      final txId = (tx['id'] is int) ? tx['id'] as int : int.tryParse(tx['id']?.toString() ?? '0') ?? 0;
      final txNumber = (tx['transaction_number'] ?? tx['number'] ?? '').toString();
      final txDate = (tx['transaction_date'] ?? tx['date'] ?? '').toString();
      final customerName = (tx['customer_name'] ?? 'Tanpa Nama').toString();
      final paymentStatus = (tx['payment_status'] ?? tx['paymentStatus'] ?? 'unpaid').toString();
      final items = (tx['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      int txCigaretteQty = 0;
      int txCigaretteTotal = 0;

      for (final item in items) {
        final prodName = (item['product_name'] ?? item['productName'] ?? '').toString();
        final catName = (item['category_name'] ?? item['categoryName'] ?? '').toString();
        final desc = item['description']?.toString();
        final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
        final subtotal = (item['subtotal'] is num) ? (item['subtotal'] as num).toInt() : int.tryParse(item['subtotal']?.toString() ?? '0') ?? 0;

        if (isCigarette(categoryName: catName, productName: prodName, description: desc)) {
          // Kumpulkan produk rokok yang terdaftar untuk filter
          distinctProducts.add(prodName);

          // Cek filter produk jika ada
          if (productFilter != null && productFilter.trim().isNotEmpty) {
            if (prodName.toLowerCase() != productFilter.trim().toLowerCase()) {
              continue;
            }
          }

          totalQuantity += qty;
          totalSales += subtotal;
          if (paymentStatus == 'paid') {
            paidSales += subtotal;
          }

          bonIds.add(txId.toString());
          txCigaretteQty += qty;
          txCigaretteTotal += subtotal;

          // Item breakdown accumulator (grouped by product_name)
          final acc = itemMap.putIfAbsent(prodName, () => _ProductAccumulator(prodName));
          acc.quantity += qty;
          acc.sales += subtotal;
        }
      }

      if (txCigaretteQty > 0 || txCigaretteTotal > 0) {
        txReports.add(CigaretteTransactionReport(
          id: txId,
          transactionNumber: txNumber,
          transactionDate: txDate,
          customerName: customerName,
          paymentStatus: paymentStatus,
          cigaretteQuantity: txCigaretteQty,
          cigaretteTotal: txCigaretteTotal,
        ));
      }
    }

    // Sort items by total_sales descending (persis orderByDesc('total_sales'))
    final sortedItems = itemMap.values.map((e) => CigaretteItemReport(
          productName: e.name,
          totalQuantity: e.quantity,
          totalSales: e.sales,
        )).toList()
      ..sort((a, b) {
        final salesCmp = b.totalSales.compareTo(a.totalSales);
        if (salesCmp != 0) return salesCmp;
        return a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
      });

    // Sort transactions by date desc, then id desc
    txReports.sort((a, b) {
      final dateCmp = b.transactionDate.compareTo(a.transactionDate);
      if (dateCmp != 0) return dateCmp;
      return b.id.compareTo(a.id);
    });

    // Sort distinct products alphabetically case-insensitive
    final sortedProducts = distinctProducts.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return CigaretteReportResult(
      summary: CigaretteSummaryReport(
        cigaretteQuantity: totalQuantity,
        cigaretteSales: totalSales,
        bonCount: bonIds.length,
        paidSales: paidSales,
        unpaidSales: totalSales - paidSales,
      ),
      items: sortedItems,
      transactions: txReports,
      products: sortedProducts,
    );
  }
}

class _ProductAccumulator {
  final String name;
  int quantity = 0;
  int sales = 0;

  _ProductAccumulator(this.name);
}
