/// Model hasil sinkronisasi pengeluaran dari item bon.
class SyncedExpense {
  final String docId;
  final String syncKey;
  final String date;
  final String title;
  final String? category;
  final int amount;
  final String source;
  final String transactionId;
  final String? notes;

  const SyncedExpense({
    required this.docId,
    required this.syncKey,
    required this.date,
    required this.title,
    this.category,
    required this.amount,
    this.source = 'bon',
    required this.transactionId,
    this.notes,
  });

  Map<String, dynamic> toFirestoreDocument({int? legacyId}) => {
        'date': date,
        'title': title,
        'category': category,
        'amount': amount,
        'source': source,
        'transactionId': transactionId,
        'syncKey': syncKey,
        'notes': notes,
        if (legacyId != null) 'legacyId': legacyId!,
      };
}

/// Service sinkronisasi potongan bon ke dokumen expense (porting dari Laravel [ExpenseSyncService]).
class ExpenseSyncService {
  ExpenseSyncService._();

  static const String sourceBon = 'bon';

  /// Format sync_key unik: `bon:{transactionId}:{itemId}`.
  static String syncKey({required String transactionId, required String itemId}) {
    return 'bon:$transactionId:$itemId';
  }

  /// Format docId dokumen di koleksi `expenses`: `bon_{transactionId}_{itemId}`.
  static String docId({required String transactionId, required String itemId}) {
    return 'bon_${transactionId}_$itemId';
  }

  /// Apakah item bon merupakan potongan/pengeluaran (subtotal < 0).
  static bool isExpenseItem(int subtotal) {
    return subtotal < 0;
  }

  /// Menghasilkan objek [SyncedExpense] jika subtotal negatif, atau null jika bukan potongan.
  static SyncedExpense? generateExpense({
    required String transactionId,
    required String itemId,
    required String transactionDate,
    required String productName,
    String? description,
    required int subtotal,
  }) {
    if (!isExpenseItem(subtotal)) return null;

    return SyncedExpense(
      docId: docId(transactionId: transactionId, itemId: itemId),
      syncKey: syncKey(transactionId: transactionId, itemId: itemId),
      date: transactionDate,
      title: productName,
      category: null,
      amount: subtotal.abs(),
      source: sourceBon,
      transactionId: transactionId,
      notes: description,
    );
  }

  /// Memeriksa apakah expense tertentu bersumber dari transaksi yang dihapus.
  static bool isBelongsToTransaction(String expenseDocId, String transactionId) {
    return expenseDocId.startsWith('bon_${transactionId}_');
  }
}
