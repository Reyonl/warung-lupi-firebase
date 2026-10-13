import '../models/models.dart';

/// Kontrak repository pelanggan (implementasi produksi di [FirestoreCustomerRepository];
/// default kosong untuk unit/widget test tanpa jaringan).
class CustomerRepository {
  Future<List<Customer>> index({String search = '', bool? isActive}) async =>
      [];

  Future<Customer> store({
    required String name,
    String? phone,
    String? notes,
  }) async =>
      Customer(id: 1, name: name.trim(), phone: phone, notes: notes, isActive: true);

  Future<Customer> show(int id) async =>
      Customer(id: id, name: '', isActive: true);

  Future<Customer> update(
    int id, {
    String? name,
    String? phone,
    String? notes,
    bool? isActive,
  }) async =>
      Customer(
        id: id,
        name: name ?? '',
        phone: phone,
        notes: notes,
        isActive: isActive ?? true,
      );

  Future<void> destroy(int id) async {}

  Future<List<TransactionSummary>> transactions(int id) async => [];
}

/// Kontrak repository kategori.
class CategoryRepository {
  Future<List<Category>> index() async => [];

  Future<Category> store(String name) async =>
      Category(id: 1, name: name.trim(), productsCount: 0);

  Future<Category> update(int id, String name) async =>
      Category(id: id, name: name.trim(), productsCount: 0);

  Future<void> destroy(int id) async {}
}

/// Kontrak repository produk/item.
class ProductRepository {
  Future<List<Product>> index({
    String search = '',
    int? categoryId,
    bool? isActive,
  }) async =>
      [];

  Future<Product> store({
    required int categoryId,
    required String name,
    required int defaultPrice,
    required String unit,
    bool isActive = true,
  }) async =>
      Product(
        id: 1,
        categoryId: categoryId,
        name: name.trim(),
        defaultPrice: defaultPrice,
        unit: unit.trim(),
        isActive: isActive,
      );

  Future<Product> update(
    int id, {
    int? categoryId,
    String? name,
    int? defaultPrice,
    String? unit,
    bool? isActive,
  }) async =>
      Product(
        id: id,
        categoryId: categoryId,
        name: name ?? '',
        defaultPrice: defaultPrice ?? 0,
        unit: unit ?? 'pcs',
        isActive: isActive ?? true,
      );

  Future<void> destroy(int id) async {}
}

/// Kontrak repository transaksi/bon.
class TransactionRepository {
  Future<Paginated<Transaction>> index({
    String search = '',
    String? dateFrom,
    String? dateTo,
    String? status,
    int? customerId,
    int page = 1,
    int perPage = 20,
  }) async =>
      const Paginated(data: [], currentPage: 1, lastPage: 1, total: 0);

  Future<Transaction> store({
    required int customerId,
    required String transactionDate,
    String? notes,
  }) async =>
      Transaction(
        id: 1,
        customerId: customerId,
        transactionNumber: 'INV-001',
        transactionDate: transactionDate,
        totalAmount: 0,
        status: 'draft',
        paymentStatus: 'unpaid',
        notes: notes,
      );

  Future<Transaction> show(int id) async => Transaction(
        id: id,
        transactionNumber: 'INV-001',
        transactionDate: '',
        totalAmount: 0,
        status: 'draft',
        paymentStatus: 'unpaid',
      );

  Future<Transaction> update(
    int id, {
    int? customerId,
    String? transactionDate,
    String? status,
    String? paymentStatus,
    String? notes,
  }) async =>
      Transaction(
        id: id,
        customerId: customerId,
        transactionNumber: 'INV-001',
        transactionDate: transactionDate ?? '',
        totalAmount: 0,
        status: status ?? 'draft',
        paymentStatus: paymentStatus ?? 'unpaid',
        notes: notes,
      );

  Future<void> destroy(int id) async {}

  Future<TransactionItem> addItem(
    int transactionId, {
    int? productId,
    required String productName,
    String? description,
    required int quantity,
    String unit = 'pcs',
    required int unitPrice,
    int? subtotal,
  }) async =>
      TransactionItem(
        id: 1,
        transactionId: transactionId,
        productId: productId,
        productName: productName,
        description: description,
        quantity: quantity,
        unit: unit,
        unitPrice: unitPrice,
        subtotal: subtotal ?? (quantity * unitPrice),
      );

  Future<TransactionItem> updateItem(
    int itemId, {
    int? productId,
    String? productName,
    String? description,
    int? quantity,
    String? unit,
    int? unitPrice,
    int? subtotal,
  }) async =>
      TransactionItem(
        id: itemId,
        productId: productId,
        productName: productName ?? '',
        description: description,
        quantity: quantity ?? 1,
        unit: unit ?? 'pcs',
        unitPrice: unitPrice ?? 0,
        subtotal: subtotal ?? 0,
      );

  Future<void> deleteItem(int itemId) async {}
}

/// Kontrak repository pengeluaran.
class ExpenseRepository {
  Future<ExpensePage> index({
    String? dateFrom,
    String? dateTo,
    String? source,
    String? category,
    String? search,
    int page = 1,
  }) async =>
      const ExpensePage(
        data: [],
        summary: ExpenseSummary.empty,
        currentPage: 1,
        lastPage: 1,
        total: 0,
      );

  Future<Expense> store({
    required String expenseDate,
    required String title,
    String? category,
    required int amount,
    String? notes,
  }) async =>
      Expense(
        id: 1,
        expenseDate: expenseDate,
        title: title,
        category: category,
        amount: amount,
        source: 'manual',
        notes: notes,
      );

  Future<Expense> update(
    int id, {
    String? expenseDate,
    String? title,
    String? category,
    int? amount,
    String? notes,
  }) async =>
      Expense(
        id: id,
        expenseDate: expenseDate ?? '',
        title: title ?? '',
        category: category,
        amount: amount ?? 0,
        source: 'manual',
        notes: notes,
      );

  Future<void> destroy(int id) async {}
}

/// Kontrak repository dashboard.
class DashboardRepository {
  Future<DashboardData> index() async => const DashboardData(
        bonHariIni: 0,
        totalHariIni: 0,
        lunasHariIni: 0,
        lunasTotal: 0,
        masihHutang: 0,
        totalPelanggan: 0,
        recent: [],
      );
}

/// Kontrak repository laporan rokok.
class CigaretteReportRepository {
  Future<CigaretteReport> report({
    String? dateFrom,
    String? dateTo,
    String? product,
    String? search,
    int page = 1,
  }) async =>
      const CigaretteReport(
        summary: CigaretteSummary.empty,
        items: [],
        bons: [],
        bonTotal: 0,
        currentPage: 1,
        lastPage: 1,
        products: [],
      );

  Future<BonCigaretteSummary> bonSummary(int transactionId) async =>
      const BonCigaretteSummary(items: [], totalQuantity: 0, totalAmount: 0);
}

/// Data ringkasan dashboard.
class DashboardData {
  final int bonHariIni;
  final int totalHariIni;
  final int lunasHariIni;
  final int lunasTotal;
  final int masihHutang;
  final int pengeluaranHariIni;
  final int pengeluaranTotal;
  final int totalPelanggan;
  final List<TransactionSummary> recent;

  const DashboardData({
    required this.bonHariIni,
    required this.totalHariIni,
    required this.lunasHariIni,
    required this.lunasTotal,
    required this.masihHutang,
    this.pengeluaranHariIni = 0,
    this.pengeluaranTotal = 0,
    required this.totalPelanggan,
    required this.recent,
  });
}
