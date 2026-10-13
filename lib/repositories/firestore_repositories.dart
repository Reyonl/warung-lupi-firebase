import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../models/models.dart';
import '../providers/repositories.dart';
import '../services/cigarette_classifier.dart';
import '../services/customer_rules_service.dart';
import '../services/dashboard_aggregate_service.dart';
import '../services/expense_sync_service.dart';
import '../services/invoice_number_service.dart';

/// Helper untuk referensi Firestore dengan fallback ke [FirebaseFirestore.instance].
FirebaseFirestore _db(FirebaseFirestore? custom) =>
    custom ?? FirebaseFirestore.instance;

/// Representasi dokumen ringan hasil gabungan Firestore (server/cache) & overlay offline.
class _DocEntry {
  final String id;
  final Map<String, dynamic> data;
  const _DocEntry(this.id, this.data);
}

/// Penyimpanan overlay di memori untuk menjamin semua dokumen yang dibuat,
/// diubah, atau dihapus saat offline langsung terlihat di seluruh layar (0ms)
/// sembari Firestore SDK menyinkronkan antrean SQLite ke server di background.
class _OfflineOverlay {
  /// colName -> (docId -> data)
  static final Map<String, Map<String, Map<String, dynamic>>> cols = {};

  /// colName -> (docId -> perubahan lokal yang belum tentu ter-commit ke server)
  static final Map<String, Map<String, Map<String, dynamic>>> dirtyCols = {};

  /// colName -> set of deleted docIds
  static final Map<String, Set<String>> deleted = {};

  /// txDocId -> (itemDocId -> itemData)
  static final Map<String, Map<String, Map<String, dynamic>>> txItems = {};

  /// txDocId -> (itemDocId -> perubahan item lokal)
  static final Map<String, Map<String, Map<String, dynamic>>> dirtyTxItems = {};

  /// txDocId -> set of deleted itemDocIds
  static final Map<String, Set<String>> deletedTxItems = {};

  static Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    final clean = Map<String, dynamic>.from(data);
    clean.removeWhere((_, v) => v is FieldValue);
    return clean;
  }

  static void putDoc(String col, String docId, Map<String, dynamic> data) {
    final clean = _sanitize(data);
    final map = cols.putIfAbsent(col, () => {});
    map[docId] = {...?map[docId], ...clean};
    final dirty = dirtyCols.putIfAbsent(col, () => {});
    dirty[docId] = {...?dirty[docId], ...clean};
    deleted[col]?.remove(docId);
  }

  static void cacheDocFromFirestore(
    String col,
    String docId,
    Map<String, dynamic> data,
  ) {
    if (deleted[col]?.contains(docId) ?? false) return;
    final clean = _sanitize(data);
    final localDirty = dirtyCols[col]?[docId];
    final map = cols.putIfAbsent(col, () => {});
    map[docId] = localDirty != null ? {...clean, ...localDirty} : clean;
  }

  static void deleteDoc(String col, String docId) {
    cols[col]?.remove(docId);
    dirtyCols[col]?.remove(docId);
    deleted.putIfAbsent(col, () => {}).add(docId);
  }

  static void putItem(
    String txDocId,
    String itemDocId,
    Map<String, dynamic> data,
  ) {
    final clean = _sanitize(data);
    final map = txItems.putIfAbsent(txDocId, () => {});
    map[itemDocId] = {...?map[itemDocId], ...clean};
    final dirty = dirtyTxItems.putIfAbsent(txDocId, () => {});
    dirty[itemDocId] = {...?dirty[itemDocId], ...clean};
    deletedTxItems[txDocId]?.remove(itemDocId);
  }

  static void cacheItemFromFirestore(
    String txDocId,
    String itemDocId,
    Map<String, dynamic> data,
  ) {
    if (deletedTxItems[txDocId]?.contains(itemDocId) ?? false) return;
    final clean = _sanitize(data);
    final localDirty = dirtyTxItems[txDocId]?[itemDocId];
    final map = txItems.putIfAbsent(txDocId, () => {});
    map[itemDocId] = localDirty != null ? {...clean, ...localDirty} : clean;
  }

  static void deleteItem(String txDocId, String itemDocId) {
    txItems[txDocId]?.remove(itemDocId);
    dirtyTxItems[txDocId]?.remove(itemDocId);
    deletedTxItems.putIfAbsent(txDocId, () => {}).add(itemDocId);
  }
}

/// Penanda adaptif apakah koneksi ke server Firestore baru saja gagal/timeout.
/// Selama offline, operasi baca langsung mengambil dari cache lokal (0ms network wait)
/// dan operasi tulis tidak menunggu ACK server yang tidak akan datang saat offline.
DateTime? _lastOfflineAt;

bool get _isLikelyOffline {
  final last = _lastOfflineAt;
  if (last == null) return false;
  return DateTime.now().difference(last) < const Duration(seconds: 15);
}

void _markOffline() {
  _lastOfflineAt = DateTime.now();
}

void _markOnline() {
  _lastOfflineAt = null;
}

/// Helper eksekusi query aman saat offline/online.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getQueryDocsSafe(
  Query<Map<String, dynamic>> query, {
  bool preferCache = false,
}) async {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> cachedDocs = const [];
  try {
    final cachedSnap = await query.get(const GetOptions(source: Source.cache));
    cachedDocs = cachedSnap.docs;
  } catch (_) {}

  if (preferCache) {
    if (cachedDocs.isNotEmpty || _isLikelyOffline) return cachedDocs;
  } else if (_isLikelyOffline) {
    return cachedDocs;
  }

  final waitMs = cachedDocs.isEmpty ? 2500 : 1200;
  try {
    final snap = await query.get().timeout(Duration(milliseconds: waitMs));
    _markOnline();
    return snap.docs;
  } catch (_) {
    _markOffline();
    return cachedDocs;
  }
}

/// Helper penulisan dokumen (`set`) yang tidak macet saat offline.
/// Di Firestore SDK, `ref.set()` langsung menulis ke cache SQLite lokal secara instan,
/// tetapi Future-nya baru selesai ketika server mengirim ACK (yang menggantung selamanya saat offline).
Future<void> _setDocSafe(
  DocumentReference<Map<String, dynamic>> ref,
  Map<String, dynamic> data, {
  String? colName,
  SetOptions? options,
}) async {
  final cName = colName ?? ref.parent.id;
  _OfflineOverlay.putDoc(cName, ref.id, data);
  final waitMs = _isLikelyOffline ? 60 : 300;
  try {
    final future = options != null ? ref.set(data, options) : ref.set(data);
    await future.timeout(Duration(milliseconds: waitMs));
    if (!_isLikelyOffline) _markOnline();
  } catch (_) {
    _markOffline();
  }
}

/// Helper update dokumen (`update`) yang tidak macet saat offline.
Future<void> _updateDocSafe(
  DocumentReference<Map<String, dynamic>> ref,
  Map<String, dynamic> data, {
  String? colName,
}) async {
  final cName = colName ?? ref.parent.id;
  _OfflineOverlay.putDoc(cName, ref.id, data);
  final waitMs = _isLikelyOffline ? 60 : 300;
  try {
    await ref.update(data).timeout(Duration(milliseconds: waitMs));
    if (!_isLikelyOffline) _markOnline();
  } catch (_) {
    _markOffline();
    // Jika dokumen baru dibuat secara lokal atau update gagal, pastikan set merge tertulis ke cache
    try {
      await ref
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(milliseconds: 60));
    } catch (_) {}
  }
}

/// Helper hapus dokumen (`delete`) yang tidak macet saat offline.
Future<void> _deleteDocSafe(
  DocumentReference<Map<String, dynamic>> ref, {
  String? colName,
}) async {
  final cName = colName ?? ref.parent.id;
  _OfflineOverlay.deleteDoc(cName, ref.id);
  final waitMs = _isLikelyOffline ? 60 : 300;
  try {
    await ref.delete().timeout(Duration(milliseconds: waitMs));
    if (!_isLikelyOffline) _markOnline();
  } catch (_) {
    _markOffline();
  }
}

/// Membaca seluruh dokumen koleksi (menggabungkan Firestore server/cache + `_OfflineOverlay`).
Future<List<_DocEntry>> _getColEntries(
  CollectionReference<Map<String, dynamic>> col, {
  bool preferCache = false,
}) async {
  final colName = col.id;
  final docs = await _getQueryDocsSafe(col, preferCache: preferCache);
  for (final d in docs) {
    _OfflineOverlay.cacheDocFromFirestore(colName, d.id, d.data());
  }

  final map = _OfflineOverlay.cols[colName];
  if (map == null || map.isEmpty) return [];
  final del = _OfflineOverlay.deleted[colName] ?? const <String>{};

  return map.entries
      .where((e) => !del.contains(e.key))
      .map((e) => _DocEntry(e.key, e.value))
      .toList();
}

/// Mencari dokumen berdasarkan integer [id] secara instan dari `_OfflineOverlay` atau `Source.cache`,
/// lalu fallback ke server jika belum ada.
Future<_DocEntry?> _findEntryById(
  CollectionReference<Map<String, dynamic>> col,
  int id, {
  required String prefix,
}) async {
  final colName = col.id;
  final del = _OfflineOverlay.deleted[colName] ?? const <String>{};
  final candidates = ['${prefix}_$id', 'legacy_$id', '$id'];

  // 1. Cek langsung di _OfflineOverlay (0ms)
  final memMap = _OfflineOverlay.cols[colName];
  if (memMap != null) {
    for (final docId in candidates) {
      if (!del.contains(docId) && memMap.containsKey(docId)) {
        return _DocEntry(docId, memMap[docId]!);
      }
    }
    for (final e in memMap.entries) {
      if (!del.contains(e.key) && parseEntityId(e.key, e.value) == id) {
        return _DocEntry(e.key, e.value);
      }
    }
  }

  // 2. Cek langsung di Firestore Source.cache (1ms)
  for (final docId in candidates) {
    if (del.contains(docId)) continue;
    try {
      final snap = await col.doc(docId).get(const GetOptions(source: Source.cache));
      if (snap.exists && snap.data() != null) {
        _OfflineOverlay.cacheDocFromFirestore(colName, snap.id, snap.data()!);
        return _DocEntry(
          snap.id,
          _OfflineOverlay.cols[colName]?[snap.id] ?? snap.data()!,
        );
      }
    } catch (_) {}
  }

  // 3. Scan koleksi (cache / server)
  final all = await _getColEntries(col);
  for (final entry in all) {
    if (parseEntityId(entry.id, entry.data) == id) {
      return entry;
    }
  }

  // 4. Pencocokan khusus nomor invoice jika mencari transaksi dengan format tanggal+urutan
  if (colName == 'transactions') {
    final idStr = id.toString();
    if (idStr.length > 8) {
      final datePart = idStr.substring(0, 8);
      final seqPart = int.tryParse(idStr.substring(8)) ?? 0;
      final formattedInv = 'INV-$datePart-${seqPart.toString().padLeft(3, '0')}';
      for (final entry in all) {
        if (entry.data['number'] == formattedInv) return entry;
      }
    }
  }

  return null;
}

/// Membaca seluruh item subkoleksi dari sebuah transaksi (`transactions/{txDocId}/items`).
Future<List<_DocEntry>> _getTxItemEntries(
  DocumentReference<Map<String, dynamic>> txRef, {
  bool preferCache = false,
}) async {
  final txDocId = txRef.id;
  final docs = await _getQueryDocsSafe(
    txRef.collection('items'),
    preferCache: preferCache,
  );
  for (final d in docs) {
    _OfflineOverlay.cacheItemFromFirestore(txDocId, d.id, d.data());
  }

  final map = _OfflineOverlay.txItems[txDocId];
  if (map == null || map.isEmpty) return [];
  final del = _OfflineOverlay.deletedTxItems[txDocId] ?? const <String>{};

  return map.entries
      .where((e) => !del.contains(e.key))
      .map((e) => _DocEntry(e.key, e.value))
      .toList();
}

// ==========================================
// 1. FIRESTORE CUSTOMER REPOSITORY
// ==========================================
class FirestoreCustomerRepository implements CustomerRepository {
  final FirebaseFirestore? _customDb;

  FirestoreCustomerRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('customers');

  @override
  Future<List<Customer>> index({String search = '', bool? isActive}) async {
    final entries = await _getColEntries(_col);
    var list = entries.map((e) => Customer.fromDocument(e.id, e.data)).toList();

    if (isActive != null) {
      list = list.where((c) => c.isActive == isActive).toList();
    }

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((c) {
        final n = c.name.toLowerCase();
        final p = c.phone?.toLowerCase() ?? '';
        return n.contains(q) || p.contains(q);
      }).toList();
    }

    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<Customer> store({
    required String name,
    String? phone,
    String? notes,
  }) async {
    final newId = DateTime.now().millisecondsSinceEpoch;
    final docRef = _col.doc('cust_$newId');
    final data = {
      'id': newId,
      'legacyId': newId,
      'name': name.trim(),
      'phone': (phone == null || phone.isEmpty) ? null : phone.trim(),
      'notes': (notes == null || notes.isEmpty) ? null : notes.trim(),
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _setDocSafe(docRef, data, colName: 'customers');
    return Customer.fromDocument(docRef.id, data);
  }

  @override
  Future<Customer> show(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'cust');
    if (entry == null) {
      throw Exception('Pelanggan ID $id tidak ditemukan.');
    }

    final allTx = await _getColEntries(db.collection('transactions'));
    final txCount = allTx
        .where((e) => Transaction.fromDocument(e.id, e.data).customerId == id)
        .length;

    return Customer.fromDocument(
      entry.id,
      entry.data,
      transactionsCount: txCount,
    );
  }

  @override
  Future<Customer> update(
    int id, {
    String? name,
    String? phone,
    String? notes,
    bool? isActive,
  }) async {
    final entry = await _findEntryById(_col, id, prefix: 'cust');
    if (entry == null) {
      throw Exception('Pelanggan ID $id tidak ditemukan.');
    }

    final updateData = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (phone != null) 'phone': (phone.isEmpty) ? null : phone.trim(),
      if (notes != null) 'notes': (notes.isEmpty) ? null : notes.trim(),
      if (isActive != null) 'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _updateDocSafe(_col.doc(entry.id), updateData, colName: 'customers');
    final merged = {...entry.data, ...updateData};
    return Customer.fromDocument(entry.id, merged);
  }

  @override
  Future<void> destroy(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'cust');
    if (entry == null) return;

    // Validasi aturan: pelanggan dengan riwayat bon dilarang dihapus
    final allTx = await _getColEntries(db.collection('transactions'));
    final txCount = allTx
        .where((e) => Transaction.fromDocument(e.id, e.data).customerId == id)
        .length;

    CustomerRulesService.validateCanDelete(
      transactionCount: txCount,
    );

    await _deleteDocSafe(_col.doc(entry.id), colName: 'customers');
  }

  @override
  Future<List<TransactionSummary>> transactions(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'cust');
    if (entry == null) return [];

    final custName = entry.data['name'] as String?;
    final allTx = await _getColEntries(db.collection('transactions'));

    final matching = allTx.where((e) {
      final tx = Transaction.fromDocument(e.id, e.data);
      return tx.customerId == id || e.data['customerId'] == entry.id;
    }).toList();

    matching.sort((a, b) {
      final da = (a.data['date'] ?? a.data['transaction_date'] ?? '').toString();
      final dbStr = (b.data['date'] ?? b.data['transaction_date'] ?? '').toString();
      return dbStr.compareTo(da);
    });

    return matching.map((e) {
      return TransactionSummary.fromDocument(
        e.id,
        e.data,
        customerName: custName,
      );
    }).toList();
  }
}

// ==========================================
// 2. FIRESTORE CATEGORY REPOSITORY
// ==========================================
class FirestoreCategoryRepository implements CategoryRepository {
  final FirebaseFirestore? _customDb;

  FirestoreCategoryRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('categories');

  @override
  Future<List<Category>> index() async {
    final entries = await _getColEntries(_col);
    final list = entries.map((e) => Category.fromDocument(e.id, e.data)).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<Category> store(String name) async {
    final newId = DateTime.now().millisecondsSinceEpoch;
    final docRef = _col.doc('cat_$newId');
    final data = {
      'id': newId,
      'legacyId': newId,
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _setDocSafe(docRef, data, colName: 'categories');
    return Category.fromDocument(docRef.id, data);
  }

  @override
  Future<Category> update(int id, String name) async {
    final entry = await _findEntryById(_col, id, prefix: 'cat');
    if (entry == null) throw Exception('Kategori ID $id tidak ditemukan.');

    final updateData = {
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _updateDocSafe(_col.doc(entry.id), updateData, colName: 'categories');
    final merged = {...entry.data, ...updateData};
    return Category.fromDocument(entry.id, merged);
  }

  @override
  Future<void> destroy(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'cat');
    if (entry == null) return;
    await _deleteDocSafe(_col.doc(entry.id), colName: 'categories');
  }
}

// ==========================================
// 3. FIRESTORE PRODUCT REPOSITORY
// ==========================================
class FirestoreProductRepository implements ProductRepository {
  final FirebaseFirestore? _customDb;

  FirestoreProductRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('products');

  @override
  Future<List<Product>> index({
    String search = '',
    int? categoryId,
    bool? isActive,
  }) async {
    final entries = await _getColEntries(_col);
    var list = entries.map((e) => Product.fromDocument(e.id, e.data)).toList();

    if (isActive != null) {
      list = list.where((p) => p.isActive == isActive).toList();
    }
    if (categoryId != null) {
      list = list.where((p) => p.categoryId == categoryId).toList();
    }

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<Product> store({
    required int categoryId,
    required String name,
    required int defaultPrice,
    required String unit,
    bool isActive = true,
  }) async {
    final newId = DateTime.now().millisecondsSinceEpoch;
    final docRef = _col.doc('prod_$newId');
    final data = {
      'id': newId,
      'legacyId': newId,
      'categoryId': 'legacy_$categoryId',
      'name': name.trim(),
      'defaultPrice': defaultPrice,
      'unit': unit.trim(),
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _setDocSafe(docRef, data, colName: 'products');
    return Product.fromDocument(docRef.id, data);
  }

  @override
  Future<Product> update(
    int id, {
    int? categoryId,
    String? name,
    int? defaultPrice,
    String? unit,
    bool? isActive,
  }) async {
    final entry = await _findEntryById(_col, id, prefix: 'prod');
    if (entry == null) throw Exception('Produk ID $id tidak ditemukan.');

    final data = <String, dynamic>{
      if (categoryId != null) 'categoryId': 'legacy_$categoryId',
      if (name != null) 'name': name.trim(),
      if (defaultPrice != null) 'defaultPrice': defaultPrice,
      if (unit != null) 'unit': unit.trim(),
      if (isActive != null) 'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _updateDocSafe(_col.doc(entry.id), data, colName: 'products');
    final merged = {...entry.data, ...data};
    return Product.fromDocument(entry.id, merged);
  }

  @override
  Future<void> destroy(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'prod');
    if (entry == null) return;
    await _deleteDocSafe(_col.doc(entry.id), colName: 'products');
  }
}

// ==========================================
// 4. FIRESTORE TRANSACTION REPOSITORY
// ==========================================
class FirestoreTransactionRepository implements TransactionRepository {
  final FirebaseFirestore? _customDb;

  FirestoreTransactionRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('transactions');

  @override
  Future<Paginated<Transaction>> index({
    String search = '',
    String? dateFrom,
    String? dateTo,
    String? status,
    int? customerId,
    int page = 1,
    int perPage = 20,
  }) async {
    final entries = await _getColEntries(_col);
    var list = entries.map((e) => Transaction.fromDocument(e.id, e.data)).toList();

    if (customerId != null) {
      list = list.where((t) => t.customerId == customerId).toList();
    }
    if (status != null && status.isNotEmpty) {
      list = list.where((t) => t.status == status).toList();
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      list = list.where((t) => t.transactionDate.compareTo(dateFrom) >= 0).toList();
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      list = list.where((t) => t.transactionDate.compareTo(dateTo) <= 0).toList();
    }

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((t) {
        return t.transactionNumber.toLowerCase().contains(q) ||
            (t.customer?.name.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    list.sort((a, b) {
      final cmp = b.transactionDate.compareTo(a.transactionDate);
      if (cmp != 0) return cmp;
      return b.id.compareTo(a.id);
    });

    final total = list.length;
    final startIndex = (page - 1) * perPage;
    final paginatedItems = list.skip(startIndex).take(perPage).toList();

    return Paginated<Transaction>(
      data: paginatedItems,
      currentPage: page,
      lastPage: (total / perPage).ceil().clamp(1, 999999),
      total: total,
    );
  }

  @override
  Future<Transaction> store({
    required int customerId,
    required String transactionDate,
    String? notes,
  }) async {
    final newId = DateTime.now().millisecondsSinceEpoch;
    final docRef = _col.doc('tx_$newId');

    // Penomoran bon instan (online & offline) tanpa db.runTransaction yang memblokir antrean saat offline
    int nextSeq = 1;
    try {
      final allTx = await _getColEntries(_col, preferCache: true);
      int sameDayCount = 0;
      for (final e in allTx) {
        final dStr = (e.data['date'] ?? e.data['transaction_date'] ?? '').toString();
        if (dStr.startsWith(transactionDate)) {
          sameDayCount++;
          final numStr = (e.data['number'] ?? e.data['transaction_number'] ?? '').toString();
          final parts = numStr.split('-');
          if (parts.length >= 3) {
            final parsed = int.tryParse(parts.last) ?? 0;
            if (parsed >= nextSeq) nextSeq = parsed + 1;
          }
        }
      }
      if (sameDayCount >= nextSeq) {
        nextSeq = sameDayCount + 1;
      }
    } catch (_) {}

    final invoiceNumber = InvoiceNumberService.formatOfficialNumber(
      transactionDate,
      nextSeq,
    );

    // Sinkronkan counter ke Firestore di background (non-blocking)
    final counterRef = db
        .collection('counters')
        .doc(InvoiceNumberService.counterDocId(transactionDate));
    _setDocSafe(
      counterRef,
      {'currentSequence': nextSeq},
      colName: 'counters',
      options: SetOptions(merge: true),
    ).ignore();

    // Ambil nama customer untuk denormalisasi
    String? customerName;
    try {
      final cEntry = await _findEntryById(
        db.collection('customers'),
        customerId,
        prefix: 'cust',
      );
      if (cEntry != null) {
        customerName = cEntry.data['name'] as String?;
      }
    } catch (_) {}

    final data = {
      'id': newId,
      'legacyId': newId,
      'customerId': 'legacy_$customerId',
      'customerName': customerName,
      'number': invoiceNumber,
      'date': transactionDate,
      'totalAmount': 0,
      'status': 'draft',
      'paymentStatus': 'unpaid',
      'type': 'sale',
      'notes': (notes == null || notes.isEmpty) ? null : notes,
      'itemCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _setDocSafe(docRef, data, colName: 'transactions');
    return Transaction.fromDocument(docRef.id, data);
  }

  @override
  Future<Transaction> show(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'tx');
    if (entry == null) throw Exception('Transaksi ID $id tidak ditemukan.');

    final itemsEntries = await _getTxItemEntries(_col.doc(entry.id));
    final items = itemsEntries
        .map((e) => TransactionItem.fromDocument(e.id, e.data, transactionId: id))
        .toList();

    return Transaction.fromDocument(entry.id, entry.data, items: items);
  }

  @override
  Future<Transaction> update(
    int id, {
    int? customerId,
    String? transactionDate,
    String? status,
    String? paymentStatus,
    String? notes,
  }) async {
    final entry = await _findEntryById(_col, id, prefix: 'tx');
    if (entry == null) throw Exception('Transaksi ID $id tidak ditemukan.');

    String? customerName;
    if (customerId != null) {
      final cEntry = await _findEntryById(
        db.collection('customers'),
        customerId,
        prefix: 'cust',
      );
      customerName = cEntry?.data['name'] as String?;
    }

    final data = <String, dynamic>{
      if (customerId != null) 'customerId': 'legacy_$customerId',
      if (customerName != null) 'customerName': customerName,
      if (transactionDate != null) 'date': transactionDate,
      if (status != null) 'status': status,
      if (paymentStatus != null) 'paymentStatus': paymentStatus,
      if (notes != null) 'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _updateDocSafe(_col.doc(entry.id), data, colName: 'transactions');
    final merged = {...entry.data, ...data};
    return Transaction.fromDocument(entry.id, merged);
  }

  @override
  Future<void> destroy(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'tx');
    if (entry == null) return;

    final txRef = _col.doc(entry.id);
    final items = await _getTxItemEntries(txRef, preferCache: true);
    for (final it in items) {
      _OfflineOverlay.deleteItem(entry.id, it.id);
      await _deleteDocSafe(txRef.collection('items').doc(it.id), colName: 'items');
      final expDocId = ExpenseSyncService.docId(
        transactionId: id.toString(),
        itemId: it.id,
      );
      await _deleteDocSafe(db.collection('expenses').doc(expDocId), colName: 'expenses');
    }

    await _deleteDocSafe(txRef, colName: 'transactions');
  }

  @override
  Future<TransactionItem> addItem(
    int transactionId, {
    int? productId,
    required String productName,
    String? description,
    required int quantity,
    String unit = 'pcs',
    required int unitPrice,
    int? subtotal,
  }) async {
    final entry = await _findEntryById(_col, transactionId, prefix: 'tx');
    if (entry == null) throw Exception('Transaksi ID $transactionId tidak ditemukan.');

    final txRef = _col.doc(entry.id);
    final calcSubtotal = subtotal ?? (quantity * unitPrice);
    final newItemId = DateTime.now().millisecondsSinceEpoch;
    final itemDocId = 'item_$newItemId';
    final itemRef = txRef.collection('items').doc(itemDocId);

    final itemData = {
      'id': newItemId,
      'legacyId': newItemId,
      'productId': productId != null ? 'legacy_$productId' : null,
      'productName': productName,
      'description': (description == null || description.isEmpty) ? null : description,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'subtotal': calcSubtotal,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Simpan ke overlay item terlebih dahulu (0ms) lalu antrekan ke Firestore
    _OfflineOverlay.putItem(entry.id, itemDocId, itemData);
    await _setDocSafe(itemRef, itemData, colName: 'items');

    // Sinkronisasi potongan bon ke expenses (subtotal < 0)
    if (ExpenseSyncService.isExpenseItem(calcSubtotal)) {
      final txDate = entry.data['date']?.toString() ?? '';
      final exp = ExpenseSyncService.generateExpense(
        transactionId: transactionId.toString(),
        itemId: itemDocId,
        transactionDate: txDate,
        productName: productName,
        description: description,
        subtotal: calcSubtotal,
      );
      if (exp != null) {
        await _setDocSafe(
          db.collection('expenses').doc(exp.docId),
          exp.toFirestoreDocument(),
          colName: 'expenses',
        );
      }
    }

    // Hitung ulang total transaksi
    await _recalculateTotal(txRef);

    return TransactionItem.fromDocument(
      itemDocId,
      itemData,
      transactionId: transactionId,
    );
  }

  /// Mencari `(txDocId, _DocEntry)` untuk sebuah `itemId` dari overlay memori, cache, atau collectionGroup.
  Future<(String, _DocEntry)?> _findItemWithParent(int itemId) async {
    // 1. Cari cepat di _OfflineOverlay.txItems (0ms)
    for (final txEntry in _OfflineOverlay.txItems.entries) {
      final txDocId = txEntry.key;
      final del = _OfflineOverlay.deletedTxItems[txDocId] ?? const <String>{};
      final itemMap = txEntry.value;
      final directKey = 'item_$itemId';
      if (!del.contains(directKey) && itemMap.containsKey(directKey)) {
        return (txDocId, _DocEntry(directKey, itemMap[directKey]!));
      }
      for (final it in itemMap.entries) {
        if (!del.contains(it.key) && parseEntityId(it.key, it.value) == itemId) {
          return (txDocId, _DocEntry(it.key, it.value));
        }
      }
    }

    // 2. Fallback via collectionGroup jika belum ada di overlay
    final all = await _getQueryDocsSafe(db.collectionGroup('items').limit(200));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == itemId) {
        final txDocId = d.reference.parent.parent?.id ?? '';
        if (txDocId.isNotEmpty) {
          _OfflineOverlay.cacheItemFromFirestore(txDocId, d.id, d.data());
          return (txDocId, _DocEntry(d.id, d.data()));
        }
      }
    }
    return null;
  }

  @override
  Future<TransactionItem> updateItem(
    int itemId, {
    int? productId,
    String? productName,
    String? description,
    int? quantity,
    String? unit,
    int? unitPrice,
    int? subtotal,
  }) async {
    final found = await _findItemWithParent(itemId);
    if (found == null) throw Exception('Item ID $itemId tidak ditemukan.');

    final (txDocId, itemEntry) = found;
    final oldData = itemEntry.data;
    final newQty = quantity ?? numFrom(oldData['quantity']);
    final newPrice = unitPrice ?? numFrom(oldData['unitPrice']);
    final newSubtotal = subtotal ?? (newQty * newPrice);

    final data = <String, dynamic>{
      if (productId != null) 'productId': 'legacy_$productId',
      if (productName != null) 'productName': productName,
      if (description != null) 'description': description,
      if (quantity != null) 'quantity': newQty,
      if (unit != null) 'unit': unit,
      if (unitPrice != null) 'unitPrice': newPrice,
      'subtotal': newSubtotal,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final txRef = _col.doc(txDocId);
    final itemRef = txRef.collection('items').doc(itemEntry.id);

    _OfflineOverlay.putItem(txDocId, itemEntry.id, data);
    await _updateDocSafe(itemRef, data, colName: 'items');

    // Update / hapus sinkronisasi expense
    final txData = _OfflineOverlay.cols['transactions']?[txDocId];
    final txId = txDocId.replaceAll(RegExp(r'^(legacy_|tx_)'), '');
    final expDocId = ExpenseSyncService.docId(
      transactionId: txId,
      itemId: itemEntry.id,
    );

    if (ExpenseSyncService.isExpenseItem(newSubtotal)) {
      final exp = ExpenseSyncService.generateExpense(
        transactionId: txId,
        itemId: itemEntry.id,
        transactionDate: txData?['date']?.toString() ?? '',
        productName: productName ?? oldData['productName']?.toString() ?? '',
        description: description ?? oldData['description']?.toString(),
        subtotal: newSubtotal,
      );
      if (exp != null) {
        await _setDocSafe(
          db.collection('expenses').doc(expDocId),
          exp.toFirestoreDocument(),
          colName: 'expenses',
        );
      }
    } else {
      await _deleteDocSafe(
        db.collection('expenses').doc(expDocId),
        colName: 'expenses',
      );
    }

    await _recalculateTotal(txRef);
    final merged = {...oldData, ...data};
    return TransactionItem.fromDocument(itemEntry.id, merged);
  }

  @override
  Future<void> deleteItem(int itemId) async {
    final found = await _findItemWithParent(itemId);
    if (found == null) return;

    final (txDocId, itemEntry) = found;
    final txRef = _col.doc(txDocId);
    final txId = txDocId.replaceAll(RegExp(r'^(legacy_|tx_)'), '');

    final expDocId = ExpenseSyncService.docId(
      transactionId: txId,
      itemId: itemEntry.id,
    );
    await _deleteDocSafe(
      db.collection('expenses').doc(expDocId),
      colName: 'expenses',
    );

    _OfflineOverlay.deleteItem(txDocId, itemEntry.id);
    await _deleteDocSafe(
      txRef.collection('items').doc(itemEntry.id),
      colName: 'items',
    );
    await _recalculateTotal(txRef);
  }

  Future<void> _recalculateTotal(
    DocumentReference<Map<String, dynamic>> txRef,
  ) async {
    final itemsEntries = await _getTxItemEntries(txRef, preferCache: true);
    int total = 0;
    for (final it in itemsEntries) {
      total += numFrom(it.data['subtotal']);
    }
    await _updateDocSafe(
      txRef,
      {
        'totalAmount': total,
        'itemCount': itemsEntries.length,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      colName: 'transactions',
    );
  }
}

// ==========================================
// 5. FIRESTORE EXPENSE REPOSITORY
// ==========================================
class FirestoreExpenseRepository implements ExpenseRepository {
  final FirebaseFirestore? _customDb;

  FirestoreExpenseRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('expenses');

  @override
  Future<ExpensePage> index({
    String? dateFrom,
    String? dateTo,
    String? source,
    String? category,
    String? search,
    int page = 1,
  }) async {
    final entries = await _getColEntries(_col);
    var list = entries.map((e) => Expense.fromDocument(e.id, e.data)).toList();

    if (source != null && source.isNotEmpty) {
      list = list.where((e) => e.source == source).toList();
    }
    if (category != null && category.isNotEmpty) {
      list = list.where((e) => e.category == category).toList();
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      list = list.where((e) => e.expenseDate.compareTo(dateFrom) >= 0).toList();
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      list = list.where((e) => e.expenseDate.compareTo(dateTo) <= 0).toList();
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((e) => e.title.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) {
      final cmp = b.expenseDate.compareTo(a.expenseDate);
      if (cmp != 0) return cmp;
      return b.id.compareTo(a.id);
    });

    int manualSum = 0;
    int bonSum = 0;
    for (final exp in list) {
      if (exp.source == 'bon') {
        bonSum += exp.amount;
      } else {
        manualSum += exp.amount;
      }
    }

    final summary = ExpenseSummary(
      totalAmount: manualSum + bonSum,
      count: list.length,
      manualAmount: manualSum,
      bonAmount: bonSum,
    );

    return ExpensePage(
      data: list,
      summary: summary,
      currentPage: page,
      lastPage: 1,
      total: list.length,
    );
  }

  @override
  Future<Expense> store({
    required String expenseDate,
    required String title,
    String? category,
    required int amount,
    String? notes,
  }) async {
    final newId = DateTime.now().millisecondsSinceEpoch;
    final docRef = _col.doc('exp_$newId');
    final data = {
      'id': newId,
      'legacyId': newId,
      'date': expenseDate,
      'title': title.trim(),
      'category': (category == null || category.trim().isEmpty) ? null : category.trim(),
      'amount': amount.abs(),
      'source': 'manual',
      'transactionId': null,
      'syncKey': null,
      'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _setDocSafe(docRef, data, colName: 'expenses');
    return Expense.fromDocument(docRef.id, data);
  }

  @override
  Future<Expense> update(
    int id, {
    String? expenseDate,
    String? title,
    String? category,
    int? amount,
    String? notes,
  }) async {
    final entry = await _findEntryById(_col, id, prefix: 'exp');
    if (entry == null) throw Exception('Pengeluaran ID $id tidak ditemukan.');

    if (entry.data['source'] == 'bon') {
      throw Exception('Pengeluaran dari bon tidak dapat diedit langsung.');
    }

    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (expenseDate != null) data['date'] = expenseDate;
    if (title != null) data['title'] = title.trim();
    if (category != null) {
      data['category'] = category.trim().isEmpty ? null : category.trim();
    }
    if (amount != null) data['amount'] = amount.abs();
    if (notes != null) {
      data['notes'] = notes.trim().isEmpty ? null : notes.trim();
    }

    await _updateDocSafe(_col.doc(entry.id), data, colName: 'expenses');
    final merged = {...entry.data, ...data};
    return Expense.fromDocument(entry.id, merged);
  }

  @override
  Future<void> destroy(int id) async {
    final entry = await _findEntryById(_col, id, prefix: 'exp');
    if (entry == null) return;

    if (entry.data['source'] == 'bon') {
      throw Exception('Hapus item di bon terkait.');
    }

    await _deleteDocSafe(_col.doc(entry.id), colName: 'expenses');
  }
}

// ==========================================
// 6. FIRESTORE DASHBOARD REPOSITORY
// ==========================================
class FirestoreDashboardRepository implements DashboardRepository {
  final FirebaseFirestore? _customDb;

  FirestoreDashboardRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  @override
  Future<DashboardData> index() async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Muat pelanggan terlebih dahulu (memanaskan koneksi gRPC atau mendeteksi offline dalam 1 langkah)
    final custEntries = await _getColEntries(db.collection('customers'));
    final activeCustCount = custEntries
        .where((e) => Customer.fromDocument(e.id, e.data).isActive)
        .length;

    // Pre-warm cache produk & kategori di background agar Buat Bon siap dipakai saat offline
    _getColEntries(db.collection('categories')).ignore();
    _getColEntries(db.collection('products')).ignore();

    final allTxEntries = await _getColEntries(db.collection('transactions'));
    final allExpEntries = await _getColEntries(db.collection('expenses'));

    // Urutkan 10 transaksi terbaru
    final sortedTx = List<_DocEntry>.from(allTxEntries)
      ..sort((a, b) {
        final da = (a.data['date'] ?? a.data['transaction_date'] ?? '').toString();
        final dbStr = (b.data['date'] ?? b.data['transaction_date'] ?? '').toString();
        return dbStr.compareTo(da);
      });

    final recent = sortedTx.take(10).map((e) {
      return TransactionSummary.fromDocument(e.id, e.data);
    }).toList();

    final stats = DashboardAggregateService.computeDashboardStats(
      todayDateStr: todayStr,
      allTransactions: allTxEntries.map((e) => e.data).toList(),
      allExpenses: allExpEntries.map((e) => e.data).toList(),
      activeCustomersCount: activeCustCount,
    );

    return DashboardData(
      bonHariIni: stats.bonHariIni,
      totalHariIni: stats.totalHariIni,
      lunasHariIni: stats.lunasHariIni,
      lunasTotal: stats.lunasTotal,
      masihHutang: stats.masihHutang,
      pengeluaranHariIni: stats.pengeluaranHariIni,
      pengeluaranTotal: stats.pengeluaranTotal,
      totalPelanggan: stats.totalPelanggan,
      recent: recent,
    );
  }
}

// ==========================================
// 7. FIRESTORE CIGARETTE REPORT REPOSITORY
// ==========================================
class FirestoreCigaretteReportRepository implements CigaretteReportRepository {
  final FirebaseFirestore? _customDb;

  FirestoreCigaretteReportRepository([this._customDb]);

  FirebaseFirestore get db => _db(_customDb);

  @override
  Future<CigaretteReport> report({
    String? dateFrom,
    String? dateTo,
    String? product,
    String? search,
    int page = 1,
  }) async {
    final allTx = await _getColEntries(db.collection('transactions'));
    final completedTx = allTx.where((e) => e.data['status'] == 'completed');

    final txList = <Map<String, dynamic>>[];
    for (final entry in completedTx) {
      final txData = Map<String, dynamic>.from(entry.data);
      final itemsEntries = await _getTxItemEntries(
        db.collection('transactions').doc(entry.id),
      );
      txData['items'] = itemsEntries.map((e) => e.data).toList();
      txList.add(txData);
    }

    final res = CigaretteClassifier.generateReport(
      txList,
      dateFrom: dateFrom,
      dateTo: dateTo,
      productFilter: product,
      search: search,
    );

    return CigaretteReport.fromJson(res.toJson());
  }

  @override
  Future<BonCigaretteSummary> bonSummary(int transactionId) async {
    final entry = await _findEntryById(
      db.collection('transactions'),
      transactionId,
      prefix: 'tx',
    );
    if (entry == null) {
      return BonCigaretteSummary(items: [], totalQuantity: 0, totalAmount: 0);
    }

    final itemsEntries = await _getTxItemEntries(
      db.collection('transactions').doc(entry.id),
      preferCache: true,
    );
    int qty = 0;
    int amount = 0;
    final items = <CigaretteItemRow>[];

    for (final doc in itemsEntries) {
      final d = doc.data;
      final pName = (d['productName'] ?? d['product_name'] ?? '') as String;
      final desc = d['description'] as String?;
      final q = numFrom(d['quantity']);
      final p = numFrom(d['unitPrice']);
      final sub = numFrom(d['subtotal']);

      if (CigaretteClassifier.isCigarette(productName: pName, description: desc)) {
        qty += q;
        amount += sub;
        items.add(CigaretteItemRow(
          productName: pName,
          totalQuantity: q,
          totalSales: sub,
          unitPrice: p,
        ));
      }
    }

    return BonCigaretteSummary(
      items: items,
      totalQuantity: qty,
      totalAmount: amount,
    );
  }
}

// ==========================================
// 8. FIRESTORE BACKUP SERVICE (EXPORT JSON)
// ==========================================
class FirestoreBackupService {
  FirestoreBackupService._();

  static dynamic _toJsonSafe(dynamic v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is FieldValue) return null;
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (e.value is! FieldValue) e.key.toString(): _toJsonSafe(e.value),
      };
    }
    if (v is Iterable) {
      return v.where((x) => x is! FieldValue).map(_toJsonSafe).toList();
    }
    return v.toString();
  }

  /// Mengekspor seluruh koleksi Firestore (termasuk cache/overlay offline) ke Map siap-JSON.
  static Future<Map<String, dynamic>> exportAllData([
    FirebaseFirestore? customDb,
  ]) async {
    final db = _db(customDb);

    final customers = await _getColEntries(db.collection('customers'));
    final categories = await _getColEntries(db.collection('categories'));
    final products = await _getColEntries(db.collection('products'));
    final transactions = await _getColEntries(db.collection('transactions'));
    final expenses = await _getColEntries(db.collection('expenses'));
    final counters = await _getColEntries(db.collection('counters'));

    final txList = <Map<String, dynamic>>[];
    for (final tx in transactions) {
      final items = await _getTxItemEntries(
        db.collection('transactions').doc(tx.id),
        preferCache: true,
      );
      txList.add({
        '_docId': tx.id,
        ...(_toJsonSafe(tx.data) as Map<String, dynamic>),
        'items': items
            .map(
              (it) => {
                '_docId': it.id,
                ...(_toJsonSafe(it.data) as Map<String, dynamic>),
              },
            )
            .toList(),
      });
    }

    List<Map<String, dynamic>> mapEntries(List<_DocEntry> entries) {
      return entries
          .map(
            (e) => {
              '_docId': e.id,
              ...(_toJsonSafe(e.data) as Map<String, dynamic>),
            },
          )
          .toList();
    }

    return {
      'app': 'Warung Lupi',
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': {
        'customers': customers.length,
        'categories': categories.length,
        'products': products.length,
        'transactions': txList.length,
        'expenses': expenses.length,
      },
      'data': {
        'customers': mapEntries(customers),
        'categories': mapEntries(categories),
        'products': mapEntries(products),
        'transactions': txList,
        'expenses': mapEntries(expenses),
        'counters': mapEntries(counters),
      },
    };
  }
}

