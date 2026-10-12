import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../models/models.dart';
import '../repositories/repository_factory.dart';
import '../utils/format.dart';
import 'repositories.dart';

/// Base state bagi provider yang memuat list + loading + error.
mixin LoadableState {
  bool loading = false;
  String? error;
}

/// Dashboard provider — menampilkan stats & bon terbaru.
class DashboardProvider extends ChangeNotifier with LoadableState {
  DashboardProvider(this._repo);

  final DashboardRepository _repo;

  DashboardData? data;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      data = await _repo.index();
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Gagal memuat dashboard.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// Customer provider — list, filter, toggle, hapus.
class CustomerProvider extends ChangeNotifier with LoadableState {
  CustomerProvider(this._repo);

  final CustomerRepository _repo;

  List<Customer> customers = [];
  String search = '';
  bool filterActive = true; // default "Aktif" (sama dgn web)
  int? togglingId;

  Future<void> load({bool resetSearch = false}) async {
    if (resetSearch) search = '';
    loading = true;
    error = null;
    notifyListeners();
    try {
      customers = await _repo.index(
        search: search,
        isActive: filterActive ? true : null, // null = Semua
      );
      if (customers.isEmpty) {}
    } catch (e) {
      error = ApiClient.errorMessage(
        e,
        fallback: 'Gagal memuat data pelanggan.',
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSearch(String v) {
    search = v;
    // debounce di screen
  }

  void setFilterActive(bool v) {
    filterActive = v;
    load();
  }

  Future<void> doSearch(String v) async {
    search = v;
    await load();
  }

  Future<String?> toggleActive(Customer c) async {
    togglingId = c.id;
    notifyListeners();
    try {
      final updated = await _repo.update(c.id, isActive: !c.isActive);
      final idx = customers.indexWhere((x) => x.id == c.id);
      if (idx != -1) customers[idx] = updated;
      return updated.isActive ? 'diaktifkan' : 'dinonaktifkan';
    } catch (e) {
      return null;
    } finally {
      togglingId = null;
      notifyListeners();
    }
  }

  Future<String?> delete(Customer c) async {
    try {
      await _repo.destroy(c.id);
      customers.removeWhere((x) => x.id == c.id);
      notifyListeners();
      return 'Pelanggan "${c.name}" berhasil dihapus.';
    } catch (e) {
      return ApiClient.errorMessage(e, fallback: 'Gagal menghapus pelanggan.');
    }
  }

  Future<void> save({
    int? id,
    required String name,
    String? phone,
    String? notes,
  }) async {
    if (id == null) {
      await _repo.store(name: name, phone: phone, notes: notes);
    } else {
      await _repo.update(id, name: name, phone: phone, notes: notes);
    }
    await load();
  }
}

/// Category provider.
class CategoryProvider extends ChangeNotifier with LoadableState {
  CategoryProvider(this._repo);

  final CategoryRepository _repo;

  List<Category> categories = [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      categories = await _repo.index();
    } catch (e) {
      error = ApiClient.errorMessage(
        e,
        fallback: 'Gagal memuat data kategori.',
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Category?> add(String name) async {
    try {
      final c = await _repo.store(name);
      categories = [c, ...categories];
      notifyListeners();
      return c;
    } catch (e) {
      rethrow;
    }
  }

  Future<Category?> update(int id, String name) async {
    try {
      final c = await _repo.update(id, name);
      final idx = categories.indexWhere((x) => x.id == id);
      // update selalu mengembalikan Category baru (tidak null)
      if (idx != -1) categories[idx] = c;
      notifyListeners();
      return c;
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> delete(Category c) async {
    try {
      await _repo.destroy(c.id);
      categories.removeWhere((x) => x.id == c.id);
      notifyListeners();
      return 'Kategori berhasil dihapus.';
    } catch (e) {
      return ApiClient.errorMessage(e, fallback: 'Gagal menghapus kategori.');
    }
  }
}

/// Product provider.
class ProductProvider extends ChangeNotifier with LoadableState {
  ProductProvider(this._repo, [CategoryRepository? catRepo]) {
    _catRepo = catRepo ?? RepositoryFactory.categoryRepository();
  }

  final ProductRepository _repo;
  late CategoryRepository _catRepo;

  List<Product> products = [];
  List<Category> categories = [];
  String search = '';
  int? filterCategory;
  bool? filterActive; // null = Semua, true = Aktif, false = Nonaktif
  String? toast;

  Future<void> loadCategories() async {
    try {
      categories = await _catRepo.index();
    } catch (_) {}
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      products = await _repo.index(
        search: search,
        categoryId: filterCategory,
        isActive: filterActive,
      );
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Gagal memuat data item.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSearch(String v) => search = v;
  void setFilterCategory(int? v) {
    filterCategory = v;
    load();
  }

  void setFilterActive(bool? v) {
    filterActive = v;
    load();
  }

  Future<Product> save({
    int? id,
    required int categoryId,
    required String name,
    required int defaultPrice,
    required String unit,
    bool isActive = true,
  }) async {
    if (id == null) {
      final p = await _repo.store(
        categoryId: categoryId,
        name: name,
        defaultPrice: defaultPrice,
        unit: unit,
        isActive: isActive,
      );
      products = [p, ...products];
      notifyListeners();
      return p;
    } else {
      final p = await _repo.update(
        id,
        categoryId: categoryId,
        name: name,
        defaultPrice: defaultPrice,
        unit: unit,
        isActive: isActive,
      );
      final idx = products.indexWhere((x) => x.id == id);
      if (idx != -1) products[idx] = p;
      notifyListeners();
      return p;
    }
  }

  Future<String?> toggleActive(Product p) async {
    try {
      final updated = await _repo.update(p.id, isActive: !p.isActive);
      final idx = products.indexWhere((x) => x.id == p.id);
      if (idx != -1) products[idx] = updated;
      notifyListeners();
      return 'Status item diubah menjadi ${updated.isActive ? 'Aktif' : 'Nonaktif'}.';
    } catch (e) {
      return 'Gagal mengubah status.';
    }
  }

  Future<String?> delete(Product p) async {
    try {
      await _repo.destroy(p.id);
      products.removeWhere((x) => x.id == p.id);
      notifyListeners();
      return 'Item berhasil dihapus.';
    } catch (e) {
      return 'Gagal menghapus item.';
    }
  }

  void showToast(String message, {bool error = false}) {
    toast = message;
    notifyListeners();
  }

  void clearToast() {
    toast = null;
    notifyListeners();
  }
}

/// Transaction provider — list bon (filter + pagination).
class TransactionListProvider extends ChangeNotifier with LoadableState {
  TransactionListProvider(this._repo);

  final TransactionRepository _repo;

  List<Transaction> transactions = [];
  int currentPage = 1;
  int lastPage = 1;
  int total = 0;
  String search = '';
  String? dateFrom;
  String? dateTo;
  String? status;
  int? customerId;

  Future<void> load({int page = 1}) async {
    currentPage = page;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await _repo.index(
        search: search,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
        customerId: customerId,
        page: page,
      );
      transactions = res.data;
      currentPage = res.currentPage;
      lastPage = res.lastPage;
      total = res.total;
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Gagal memuat data bon.');
      transactions = [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSearch(String v) {
    search = v;
    load(page: 1);
  }

  void setDateRange(String? from, String? to) {
    dateFrom = from;
    dateTo = to;
    load(page: 1);
  }

  void nextPage() {
    if (currentPage < lastPage) load(page: currentPage + 1);
  }

  void prevPage() {
    if (currentPage > 1) load(page: currentPage - 1);
  }

  Future<String?> delete(int id) async {
    try {
      await _repo.destroy(id);
      await load(page: currentPage);
      return null;
    } catch (e) {
      return 'Gagal menghapus bon.';
    }
  }
}

/// Provider pengeluaran — mirror `ExpenseList.jsx` + `Api\ExpenseController`.
///
/// Filter mengikuti web: rentang tanggal (date_from/date_to), sumber
/// (manual|bon), dan pencarian; ringkasan total ikut filter aktif.
/// Pengeluaran `source=bon` tidak bisa diedit/dihapus manual (backend 422).
class ExpenseProvider extends ChangeNotifier with LoadableState {
  ExpenseProvider(this._repo);

  final ExpenseRepository _repo;

  ExpensePage? page;
  String dateFrom = '';
  String dateTo = '';
  String source = '';
  String search = '';
  int currentPage = 1;

  bool get hasData => page != null;
  ExpenseSummary get summary => page?.summary ?? ExpenseSummary.empty;

  /// Muat halaman pengeluaran (default halaman 1 / halaman [page]).
  Future<void> load({int page = 1}) async {
    currentPage = page;
    loading = true;
    error = null;
    notifyListeners();
    try {
      this.page = await _repo.index(
        dateFrom: dateFrom,
        dateTo: dateTo,
        source: source,
        search: search,
        page: page,
      );
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Gagal memuat pengeluaran.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setDateRange(String from, String to) {
    dateFrom = from;
    dateTo = to;
    load(page: 1);
  }

  /// Pilih satu sisi rentang lewat date picker (mirip _pickDate di laporan rokok).
  Future<void> pickDate(BuildContext context, {required bool isFrom}) async {
    final current = isFrom ? dateFrom : dateTo;
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (isFrom) {
      dateFrom = toInputDate(picked);
    } else {
      dateTo = toInputDate(picked);
    }
    load(page: 1);
  }

  void setSource(String v) {
    source = v;
    load(page: 1);
  }

  void setSearch(String v) {
    search = v;
    load(page: 1);
  }

  void resetFilter() {
    dateFrom = '';
    dateTo = '';
    source = '';
    search = '';
    load(page: 1);
  }

  /// Simpan pengeluaran manual (tambah bila [id] null, edit bila ada).
  /// Mengembalikan pesan error siap tampil, atau null bila sukses.
  Future<String?> save({
    int? id,
    required String expenseDate,
    required String title,
    String? category,
    required int amount,
    String? notes,
  }) async {
    try {
      if (id == null) {
        await _repo.store(
          expenseDate: expenseDate,
          title: title,
          category: category,
          amount: amount,
          notes: notes,
        );
      } else {
        await _repo.update(
          id,
          expenseDate: expenseDate,
          title: title,
          category: category,
          amount: amount,
          notes: notes,
        );
      }
      // Header/summary dihitung server → selalu muat ulang halaman aktif.
      await load(page: id == null ? 1 : currentPage);
      return null;
    } catch (e) {
      return ApiClient.errorMessage(
        e,
        fallback: 'Gagal menyimpan pengeluaran.',
      );
    }
  }

  /// Hapus pengeluaran manual. Pengeluaran dari bon ditolak backend (422).
  Future<String?> delete(Expense e) async {
    try {
      await _repo.destroy(e.id);
      await load(page: currentPage);
      return null;
    } catch (err) {
      return ApiClient.errorMessage(
        err,
        fallback: 'Gagal menghapus pengeluaran.',
      );
    }
  }
}

/// Provider laporan rokok — mirror perilaku `CigaretteReport.jsx`.
/// Default periode: hari ini (sama seperti web).
class CigaretteReportProvider extends ChangeNotifier with LoadableState {
  CigaretteReportProvider(this._repo);

  final CigaretteReportRepository _repo;

  CigaretteReport? report;
  String dateFrom = today();
  String dateTo = today();
  String product = '';
  String search = '';

  bool get hasData => report != null;
  CigaretteSummary get summary => report?.summary ?? CigaretteSummary.empty;

  Future<void> load({int page = 1}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      report = await _repo.report(
        dateFrom: dateFrom,
        dateTo: dateTo,
        product: product,
        search: search,
        page: page,
      );
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Laporan gagal dimuat.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setDateRange(String from, String to) {
    dateFrom = from;
    dateTo = to;
    load(page: 1);
  }

  void setProduct(String v) {
    product = v;
    load(page: 1);
  }

  void setSearch(String v) {
    search = v;
    load(page: 1);
  }

  void nextPage() {
    if (report != null && report!.currentPage < report!.lastPage) {
      load(page: report!.currentPage + 1);
    }
  }

  void prevPage() {
    if (report != null && report!.currentPage > 1) {
      load(page: report!.currentPage - 1);
    }
  }
}

/// Data bersama untuk layar Buat/Edit Bon (CreateTransaction + TransactionDetail).
class BonDraftProvider extends ChangeNotifier {
  BonDraftProvider(this._repo);

  final TransactionRepository _repo;

  // Header
  int? transactionId;
  String transactionNumber = '';
  int? customerId;
  String customerName = '';
  String transactionDate = '';
  String notes = '';
  String paymentStatus = 'unpaid';
  bool headerSaved = false;

  // Data
  List<TransactionItem> items = [];
  int totalAmount = 0;

  bool loading = false;
  String? error;

  /// Draft bon yang masih tertahan di memori dan akan dipakai ulang bila
  /// pengguna membuka "Buat Bon" lagi.
  bool get hasDraft => transactionId != null && headerSaved;

  /// Buang draft yang tertahan di memori supaya "Buat Bon" benar-benar
  /// memulai bon baru. Tanpa ini, screen akan memakai kembali
  /// (customerId/transactionDate/items) dari bon terakhir yang dibuat.
  void startNew() {
    reset();
    notifyListeners();
  }

  Future<void> loadReference() async {
    // customers & products dimuat oleh screen masing-masing (dibutuhkan sebelum header).
  }

  Future<String?> saveHeader() async {
    if (customerId == null || transactionDate.isEmpty) {
      return 'Pelanggan dan tanggal wajib diisi.';
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (transactionId == null) {
        final t = await _repo.store(
          customerId: customerId!,
          transactionDate: transactionDate,
          notes: notes.isEmpty ? null : notes,
        );
        transactionId = t.id;
        transactionNumber = t.transactionNumber;
      } else {
        final t = await _repo.update(
          transactionId!,
          customerId: customerId,
          transactionDate: transactionDate,
          notes: notes.isEmpty ? null : notes,
        );
        transactionId = t.id;
        transactionNumber = t.transactionNumber;
      }
      headerSaved = true;
      await refreshItems();
      return null;
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Gagal menyimpan bon.');
      return error;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadExisting(int id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final t = await _repo.show(id);
      transactionId = t.id;
      transactionNumber = t.transactionNumber;
      customerId = t.customerId;
      customerName = t.customer?.name ?? '';
      transactionDate = t.transactionDate;
      notes = t.notes ?? '';
      paymentStatus = t.paymentStatus;
      items = List.of(t.items);
      _itemOrder = []; // bon baru dimuat → mulai dari urutan server (by id)
      totalAmount = t.totalAmount;
      headerSaved = true;
    } catch (e) {
      error = ApiClient.errorMessage(e, fallback: 'Gagal memuat draft bon.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Ubah status pembayaran. Mengembalikan pesan error bila gagal (null = sukses).
  Future<String?> updatePaymentStatus(String status) async {
    final previous = paymentStatus;
    paymentStatus = status;
    notifyListeners();
    final id = transactionId;
    if (id == null) return null; // header belum ada → cukup state lokal
    try {
      await _repo.update(id, paymentStatus: status);
      return null;
    } catch (e) {
      paymentStatus = previous; // rollback agar UI tidak menyesatkan
      notifyListeners();
      return ApiClient.errorMessage(
        e,
        fallback: 'Gagal mengubah status pembayaran.',
      );
    }
  }

  Future<String?> addItem({
    int? productId,
    required String productName,
    String? description,
    required int quantity,
    String unit = 'pcs',
    required int unitPrice,
    int? subtotal,
  }) async {
    final id = transactionId;
    if (id == null) return 'Header belum disimpan.';
    try {
      await _repo.addItem(
        id,
        productId: productId,
        productName: productName,
        description: description,
        quantity: quantity,
        unit: unit,
        unitPrice: unitPrice,
        subtotal: subtotal,
      );
      await refreshItems();
      return null;
    } catch (e) {
      return ApiClient.errorMessage(e, fallback: 'Gagal menyimpan item.');
    }
  }

  Future<String?> updateItem(
    int itemId, {
    int? productId,
    required String productName,
    String? description,
    required int quantity,
    String? unit,
    required int unitPrice,
    int? subtotal,
  }) async {
    try {
      await _repo.updateItem(
        itemId,
        productId: productId,
        productName: productName,
        description: description,
        quantity: quantity,
        unit: unit,
        unitPrice: unitPrice,
        subtotal: subtotal,
      );
      await refreshItems();
      return null;
    } catch (e) {
      return ApiClient.errorMessage(e, fallback: 'Gagal mengubah item.');
    }
  }

  Future<String?> removeItem(int itemId) async {
    try {
      await _repo.deleteItem(itemId);
      await refreshItems();
      return null;
    } catch (e) {
      return ApiClient.errorMessage(e, fallback: 'Gagal menghapus item.');
    }
  }

  /// Penanda urutan refresh — respons lama dibuang agar tidak menimpa
  /// state yang lebih baru saat beberapa request berjalan bersamaan.
  int _refreshSeq = 0;

  /// Muat ulang items + total dari backend (server = source of truth,
  /// karena `total_amount` dihitung oleh model Transaction di Laravel).
  Future<void> refreshItems() async {
    final id = transactionId;
    if (id == null) return;
    final seq = ++_refreshSeq;
    try {
      final t = await _repo.show(id);
      // Buang respons kedaluwarsa: draft sudah berganti atau ada refresh
      // yang lebih baru. Mencegah item hilang saat input cepat berturut-turut.
      if (seq != _refreshSeq || id != transactionId) return;
      // Reconcile order saat refresh:
      // - jika _itemOrder kosong (baru dimuat/direset), pakai urutan server.
      // - jika _itemOrder ada, buang id yang tidak lagi ada di server;
      //   item baru dari server ditaruh di akhir urutan manual.
      if (_itemOrder.isEmpty) {
        _itemOrder = t.items.map((e) => e.id).toList();
      } else {
        final newOrder = <int>[];
        final currentItemIds = t.items.map((e) => e.id).toSet();
        for (final id in _itemOrder) {
          if (currentItemIds.contains(id)) {
            newOrder.add(id);
            currentItemIds.remove(id); // hindari duplikat
          }
        }
        // Tambahkan item baru yang belum punya urutan manual (dari server),
        // letakkan di akhir sesuai urutan id default mereka.
        newOrder.addAll(currentItemIds.toList());
        _itemOrder = newOrder;
      }
      items = List.of(t.items); // selalu simpan raw items dari server
      totalAmount = t.totalAmount;
      notifyListeners();
    } catch (_) {}
  }

  // ---- Reorder item (drag & drop) --------------------------------------
  //
  /// Urutan item pilihan pengguna, berisi id item dari atas ke bawah.
  ///
  /// Backend TIDAK menyimpan urutan: `transaction_items` tidak punya kolom
  /// order/sort, dan `GET /transactions/{id}` selalu mengembalikan item
  /// berdasarkan `id`. Karena itu urutan ini hidup di memori saja — cukup
  /// untuk alur create/edit → preview → print, dan TIDAK diklaim persistent
  /// setelah data diambil ulang dari server. Tidak ada DB/migration/API baru.
  List<int> _itemOrder = [];

  /// Urutan manual saat ini (salinan, aman untuk dibaca konsumen).
  List<int> get itemOrderIds => List.unmodifiable(_itemOrder);

  /// Item sesuai urutan pilihan pengguna.
  ///
  /// Id yang hilang (item dihapus) dibuang; item baru/asing (belum punya
  /// urutan manual) diletakkan di akhir sesuai urutan server, supaya list
  /// tidak pernah kembali ke urutan `id` selama sesi berjalan.
  List<TransactionItem> get orderedItems {
    if (_itemOrder.isEmpty) return items;
    final byId = <int, TransactionItem>{for (final it in items) it.id: it};
    final out = <TransactionItem>[];
    for (final id in _itemOrder) {
      final it = byId.remove(id);
      if (it != null) out.add(it);
    }
    out.addAll(byId.values);
    return out;
  }

  /// Terapkan urutan manual (id item dari atas ke bawah).
  void setItemOrder(List<int> ids) {
    _itemOrder = List.of(ids);
    notifyListeners();
  }

  /// Pindahkan item dari [oldIndex] ke [newIndex] pada daftar yang tampil.
  /// Dipanggil `ReorderableListView.onReorder`.
  void moveItem(int oldIndex, int newIndex) {
    final list = List.of(orderedItems);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    // ReorderableListView memberi newIndex setelah item asal dilepas.
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= list.length) target = list.length - 1;
    if (target == oldIndex) return;
    final moved = list.removeAt(oldIndex);
    list.insert(target, moved);
    _itemOrder = list.map((it) => it.id).toList();
    notifyListeners();
  }

  /// Buang urutan manual (dipakai saat draft direset / bon dimuat ulang).
  void clearItemOrder() {
    if (_itemOrder.isEmpty) return;
    _itemOrder = [];
    notifyListeners();
  }

  Future<String?> finalizeBon() async {
    final id = transactionId;
    if (id == null) return null;
    try {
      await _repo.update(id, status: 'completed');
      return null;
    } catch (e) {
      return ApiClient.errorMessage(e, fallback: 'Gagal menyelesaikan bon.');
    }
  }

  /// Reset semua state (untuk buat bon baru setelah selesai).
  void reset() {
    _refreshSeq++;
    transactionId = null;
    transactionNumber = '';
    customerId = null;
    customerName = '';
    transactionDate = '';
    notes = '';
    paymentStatus = 'unpaid';
    headerSaved = false;
    items = [];
    _itemOrder = [];
    totalAmount = 0;
    loading = false;
    error = null;
  }
}
