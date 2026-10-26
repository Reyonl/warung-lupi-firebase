/// Util promo — padanan persis `calculatePromoSubtotal` di CreateTransaction.jsx.
///
/// Aturan (jangan diubah — business logic yang sudah berjalan):
/// - Nama mengandung "gorengan" → tiap 3 pcs dihitung 5000 (sisanya × harga)
/// - Nama mengandung salah satu dari "donat", "nagasari", "lemper", "jajanan"
///   → tiap 2 pcs dihitung 5000 (sisanya × harga)
int calculatePromoSubtotal(String name, int qty, int unitPrice) {
  if (name.isEmpty) return qty * unitPrice;
  final lower = name.toLowerCase();
  var subtotal = qty * unitPrice;

  if (lower.contains('gorengan')) {
    final promoQty = qty ~/ 3;
    final remainder = qty % 3;
    subtotal = (promoQty * 5000) + (remainder * unitPrice);
  } else if (['donat', 'nagasari', 'lemper', 'jajanan', 'sosis solo', 'sosis'].any(lower.contains)) {
    final promoQty = qty ~/ 2;
    final remainder = qty % 2;
    subtotal = (promoQty * 5000) + (remainder * unitPrice);
  }
  return subtotal;
}

/// Padanan `formatPriceDisplay` di CreateTransaction.jsx:
/// tampilkan angka dengan pemisah ribuan (id-ID).
String formatPriceDisplay(dynamic val) {
  if (val == null || val == '' || val == '-') return val?.toString() ?? '';
  final s = val.toString();
  final isNeg = s.startsWith('-');
  final numStr = isNeg ? s.substring(1) : s;
  final digits = numStr.replaceAll(RegExp(r'[^0-9]'), '');
  final formatted = _thousands(digits);
  return isNeg ? '-$formatted' : formatted;
}

String _thousands(String digits) {
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Padanan `handlePriceChange`: sanitasi input harga — hanya digit,
/// minus hanya boleh di awal.
String sanitizePriceInput(String raw) {
  var s = raw.replaceAll(RegExp(r'[^0-9-]'), '');
  if (s.lastIndexOf('-') > 0) {
    s = s.replaceAll('-', '');
  }
  if (s != '0' && s != '-' && s != '-0') {
    s = s.replaceFirstMapped(RegExp(r'^(-?)0+(?=\d)'), (m) => m.group(1)!);
  }
  return s;
}
