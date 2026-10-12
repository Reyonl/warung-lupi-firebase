/// Aturan bisnis pelanggan (porting dari Laravel [CustomerController]).
class CustomerRulesService {
  CustomerRulesService._();

  static const String cannotDeleteMessage =
      'Pelanggan tidak dapat dihapus karena memiliki riwayat bon.';

  /// Memvalidasi apakah pelanggan boleh dihapus.
  /// Menghasilkan true jika boleh, atau melempar [CustomerDeletionException] jika masih punya transaksi.
  static bool validateCanDelete({required int transactionCount}) {
    if (transactionCount > 0) {
      throw CustomerDeletionException(cannotDeleteMessage);
    }
    return true;
  }

  /// Mengecek secara aman apakah pelanggan bisa dihapus tanpa melempar exception.
  static bool canDelete({required int transactionCount}) {
    return transactionCount <= 0;
  }
}

/// Exception saat pelanggan tidak dapat dihapus.
class CustomerDeletionException implements Exception {
  final String message;

  const CustomerDeletionException(this.message);

  @override
  String toString() => message;
}
