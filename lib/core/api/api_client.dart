import '../../services/customer_rules_service.dart';

/// Helper pemformat pesan error untuk ditampilkan ke kasir.
class ApiClient {
  ApiClient._();

  static String errorMessage(
    Object? error, {
    String fallback = 'Terjadi kesalahan. Silakan coba lagi.',
  }) {
    if (error == null) return fallback;
    if (error is CustomerDeletionException) return error.message;
    final raw = error.toString().trim();
    if (raw.startsWith('Exception:')) {
      final msg = raw.substring('Exception:'.length).trim();
      if (msg.isNotEmpty) return msg;
    }
    return fallback;
  }
}
