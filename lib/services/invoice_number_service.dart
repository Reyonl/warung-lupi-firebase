/// Service untuk penomoran transaksi bon (porting dari [Transaction::generateTransactionNumber]).
///
/// Format penomoran:
/// - Nomor Resmi: `INV-YYYYMMDD-NNN` (di-generate via Firestore transaction dengan atomic counter).
/// - Nomor Draft Offline (Opsi B): `DRAFT-YYYYMMDD-XXX` (dibuat saat offline, lalu dikonversi saat sinkron).
class InvoiceNumberService {
  InvoiceNumberService._();

  /// Menghasilkan nomor resmi `INV-YYYYMMDD-NNN`.
  /// [dateStr] format `yyyy-MM-dd` atau `yyyyMMdd`.
  /// [sequence] bilangan bulat positif mulai dari 1.
  static String formatOfficialNumber(String dateStr, int sequence) {
    final cleanDate = dateStr.replaceAll('-', '');
    final paddedSeq = sequence.toString().padLeft(3, '0');
    return 'INV-$cleanDate-$paddedSeq';
  }

  /// Menghasilkan nomor draft sementara saat perangkat dalam mode offline (Opsi B).
  /// [dateStr] format `yyyy-MM-dd` atau `yyyyMMdd`.
  /// [uniqueSuffix] opsional (jika null, memakai milidetik sejak epoch).
  static String generateOfflineDraftNumber(String dateStr, {String? uniqueSuffix}) {
    final cleanDate = dateStr.replaceAll('-', '');
    final suffix = uniqueSuffix ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'DRAFT-$cleanDate-$suffix';
  }

  /// Mengecek apakah sebuah nomor bon adalah nomor sementara / offline draft.
  static bool isDraft(String? number) {
    if (number == null || number.isEmpty) return true;
    return number.startsWith('DRAFT-') || number.startsWith('TEMP-');
  }

  /// Mengekstrak tanggal `yyyyMMdd` dari nomor invoice (`INV-YYYYMMDD-NNN` atau `DRAFT-YYYYMMDD-XXX`).
  static String? extractDatePart(String number) {
    final parts = number.split('-');
    if (parts.length >= 2 && parts[1].length == 8) {
      return parts[1];
    }
    return null;
  }

  /// Nama dokumen counter di koleksi `counters` Firestore.
  /// Contoh: `counters/invoice_20261012`.
  static String counterDocId(String dateStr) {
    final cleanDate = dateStr.replaceAll('-', '');
    return 'invoice_$cleanDate';
  }
}
