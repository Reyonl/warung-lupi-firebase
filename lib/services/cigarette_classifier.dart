import '../models/models.dart';

/// Klasifikasi & agregasi penjualan rokok.
class CigaretteClassifier {
  CigaretteClassifier._();

  static const List<String> keywords = [
    'rokok',
    'surya',
    'sampoerna',
    's.prima',
    's. prima',
    'sprima',
    's.mild',
    's mild',
    'smild',
    'magnum',
    'mg. max',
    'mg. bintang',
    'djarum',
    'super 12',
    'super 16',
    'evo biru',
    'evo bold',
    'marlboro',
    'esse',
    'camel',
    'clas mild',
    'class mild',
    'classmild',
    '76 royal',
    '76 madu',
    '76 filter',
    '76 kurma',
    '76 ',
    'gg. filter',
    'gg filter',
    'gudang garam',
    'samsu',
    'dji sam soe',
    'ji sam su',
    'on bold',
    'diplomat',
    'gajah baru',
    'la bold',
    'la lights',
    'dunhill',
    'juara',
    'win mild',
    'kretek',
    'tembakau',
    'tingwe',
    'cerutu',
    'sukun',
    'sukor',
    'aroma',
    'red bold',
    'in mild',
    'inter',
    'vanguard',
    'chief',
    'andalan',
    'twizz',
    'apache',
    'sejati',
    'grendel',
  ];

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

  /// Canonical classifier untuk 1 item:
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

  /// Menghitung laporan agregasi rokok dari sekumpulan transaksi completed.
  static CigaretteReport generateReport(
    List<Map<String, dynamic>> transactionsData, {
    String? dateFrom,
    String? dateTo,
    String? productFilter,
    String? search,
  }) {
    final validTransactions = transactionsData.where((tx) {
      final status = tx['status']?.toString().toLowerCase();
      if (status != 'completed') return false;

      final rawTxDate =
          tx['transaction_date']?.toString() ?? tx['date']?.toString() ?? '';
      final txDate =
          rawTxDate.length >= 10 ? rawTxDate.substring(0, 10) : rawTxDate;
      if (dateFrom != null &&
          dateFrom.isNotEmpty &&
          txDate.compareTo(dateFrom) < 0) {
        return false;
      }
      if (dateTo != null &&
          dateTo.isNotEmpty &&
          txDate.compareTo(dateTo) > 0) {
        return false;
      }

      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        final num = (tx['transaction_number'] ?? tx['number'] ?? '')
            .toString()
            .toLowerCase();
        final cust = (tx['customer_name'] ?? tx['customerName'] ?? '')
            .toString()
            .toLowerCase();
        if (!num.contains(q) && !cust.contains(q)) return false;
      }

      return true;
    }).toList();

    int totalQuantity = 0;
    int totalSales = 0;
    int paidSales = 0;
    final Set<String> bonIds = {};
    final Map<String, _ProductAccumulator> itemMap = {};
    final List<CigaretteBonRow> txReports = [];
    final Set<String> distinctProducts = {};

    for (final tx in validTransactions) {
      final txId = (tx['id'] is int)
          ? tx['id'] as int
          : int.tryParse(tx['id']?.toString() ?? '0') ?? 0;
      final txNumber =
          (tx['transaction_number'] ?? tx['number'] ?? '').toString();
      final rawTxDate = (tx['transaction_date'] ?? tx['date'] ?? '').toString();
      final txDate =
          rawTxDate.length >= 10 ? rawTxDate.substring(0, 10) : rawTxDate;
      final rawCust =
          (tx['customer_name'] ?? tx['customerName'] ?? '').toString().trim();
      final customerName = rawCust.isEmpty ? 'Tanpa Nama' : rawCust;
      final paymentStatus =
          (tx['payment_status'] ?? tx['paymentStatus'] ?? 'unpaid').toString();
      final items = (tx['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      int txCigaretteQty = 0;
      int txCigaretteTotal = 0;

      for (final item in items) {
        final prodName =
            (item['product_name'] ?? item['productName'] ?? '').toString();
        final catName =
            (item['category_name'] ?? item['categoryName'] ?? '').toString();
        final desc = item['description']?.toString();
        final qty = (item['quantity'] is num)
            ? (item['quantity'] as num).toInt()
            : int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
        final subtotal = (item['subtotal'] is num)
            ? (item['subtotal'] as num).toInt()
            : int.tryParse(item['subtotal']?.toString() ?? '0') ?? 0;

        if (isCigarette(
          categoryName: catName,
          productName: prodName,
          description: desc,
        )) {
          distinctProducts.add(prodName);

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

          final acc = itemMap.putIfAbsent(
            prodName,
            () => _ProductAccumulator(prodName),
          );
          acc.quantity += qty;
          acc.sales += subtotal;
        }
      }

      if (txCigaretteQty > 0 || txCigaretteTotal > 0) {
        txReports.add(
          CigaretteBonRow(
            id: txId,
            transactionNumber: txNumber,
            transactionDate: txDate,
            customerName: customerName,
            paymentStatus: paymentStatus,
            cigaretteQuantity: txCigaretteQty,
            cigaretteTotal: txCigaretteTotal,
          ),
        );
      }
    }

    final sortedItems = itemMap.values
        .map(
          (e) => CigaretteItemRow(
            productName: e.name,
            totalQuantity: e.quantity,
            totalSales: e.sales,
          ),
        )
        .toList()
      ..sort((a, b) {
        final salesCmp = b.totalSales.compareTo(a.totalSales);
        if (salesCmp != 0) return salesCmp;
        return a.productName
            .toLowerCase()
            .compareTo(b.productName.toLowerCase());
      });

    txReports.sort((a, b) {
      final dateCmp = b.transactionDate.compareTo(a.transactionDate);
      if (dateCmp != 0) return dateCmp;
      return b.id.compareTo(a.id);
    });

    final sortedProducts = distinctProducts.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return CigaretteReport(
      summary: CigaretteSummary(
        cigaretteQuantity: totalQuantity,
        cigaretteSales: totalSales,
        bonCount: bonIds.length,
        paidSales: paidSales,
        unpaidSales: totalSales - paidSales,
      ),
      items: sortedItems,
      bons: txReports,
      bonTotal: txReports.length,
      currentPage: 1,
      lastPage: 1,
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
