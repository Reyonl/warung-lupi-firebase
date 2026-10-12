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

/// Helper pembacaan dokumen aman saat offline/online.
/// Firestore melempar exception saat offline jika dokumen belum ada di cache lokal.
Future<DocumentSnapshot<Map<String, dynamic>>?> _getDocSafe(
  DocumentReference<Map<String, dynamic>> ref,
) async {
  try {
    return await ref.get();
  } catch (_) {
    try {
      return await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return null;
    }
  }
}

/// Helper eksekusi query aman saat offline/online.
/// Mengembalikan list docs dari cache atau server, atau list kosong jika gagal / offline tanpa data.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getQueryDocsSafe(
  Query<Map<String, dynamic>> query,
) async {
  try {
    final snap = await query.get();
    return snap.docs;
  } catch (_) {
    try {
      final snap = await query.get(const GetOptions(source: Source.cache));
      return snap.docs;
    } catch (_) {
      return [];
    }
  }
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
    Query<Map<String, dynamic>> query = _col;
    if (isActive != null) {
      query = query.where('isActive', isEqualTo: isActive);
    }

    final docs = await _getQueryDocsSafe(query);
    var list = docs.map((d) => Customer.fromDocument(d.id, d.data())).toList();

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
    await docRef.set(data);
    return Customer.fromDocument(docRef.id, data);
  }

  @override
  Future<Customer> show(int id) async {
    final docSnap = await _findCustomerDoc(id);
    if (docSnap == null || !docSnap.exists) {
      throw Exception('Pelanggan ID $id tidak ditemukan.');
    }

    // Hitung jumlah transaksi secara aman (offline-ready tanpa .count().get())
    final txDocs = await _getQueryDocsSafe(
      db.collection('transactions').where('customerId', isEqualTo: docSnap.id),
    );

    return Customer.fromDocument(
      docSnap.id,
      docSnap.data()!,
      transactionsCount: txDocs.length,
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
    final docSnap = await _findCustomerDoc(id);
    if (docSnap == null || !docSnap.exists) {
      throw Exception('Pelanggan ID $id tidak ditemukan.');
    }

    final updateData = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (phone != null) 'phone': (phone.isEmpty) ? null : phone.trim(),
      if (notes != null) 'notes': (notes.isEmpty) ? null : notes.trim(),
      if (isActive != null) 'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await docSnap.reference.update(updateData);
    final fresh = await _getDocSafe(docSnap.reference);
    final currentData = Map<String, dynamic>.from(docSnap.data() ?? {});
    currentData.addAll(updateData);
    return Customer.fromDocument(docSnap.id, fresh?.data() ?? currentData);
  }

  @override
  Future<void> destroy(int id) async {
    final docSnap = await _findCustomerDoc(id);
    if (docSnap == null || !docSnap.exists) return;

    // Validasi aturan: pelanggan dengan riwayat bon dilarang dihapus
    final txDocs = await _getQueryDocsSafe(
      db.collection('transactions').where('customerId', isEqualTo: docSnap.id).limit(1),
    );

    CustomerRulesService.validateCanDelete(
      transactionCount: txDocs.length,
    );

    await docSnap.reference.delete();
  }

  @override
  Future<List<TransactionSummary>> transactions(int id) async {
    final custSnap = await _findCustomerDoc(id);
    if (custSnap == null || !custSnap.exists) return [];

    final txDocs = await _getQueryDocsSafe(
      db
          .collection('transactions')
          .where('customerId', isEqualTo: custSnap.id)
          .orderBy('date', descending: true),
    );

    return txDocs.map((d) {
      return TransactionSummary.fromDocument(
        d.id,
        d.data(),
        customerName: custSnap.data()?['name'] as String?,
      );
    }).toList();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findCustomerDoc(int id) async {
    final custSnap = await _getDocSafe(_col.doc('cust_$id'));
    if (custSnap != null && custSnap.exists) return custSnap;

    final legSnap = await _getDocSafe(_col.doc('legacy_$id'));
    if (legSnap != null && legSnap.exists) return legSnap;

    final rawSnap = await _getDocSafe(_col.doc('$id'));
    if (rawSnap != null && rawSnap.exists) return rawSnap;

    final qLeg = await _getQueryDocsSafe(_col.where('legacyId', isEqualTo: id).limit(1));
    if (qLeg.isNotEmpty) return qLeg.first;

    final qId = await _getQueryDocsSafe(_col.where('id', isEqualTo: id).limit(1));
    if (qId.isNotEmpty) return qId.first;

    final all = await _getQueryDocsSafe(_col.limit(100));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == id) return d;
    }

    return null;
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
    final docs = await _getQueryDocsSafe(_col);
    final list = docs.map((d) => Category.fromDocument(d.id, d.data())).toList();
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
    await docRef.set(data);
    return Category.fromDocument(docRef.id, data);
  }

  @override
  Future<Category> update(int id, String name) async {
    final doc = await _findCategoryDoc(id);
    if (doc == null || !doc.exists) throw Exception('Kategori ID $id tidak ditemukan.');

    final updateData = {
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await doc.reference.update(updateData);
    final fresh = await _getDocSafe(doc.reference);
    final currentData = Map<String, dynamic>.from(doc.data() ?? {});
    currentData.addAll(updateData);
    return Category.fromDocument(doc.id, fresh?.data() ?? currentData);
  }

  @override
  Future<void> destroy(int id) async {
    final doc = await _findCategoryDoc(id);
    if (doc == null || !doc.exists) return;
    await doc.reference.delete();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findCategoryDoc(int id) async {
    final catSnap = await _getDocSafe(_col.doc('cat_$id'));
    if (catSnap != null && catSnap.exists) return catSnap;

    final legSnap = await _getDocSafe(_col.doc('legacy_$id'));
    if (legSnap != null && legSnap.exists) return legSnap;

    final rawSnap = await _getDocSafe(_col.doc('$id'));
    if (rawSnap != null && rawSnap.exists) return rawSnap;

    final qLeg = await _getQueryDocsSafe(_col.where('legacyId', isEqualTo: id).limit(1));
    if (qLeg.isNotEmpty) return qLeg.first;

    final qId = await _getQueryDocsSafe(_col.where('id', isEqualTo: id).limit(1));
    if (qId.isNotEmpty) return qId.first;

    final all = await _getQueryDocsSafe(_col.limit(100));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == id) return d;
    }

    return null;
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
    Query<Map<String, dynamic>> query = _col;
    if (isActive != null) {
      query = query.where('isActive', isEqualTo: isActive);
    }
    if (categoryId != null) {
      query = query.where('categoryId', isEqualTo: 'legacy_$categoryId');
    }

    final docs = await _getQueryDocsSafe(query);
    var list = docs.map((d) => Product.fromDocument(d.id, d.data())).toList();

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
    await docRef.set(data);
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
    final doc = await _findProductDoc(id);
    if (doc == null || !doc.exists) throw Exception('Produk ID $id tidak ditemukan.');

    final data = <String, dynamic>{
      if (categoryId != null) 'categoryId': 'legacy_$categoryId',
      if (name != null) 'name': name.trim(),
      if (defaultPrice != null) 'defaultPrice': defaultPrice,
      if (unit != null) 'unit': unit.trim(),
      if (isActive != null) 'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await doc.reference.update(data);
    final fresh = await _getDocSafe(doc.reference);
    final currentData = Map<String, dynamic>.from(doc.data() ?? {});
    currentData.addAll(data);
    return Product.fromDocument(doc.id, fresh?.data() ?? currentData);
  }

  @override
  Future<void> destroy(int id) async {
    final doc = await _findProductDoc(id);
    if (doc == null || !doc.exists) return;
    await doc.reference.delete();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findProductDoc(int id) async {
    final prodSnap = await _getDocSafe(_col.doc('prod_$id'));
    if (prodSnap != null && prodSnap.exists) return prodSnap;

    final legSnap = await _getDocSafe(_col.doc('legacy_$id'));
    if (legSnap != null && legSnap.exists) return legSnap;

    final rawSnap = await _getDocSafe(_col.doc('$id'));
    if (rawSnap != null && rawSnap.exists) return rawSnap;

    final qLeg = await _getQueryDocsSafe(_col.where('legacyId', isEqualTo: id).limit(1));
    if (qLeg.isNotEmpty) return qLeg.first;

    final qId = await _getQueryDocsSafe(_col.where('id', isEqualTo: id).limit(1));
    if (qId.isNotEmpty) return qId.first;

    final all = await _getQueryDocsSafe(_col.limit(100));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == id) return d;
    }

    return null;
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
    Query<Map<String, dynamic>> query = _col;

    if (customerId != null) {
      query = query.where('customerId', isEqualTo: 'legacy_$customerId');
    }
    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      query = query.where('date', isGreaterThanOrEqualTo: dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      query = query.where('date', isLessThanOrEqualTo: dateTo);
    }

    query = query.orderBy('date', descending: true);

    final docs = await _getQueryDocsSafe(query);
    var list = docs.map((d) => Transaction.fromDocument(d.id, d.data())).toList();

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((t) {
        return t.transactionNumber.toLowerCase().contains(q) ||
            (t.customer?.name.toLowerCase().contains(q) ?? false);
      }).toList();
    }

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
    String invoiceNumber;

    // Penomoran via Firestore Transaction (Online) atau Draft Sementara (Offline Opsi B)
    try {
      final counterRef = db.collection('counters').doc(InvoiceNumberService.counterDocId(transactionDate));
      invoiceNumber = await db.runTransaction((t) async {
        final counterDoc = await t.get(counterRef);
        final current = (counterDoc.data()?['currentSequence'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        t.set(counterRef, {'currentSequence': next}, SetOptions(merge: true));
        return InvoiceNumberService.formatOfficialNumber(transactionDate, next);
      }).timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      // Offline fallback: buat nomor draft sementara
      invoiceNumber = InvoiceNumberService.generateOfflineDraftNumber(transactionDate);
    }

    // Ambil nama customer untuk denormalisasi
    String? customerName;
    try {
      final cDoc = await _findCustomerDoc(customerId);
      if (cDoc != null && cDoc.exists) {
        customerName = cDoc.data()?['name'] as String?;
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

    await docRef.set(data);
    return Transaction.fromDocument(docRef.id, data);
  }

  @override
  Future<Transaction> show(int id) async {
    final doc = await _findTransactionDoc(id);
    if (doc == null || !doc.exists) throw Exception('Transaksi ID $id tidak ditemukan.');

    // Muat detail items dari subkoleksi
    final itemsDocs = await _getQueryDocsSafe(doc.reference.collection('items'));
    final items = itemsDocs
        .map((d) => TransactionItem.fromDocument(d.id, d.data(), transactionId: id))
        .toList();

    return Transaction.fromDocument(doc.id, doc.data()!, items: items);
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
    final doc = await _findTransactionDoc(id);
    if (doc == null || !doc.exists) throw Exception('Transaksi ID $id tidak ditemukan.');

    final data = <String, dynamic>{
      if (customerId != null) 'customerId': 'legacy_$customerId',
      if (transactionDate != null) 'date': transactionDate,
      if (status != null) 'status': status,
      if (paymentStatus != null) 'paymentStatus': paymentStatus,
      if (notes != null) 'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await doc.reference.update(data);
    final fresh = await _getDocSafe(doc.reference);
    final currentData = Map<String, dynamic>.from(doc.data() ?? {});
    currentData.addAll(data);
    return Transaction.fromDocument(doc.id, fresh?.data() ?? currentData);
  }

  @override
  Future<void> destroy(int id) async {
    final doc = await _findTransactionDoc(id);
    if (doc == null || !doc.exists) return;

    // Hapus items subcollection
    final items = await _getQueryDocsSafe(doc.reference.collection('items'));
    for (final it in items) {
      await it.reference.delete();
      // Hapus expense turunan jika ada
      final expDocId = ExpenseSyncService.docId(transactionId: id.toString(), itemId: it.id);
      await db.collection('expenses').doc(expDocId).delete().catchError((_) {});
    }

    await doc.reference.delete();
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
    final doc = await _findTransactionDoc(transactionId);
    if (doc == null || !doc.exists) throw Exception('Transaksi ID $transactionId tidak ditemukan.');

    final calcSubtotal = subtotal ?? (quantity * unitPrice);
    final newItemId = DateTime.now().millisecondsSinceEpoch;
    final itemRef = doc.reference.collection('items').doc('item_$newItemId');

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

    await itemRef.set(itemData);

    // Sinkronisasi potongan bon ke expenses (subtotal < 0)
    if (ExpenseSyncService.isExpenseItem(calcSubtotal)) {
      final txDate = doc.data()?['date']?.toString() ?? '';
      final exp = ExpenseSyncService.generateExpense(
        transactionId: transactionId.toString(),
        itemId: itemRef.id,
        transactionDate: txDate,
        productName: productName,
        description: description,
        subtotal: calcSubtotal,
      );
      if (exp != null) {
        await db.collection('expenses').doc(exp.docId).set(exp.toFirestoreDocument());
      }
    }

    // Hitung ulang total transaksi
    await _recalculateTotal(doc.reference);

    return TransactionItem.fromDocument(itemRef.id, itemData, transactionId: transactionId);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findItemDoc(int itemId) async {
    // 1. Cari via legacyId
    var q = await _getQueryDocsSafe(
      db.collectionGroup('items').where('legacyId', isEqualTo: itemId).limit(1),
    );
    if (q.isNotEmpty) return q.first;

    // 2. Cari via id
    q = await _getQueryDocsSafe(
      db.collectionGroup('items').where('id', isEqualTo: itemId).limit(1),
    );
    if (q.isNotEmpty) return q.first;

    // 3. Fallback scan item_ docId
    final all = await _getQueryDocsSafe(db.collectionGroup('items').limit(200));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == itemId) return d;
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
    final itemDoc = await _findItemDoc(itemId);
    if (itemDoc == null || !itemDoc.exists) throw Exception('Item ID $itemId tidak ditemukan.');

    final oldData = itemDoc.data()!;
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

    await itemDoc.reference.update(data);

    // Update / hapus sinkronisasi expense
    final txRef = itemDoc.reference.parent.parent!;
    final txSnap = await _getDocSafe(txRef);
    final txId = (txSnap?.id ?? '').replaceAll(RegExp(r'^(legacy_|tx_)'), '');
    final expDocId = ExpenseSyncService.docId(transactionId: txId, itemId: itemDoc.id);

    if (ExpenseSyncService.isExpenseItem(newSubtotal)) {
      final exp = ExpenseSyncService.generateExpense(
        transactionId: txId,
        itemId: itemDoc.id,
        transactionDate: txSnap?.data()?['date']?.toString() ?? '',
        productName: productName ?? oldData['productName']?.toString() ?? '',
        description: description ?? oldData['description']?.toString(),
        subtotal: newSubtotal,
      );
      if (exp != null) {
        await db.collection('expenses').doc(expDocId).set(exp.toFirestoreDocument());
      }
    } else {
      await db.collection('expenses').doc(expDocId).delete().catchError((_) {});
    }

    await _recalculateTotal(txRef);
    final fresh = await _getDocSafe(itemDoc.reference);
    final currentData = Map<String, dynamic>.from(oldData);
    currentData.addAll(data);
    return TransactionItem.fromDocument(itemDoc.id, fresh?.data() ?? currentData);
  }

  @override
  Future<void> deleteItem(int itemId) async {
    final itemDoc = await _findItemDoc(itemId);
    if (itemDoc == null || !itemDoc.exists) return;

    final txRef = itemDoc.reference.parent.parent!;
    final txSnap = await _getDocSafe(txRef);
    final txId = (txSnap?.id ?? '').replaceAll(RegExp(r'^(legacy_|tx_)'), '');

    // Hapus expense turunan jika ada
    final expDocId = ExpenseSyncService.docId(transactionId: txId, itemId: itemDoc.id);
    await db.collection('expenses').doc(expDocId).delete().catchError((_) {});

    await itemDoc.reference.delete();
    await _recalculateTotal(txRef);
  }

  Future<void> _recalculateTotal(DocumentReference<Map<String, dynamic>> txRef) async {
    final itemsDocs = await _getQueryDocsSafe(txRef.collection('items'));
    int total = 0;
    for (final it in itemsDocs) {
      total += numFrom(it.data()['subtotal']);
    }
    await txRef.update({
      'totalAmount': total,
      'itemCount': itemsDocs.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findCustomerDoc(int id) async {
    final cCol = db.collection('customers');
    final cCust = await _getDocSafe(cCol.doc('cust_$id'));
    if (cCust != null && cCust.exists) return cCust;
    final cLeg = await _getDocSafe(cCol.doc('legacy_$id'));
    if (cLeg != null && cLeg.exists) return cLeg;
    final cRaw = await _getDocSafe(cCol.doc('$id'));
    if (cRaw != null && cRaw.exists) return cRaw;

    final qLeg = await _getQueryDocsSafe(cCol.where('legacyId', isEqualTo: id).limit(1));
    if (qLeg.isNotEmpty) return qLeg.first;

    final qId = await _getQueryDocsSafe(cCol.where('id', isEqualTo: id).limit(1));
    if (qId.isNotEmpty) return qId.first;

    return null;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findTransactionDoc(int id) async {
    // 1. Direct doc ID
    final txSnap = await _getDocSafe(_col.doc('tx_$id'));
    if (txSnap != null && txSnap.exists) return txSnap;

    final legSnap = await _getDocSafe(_col.doc('legacy_$id'));
    if (legSnap != null && legSnap.exists) return legSnap;

    final dirSnap = await _getDocSafe(_col.doc('$id'));
    if (dirSnap != null && dirSnap.exists) return dirSnap;

    // 2. Query legacyId
    final qLegacy = await _getQueryDocsSafe(_col.where('legacyId', isEqualTo: id).limit(1));
    if (qLegacy.isNotEmpty) return qLegacy.first;

    // 3. Query id
    final qId = await _getQueryDocsSafe(_col.where('id', isEqualTo: id).limit(1));
    if (qId.isNotEmpty) return qId.first;

    // 4. Pencocokan nomor invoice INV-YYYYMMDD-NNN jika id formatnya tanggal+urutan
    final idStr = id.toString();
    if (idStr.length > 8) {
      final datePart = idStr.substring(0, 8);
      final seqPart = int.tryParse(idStr.substring(8)) ?? 0;
      final formattedInv = 'INV-$datePart-${seqPart.toString().padLeft(3, '0')}';
      final qInv = await _getQueryDocsSafe(_col.where('number', isEqualTo: formattedInv).limit(1));
      if (qInv.isNotEmpty) return qInv.first;
    }

    // 5. Fallback scan
    final all = await _getQueryDocsSafe(_col.limit(100));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == id) return d;
    }

    return null;
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
    Query<Map<String, dynamic>> query = _col;
    if (source != null && source.isNotEmpty) {
      query = query.where('source', isEqualTo: source);
    }
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      query = query.where('date', isGreaterThanOrEqualTo: dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      query = query.where('date', isLessThanOrEqualTo: dateTo);
    }

    query = query.orderBy('date', descending: true);
    final docs = await _getQueryDocsSafe(query);
    var list = docs.map((d) => Expense.fromDocument(d.id, d.data())).toList();

    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((e) => e.title.toLowerCase().contains(q)).toList();
    }

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
    await docRef.set(data);
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
    final doc = await _findExpenseDoc(id);
    if (doc == null || !doc.exists) throw Exception('Pengeluaran ID $id tidak ditemukan.');

    if (doc.data()?['source'] == 'bon') {
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

    await doc.reference.update(data);
    final fresh = await _getDocSafe(doc.reference);
    final currentData = Map<String, dynamic>.from(doc.data() ?? {});
    currentData.addAll(data);
    return Expense.fromDocument(doc.id, fresh?.data() ?? currentData);
  }

  @override
  Future<void> destroy(int id) async {
    final doc = await _findExpenseDoc(id);
    if (doc == null || !doc.exists) return;

    if (doc.data()?['source'] == 'bon') {
      throw Exception('Hapus item di bon terkait.');
    }

    await doc.reference.delete();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findExpenseDoc(int id) async {
    final expSnap = await _getDocSafe(_col.doc('exp_$id'));
    if (expSnap != null && expSnap.exists) return expSnap;

    final legSnap = await _getDocSafe(_col.doc('legacy_$id'));
    if (legSnap != null && legSnap.exists) return legSnap;

    final rawSnap = await _getDocSafe(_col.doc('$id'));
    if (rawSnap != null && rawSnap.exists) return rawSnap;

    final qLeg = await _getQueryDocsSafe(_col.where('legacyId', isEqualTo: id).limit(1));
    if (qLeg.isNotEmpty) return qLeg.first;

    final qId = await _getQueryDocsSafe(_col.where('id', isEqualTo: id).limit(1));
    if (qId.isNotEmpty) return qId.first;

    final all = await _getQueryDocsSafe(_col.limit(100));
    for (final d in all) {
      if (parseEntityId(d.id, d.data()) == id) return d;
    }

    return null;
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

    // Coba baca dari rollup daily_summary/{todayStr} dengan aman
    final summaryDoc = await _getDocSafe(db.collection('daily_summary').doc(todayStr));

    int activeCustCount = 0;
    try {
      final custDocs = await _getQueryDocsSafe(
        db.collection('customers').where('isActive', isEqualTo: true),
      );
      activeCustCount = custDocs.length;
    } catch (_) {}

    // Muat 10 transaksi terbaru
    final recentDocs = await _getQueryDocsSafe(
      db.collection('transactions').orderBy('date', descending: true).limit(10),
    );

    final recent = recentDocs.map((d) {
      return TransactionSummary.fromDocument(d.id, d.data());
    }).toList();

    if (summaryDoc != null && summaryDoc.exists && summaryDoc.data() != null) {
      final s = summaryDoc.data()!;
      return DashboardData(
        bonHariIni: numFrom(s['saleCount']),
        totalHariIni: numFrom(s['saleTotal']),
        lunasHariIni: numFrom(s['paidTotal']),
        lunasTotal: numFrom(s['paidTotal']),
        masihHutang: numFrom(s['unpaidTotal']),
        pengeluaranHariIni: numFrom(s['expenseTotal']),
        pengeluaranTotal: numFrom(s['expenseTotal']),
        totalPelanggan: activeCustCount,
        recent: recent,
      );
    }

    // Fallback: agregasi langsung jika rollup belum tersedia atau saat OFFLINE
    final allTxDocs = await _getQueryDocsSafe(db.collection('transactions'));
    final allExpDocs = await _getQueryDocsSafe(db.collection('expenses'));

    final stats = DashboardAggregateService.computeDashboardStats(
      todayDateStr: todayStr,
      allTransactions: allTxDocs.map((d) => d.data()).toList(),
      allExpenses: allExpDocs.map((d) => d.data()).toList(),
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
    // Ambil transaksi completed dari Firestore secara aman
    final txDocs = await _getQueryDocsSafe(
      db.collection('transactions').where('status', isEqualTo: 'completed'),
    );

    final txList = <Map<String, dynamic>>[];
    for (final doc in txDocs) {
      final txData = Map<String, dynamic>.from(doc.data());
      final itemsDocs = await _getQueryDocsSafe(doc.reference.collection('items'));
      txData['items'] = itemsDocs.map((d) => d.data()).toList();
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
    final direct = await _getDocSafe(db.collection('transactions').doc('legacy_$transactionId')) ??
        await _getDocSafe(db.collection('transactions').doc('tx_$transactionId')) ??
        await _getDocSafe(db.collection('transactions').doc('$transactionId'));
    if (direct == null || !direct.exists) {
      return BonCigaretteSummary(items: [], totalQuantity: 0, totalAmount: 0);
    }

    final itemsDocs = await _getQueryDocsSafe(direct.reference.collection('items'));
    int qty = 0;
    int amount = 0;
    final items = <CigaretteItemRow>[];

    for (final doc in itemsDocs) {
      final d = doc.data();
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
