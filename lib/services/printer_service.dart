import 'dart:convert';
import 'dart:typed_data';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/models.dart';
import '../utils/format.dart';

/// PrinterService — cetak thermal via **Bluetooth Classic (SPP/RFCOMM)**.
///
/// Sebelumnya layanan ini memakai `flutter_blue_plus` (BLE/GATT). Printer
/// thermal yang dipasangkan lewat Pengaturan Android menggunakan profil
/// Bluetooth Classic dan menerima byte ESC/POS lewat socket RFCOMM
/// (UUID 00001101-0000-1000-8000-00805F9B34FB) — BUKAN BLE GATT
/// characteristic. Itulah sebabnya pairing berhasil tapi cetak selalu gagal
/// dengan pesan "Tidak menemukan akses cetak di perangkat ini."
///
/// `print_bluetooth_thermal` mengurus semuanya: daftar perangkat paired,
/// koneksi `createRfcommSocketToServiceRecord`, pemotongan buffer, dan
/// permintaan izin BLUETOOTH_CONNECT/SCAN di Android 12+.
class PrinterService {
  PrinterService._();

  static final PrinterService instance = PrinterService._();

  // Printer aktif di memori (hasil Pair/Pilih Printer di Pengaturan).
  String? _activeName;
  String? _activeMac;

  String? get activeName => _activeName;
  String? get activeMac => _activeMac;
  bool get hasActiveDevice => _activeMac != null && _activeMac!.isNotEmpty;

  /// Catat printer aktif tanpa membuka koneksi (koneksi dibuka saat mencetak).
  void setActivePrinter({required String name, required String mac}) {
    _activeName = name;
    _activeMac = mac;
  }

  void clearActivePrinter() {
    _activeName = null;
    _activeMac = null;
  }

  /// Bluetooth siap dipakai (izin Android 12+ diberikan + adapter menyala).
  /// Men-trigger dialog izin sistem bila belum diberikan.
  Future<void> ensureReady() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted) {
      throw PrinterException(
        'Izin Bluetooth belum diberikan. Setujui permintaan izin "Perangkat di sekitar" untuk aplikasi ini, lalu coba lagi.',
      );
    }
    final on = await PrintBluetoothThermal.bluetoothEnabled;
    if (!on) {
      throw PrinterException(
        'Bluetooth mati. Nyalakan Bluetooth di perangkat Anda, lalu coba lagi.',
      );
    }
  }

  /// Daftar printer Bluetooth Classic yang sudah dipasangkan (bonded) dengan
  /// HP ini. Printer dipasangkan lewat Pengaturan Android → Bluetooth.
  Future<List<PrinterDevice>> bondedPrinters() async {
    await ensureReady();
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list
        .map((e) => PrinterDevice(name: e.name, mac: e.macAdress))
        .toList();
  }

  /// Buka koneksi ke printer [mac] (idempoten — aman dipanggil sebelum cetak).
  Future<void> _connect(String mac) async {
    if (mac.isEmpty) {
      throw PrinterException(
        'Printer belum dikonfigurasi. Buka Pengaturan → Printer Thermal untuk memilih printer.',
      );
    }
    await ensureReady();

    if (await PrintBluetoothThermal.connectionStatus) {
      // Sudah tersambung (mis. dari Tes Cetak sebelumnya).
      return;
    }
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!ok) {
      throw PrinterException(
        'Gagal terhubung ke printer $mac. Pastikan printer menyala, masih '
        'terpasang (paired) di Pengaturan Bluetooth Android, dan tidak sedang '
        'dipakai aplikasi lain.',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
    } catch (_) {
      // Abaikan — koneksi mungkin sudah putus dari sisi printer.
    }
  }

  Future<void> _write(Uint8List bytes) async {
    final ok = await PrintBluetoothThermal.writeBytes(bytes.toList());
    if (!ok) {
      throw PrinterException(
        'Printer menolak data cetak. Periksa kertas, daya printer, lalu coba lagi.',
      );
    }
  }

  /// Selesaikan alamat MAC printer; utamakan MAC yang tersimpan (paling andal).
  Future<String> resolveMac({
    required String printerName,
    required String printerId,
  }) async {
    // 1. MAC/ID yang tersimpan.
    if (printerId.isNotEmpty && printerId != '-') return printerId;

    // 2. Fallback: cocokkan berdasarkan nama di antara perangkat paired.
    if (printerName.isNotEmpty) {
      final paired = await bondedPrinters();
      for (final p in paired) {
        if (p.name == printerName) return p.mac;
      }
    }

    // 3. Terakhir: printer aktif di memori sesi ini.
    if (hasActiveDevice) return _activeMac!;

    throw PrinterException(
      'Koneksi ke printer terputus atau printer tidak lagi terpasang (paired). '
      'Buka menu Pengaturan → Printer Thermal untuk menghubungkan kembali.',
    );
  }

  /// Cetak struk penuh (padanan handleCetak) — byte ESC/POS dari [buildEscPos].
  Future<void> printReceipt({
    required Transaction transaction,
    required String thermalSize, // '58mm' | '80mm'
    required String printerName,
    required String printerId,
  }) async {
    final mac = await resolveMac(
      printerName: printerName,
      printerId: printerId,
    );
    await _connect(mac);
    try {
      final bytes = buildEscPos(transaction, thermalSize);
      await _write(bytes);
      // Jeda agar buffer printer selesai dicetak sebelum koneksi ditutup.
      await Future.delayed(const Duration(milliseconds: 600));
    } finally {
      await disconnect();
    }
  }

  /// Tes cetak (padanan handleTestPrint) — tidak bergantung pada data bon,
  /// jadi aman dipakai untuk memverifikasi koneksi printer saat setup.
  Future<void> printTest({
    required String printerName,
    required String printerId,
  }) async {
    final mac = await resolveMac(
      printerName: printerName,
      printerId: printerId,
    );
    await _connect(mac);
    try {
      // '\x1B\x40' init; '\x1B\x61\x01' center; teks; '\x1B\x61\x00' left
      final bytes = <int>[
        0x1B, 0x40, // init
        0x1B, 0x61, 0x01, // center
        ...utf8.encode('TES PRINTER BERHASIL\n\n'),
        0x1B, 0x61, 0x00, // left
        ...utf8.encode('Printer Utama Anda siap digunakan.\n\n\n'),
      ];
      await _write(Uint8List.fromList(bytes));
      await Future.delayed(const Duration(milliseconds: 600));
    } finally {
      await disconnect();
    }
  }

  /// Bangun byte ESC/POS struk — padanan kode `handleCetak` di TransactionDetail.jsx.
  Uint8List buildEscPos(Transaction t, String size) {
    final maxChars = size == '80mm' ? 48 : 32;
    final bytes = <int>[];

    void addText(String s) => bytes.addAll(utf8.encode(s));
    void addBytes(List<int> arr) => bytes.addAll(arr);

    String rightAlign(String label, String value) {
      final available = maxChars - label.length;
      final padding = (available - value.length) < 1
          ? 1
          : (available - value.length);
      return label + (' ' * padding) + value;
    }

    List<String> wrapText(String text) {
      final lines = <String>[];
      var currentLine = '';
      final words = text.split(' ');
      for (final word in words) {
        if ((currentLine + word).length > maxChars) {
          if (currentLine.isNotEmpty) lines.add(currentLine.trim());
          currentLine = word + ' ';
        } else {
          currentLine += word + ' ';
        }
      }
      if (currentLine.isNotEmpty) lines.add(currentLine.trim());
      return lines;
    }

    void boldOn() {
      addBytes([0x1B, 0x45, 1]); // Emphasized
      addBytes([0x1B, 0x47, 1]); // Double-strike
    }

    void boldOff() {
      addBytes([0x1B, 0x45, 0]);
      addBytes([0x1B, 0x47, 0]);
    }

    addBytes([0x1B, 0x40]); // Initialize
    addBytes([0x1B, 0x4D, 0x00]); // Force Font A

    // Header
    addBytes([0x1B, 0x61, 0x01]); // Center
    addBytes([0x1B, 0x21, 0x30]); // Double width & height
    boldOn();
    addText('WARUNG LUPI\n');
    boldOff();
    addBytes([0x1B, 0x21, 0x00]);
    addText('Ke pasar membeli semangka\n');
    addText('Jangan lupa mampir ke Lupi\n');

    // Info
    addBytes([0x1B, 0x61, 0x00]); // Left
    addText('-' * maxChars + '\n');
    addText(rightAlign('No.', t.transactionNumber) + '\n');
    final dateStr = formatDateShort(t.transactionDate);
    addText(rightAlign('Tanggal', dateStr) + '\n');
    addText(rightAlign('Pelanggan', t.customer?.name ?? 'Umum') + '\n');
    addText('-' * maxChars + '\n');

    // Items (penambahan) — padanan web: tambahan dulu, potongan terpisah
    final split = splitItems(t.items);
    for (final item in split.adds) {
      final name = (item.description != null && item.description!.isNotEmpty)
          ? '${item.productName} - ${item.description}'
          : item.productName;
      boldOn();
      for (final l in wrapText(name)) {
        addText(l + '\n');
      }
      boldOff();
      final leftStr = '${item.quantity} x ${formatNumber(item.unitPrice)}';
      final rightStr = formatNumber(item.subtotal);
      addText(rightAlign(leftStr, rightStr) + '\n');
    }

    // Potongan (item minus)
    if (split.deductions.isNotEmpty) {
      addText('-' * maxChars + '\n');
      addBytes([0x1B, 0x61, 0x01]); // Center
      boldOn();
      addText('POTONGAN\n');
      boldOff();
      addBytes([0x1B, 0x61, 0x00]); // Left
      for (final item in split.deductions) {
        final name = (item.description != null && item.description!.isNotEmpty)
            ? '${item.productName} - ${item.description}'
            : item.productName;
        for (final l in wrapText(name)) {
          addText(l + '\n');
        }
        addText(
          rightAlign(
                '${item.quantity} x ${formatNumber(item.unitPrice)}',
                '-${formatNumber(item.subtotal.abs())}',
              ) +
              '\n',
        );
      }
    }

    addText('-' * maxChars + '\n');

    // Total
    if (split.deductions.isNotEmpty) {
      addText(
        rightAlign('Sebelum Potongan', formatNumber(split.totalBefore)) + '\n',
      );
    }
    boldOn();
    addBytes([0x1B, 0x21, 0x10]); // Double height only
    addText(rightAlign('TOTAL', formatNumber(t.totalAmount)) + '\n');
    addBytes([0x1B, 0x21, 0x00]);
    boldOff();

    if (t.notes != null && t.notes!.isNotEmpty) {
      addText('\nCatatan: ${t.notes}\n');
    }
    addText('\n');

    // QR Code QRIS (static value dari TransactionDetail.jsx)
    const qrisData =
        '00020101021126610014COM.GO-JEK.WWW01189360091431908993800210G1908993800303UMI51440014ID.CO.QRIS.WWW0215ID10253695702010303UMI5204549953033605802ID5923WARUNG LUPI, Pagedangan6009TANGERANG61051533062070703A0163044C4B';
    final qrisBytes = utf8.encode(qrisData);
    final pL = (qrisBytes.length + 3) % 256;
    final pH = (qrisBytes.length + 3) ~/ 256;

    addBytes([0x1B, 0x61, 0x01]); // center
    addBytes([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]); // Model 2
    addBytes([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05]); // Size 5
    addBytes([
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x45,
      0x31,
    ]); // Error correction M
    addBytes([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]); // Store data
    addBytes(qrisBytes.toList());
    addBytes([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]); // Print QR

    addText('\n');
    addBytes([0x1B, 0x61, 0x01]);
    addText('Terima kasih sudah belanja\n');
    addText('Semoga puas di hati\n\n\n');

    return Uint8List.fromList(bytes);
  }

  Future<void> printShiftReport({
    required SalesReportData report,
    required String thermalSize,
    required String printerName,
    required String printerId,
  }) async {
    final mac = await resolveMac(
      printerName: printerName,
      printerId: printerId,
    );
    await _connect(mac);
    try {
      final bytes = buildShiftReportEscPos(report, thermalSize);
      await _write(bytes);
      await Future.delayed(const Duration(milliseconds: 600));
    } finally {
      await disconnect();
    }
  }

  Uint8List buildShiftReportEscPos(SalesReportData report, String size) {
    final maxChars = size == '80mm' ? 48 : 32;
    final bytes = <int>[];

    void addText(String s) => bytes.addAll(utf8.encode(s));
    void addBytes(List<int> arr) => bytes.addAll(arr);

    String rightAlign(String label, String value) {
      final available = maxChars - label.length;
      final padding = (available - value.length) < 1 ? 1 : (available - value.length);
      return label + (' ' * padding) + value;
    }

    void boldOn() {
      addBytes([0x1B, 0x45, 1]);
      addBytes([0x1B, 0x47, 1]);
    }

    void boldOff() {
      addBytes([0x1B, 0x45, 0]);
      addBytes([0x1B, 0x47, 0]);
    }

    addBytes([0x1B, 0x40]);
    addBytes([0x1B, 0x4D, 0x00]);

    addBytes([0x1B, 0x61, 0x01]);
    addBytes([0x1B, 0x21, 0x30]);
    boldOn();
    addText('WARUNG LUPI\n');
    boldOff();
    addBytes([0x1B, 0x21, 0x00]);
    addText('Ke pasar membeli semangka\n');
    addText('Pagedangan, Tangerang\n');
    addText('-' * maxChars + '\n');
    boldOn();
    addText('REKAP LAPORAN PENJUALAN\n');
    boldOff();
    addText('Periode: ' + report.dateFrom + ' s/d ' + report.dateTo + '\n');
    addText('-' * maxChars + '\n');

    addBytes([0x1B, 0x61, 0x00]);
    addText(rightAlign('Total Bon', report.totalTransactions.toString() + ' transaksi') + '\n');
    addText(rightAlign('Omset Kotor', formatNumber(report.grossSales)) + '\n');
    if (report.promoDiscounts > 0) {
      addText(rightAlign('Diskon Promo', '-' + formatNumber(report.promoDiscounts)) + '\n');
    }
    addText(rightAlign('Omset Bersih', formatNumber(report.netSales)) + '\n');
    addText(rightAlign('Pengeluaran', '-' + formatNumber(report.totalExpenses)) + '\n');
    addText('-' * maxChars + '\n');

    boldOn();
    addBytes([0x1B, 0x21, 0x10]);
    addText(rightAlign('PROFIT BERSIH', formatNumber(report.netProfit)) + '\n');
    addBytes([0x1B, 0x21, 0x00]);
    boldOff();
    addText('-' * maxChars + '\n');

    boldOn();
    addText('METODE PEMBAYARAN:\n');
    boldOff();
    addText(rightAlign('Tunai', formatNumber(report.cashTotal)) + '\n');
    addText(rightAlign('QRIS / Transfer', formatNumber(report.nonCashTotal)) + '\n');
    addText(rightAlign('Kasbon (Hutang)', formatNumber(report.unpaidTotal)) + '\n');
    addText('-' * maxChars + '\n');

    if (report.topProducts.isNotEmpty) {
      boldOn();
      addText('PRODUK TERLARIS:\n');
      boldOff();
      int rank = 1;
      for (final p in report.topProducts) {
        addText(rightAlign(rank.toString() + '. ' + p.productName, p.quantity.toString() + ' pcs') + '\n');
        addText(rightAlign('   Total', formatNumber(p.totalAmount)) + '\n');
        rank++;
      }
      addText('-' * maxChars + '\n');
    }

    addBytes([0x1B, 0x61, 0x01]);
    addText('Sistem Rekap Warung Lupi\n');
    addText('Dicetak: ' + DateTime.now().toString().substring(0, 16) + '\n\n\n');

    return Uint8List.fromList(bytes);
  }

  String generateShiftReportRawText(SalesReportData report) {
    const maxChars = 32;
    String rightAlign(String label, String value) {
      final available = maxChars - label.length;
      final padding = (available - value.length) < 1 ? 1 : (available - value.length);
      return label + (' ' * padding) + value;
    }

    final sb = StringBuffer();
    sb.writeln('WARUNG LUPI');
    sb.writeln('REKAP LAPORAN PENJUALAN');
    sb.writeln('Periode: ' + report.dateFrom + ' s/d ' + report.dateTo);
    sb.writeln('--------------------------------');
    sb.writeln(rightAlign('Total Bon', report.totalTransactions.toString() + ' transaksi'));
    sb.writeln(rightAlign('Omset Kotor', formatNumber(report.grossSales)));
    if (report.promoDiscounts > 0) {
      sb.writeln(rightAlign('Diskon Promo', '-' + formatNumber(report.promoDiscounts)));
    }
    sb.writeln(rightAlign('Omset Bersih', formatNumber(report.netSales)));
    sb.writeln(rightAlign('Pengeluaran', '-' + formatNumber(report.totalExpenses)));
    sb.writeln('--------------------------------');
    sb.writeln(rightAlign('PROFIT BERSIH', formatNumber(report.netProfit)));
    sb.writeln('--------------------------------');
    sb.writeln('METODE PEMBAYARAN:');
    sb.writeln(rightAlign('Tunai', formatNumber(report.cashTotal)));
    sb.writeln(rightAlign('QRIS / Transfer', formatNumber(report.nonCashTotal)));
    sb.writeln(rightAlign('Kasbon (Hutang)', formatNumber(report.unpaidTotal)));
    sb.writeln('--------------------------------');
    if (report.topProducts.isNotEmpty) {
      sb.writeln('PRODUK TERLARIS:');
      int rank = 1;
      for (final p in report.topProducts) {
        sb.writeln(rightAlign(rank.toString() + '. ' + p.productName, p.quantity.toString() + ' pcs'));
        sb.writeln(rightAlign('   Total', formatNumber(p.totalAmount)));
        rank++;
      }
      sb.writeln('--------------------------------');
    }
    sb.writeln('Dicetak: ' + DateTime.now().toString().substring(0, 16));
    return sb.toString();
  }

  /// Generate teks polos struk (padanan generateRawText — untuk Copy & RawBT).
  String generateRawText(Transaction t, String size) {
    final maxChars = size == '80mm' ? 48 : 32;
    final lineDash = '-' * maxChars;
    final out = <String>[];

    String centerText(String text) {
      final spaces = ((maxChars - text.length) / 2).floor().clamp(0, maxChars);
      return ' ' * spaces + text;
    }

    String rightAlign(String label, String value) {
      final padding = (maxChars - label.length - value.length).clamp(
        1,
        maxChars,
      );
      return label + ' ' * padding + value;
    }

    List<String> wrapText(String text) {
      final lines = <String>[];
      var currentLine = '';
      final words = text.split(' ');
      for (final word in words) {
        if ((currentLine + word).length > maxChars) {
          if (currentLine.isNotEmpty) lines.add(currentLine.trim());
          currentLine = word + ' ';
        } else {
          currentLine += word + ' ';
        }
      }
      if (currentLine.isNotEmpty) lines.add(currentLine.trim());
      return lines;
    }

    out.add(centerText('WARUNG LUPI'));
    out.add(centerText('Ke pasar membeli semangka'));
    out.add(centerText('Jangan lupa mampir ke Lupi'));
    out.add(lineDash);
    out.add('No   : ${t.transactionNumber}');
    out.add('Tgl  : ${formatDateShort(t.transactionDate)}');
    out.add('Plg  : ${t.customer?.name ?? 'Umum'}');
    out.add(lineDash);

    // Items (penambahan) — tambahan dulu, potongan terpisah (padanan web)
    final split = splitItems(t.items);
    for (final item in split.adds) {
      final name = (item.description != null && item.description!.isNotEmpty)
          ? '${item.productName} - ${item.description}'
          : item.productName;
      out.addAll(wrapText(name));
      out.add(
        rightAlign(
          '${item.quantity} x ${formatNumber(item.unitPrice)}',
          formatNumber(item.subtotal),
        ),
      );
    }

    // Potongan (item minus)
    if (split.deductions.isNotEmpty) {
      out.add(lineDash);
      out.add(centerText('POTONGAN'));
      for (final item in split.deductions) {
        final name = (item.description != null && item.description!.isNotEmpty)
            ? '${item.productName} - ${item.description}'
            : item.productName;
        out.addAll(wrapText(name));
        out.add(rightAlign('', '-${formatNumber(item.subtotal.abs())}'));
      }
    }

    out.add(lineDash);
    if (split.deductions.isNotEmpty) {
      out.add(rightAlign('Sebelum Potongan', formatNumber(split.totalBefore)));
    }
    out.add(rightAlign('TOTAL', formatNumber(t.totalAmount)));

    if (t.notes != null && t.notes!.isNotEmpty) {
      out.add('\nCatatan: ${t.notes}');
    }
    out.add('');
    out.add(centerText('Terima kasih sudah belanja'));
    out.add(centerText('Semoga puas di hati'));

    return out.join('\n');
  }
}

/// Perangkat printer Bluetooth Classic (paired) — dipakai UI Pengaturan.
class PrinterDevice {
  final String name;
  final String mac;

  const PrinterDevice({required this.name, required this.mac});

  String get displayName => name.isNotEmpty ? name : mac;
}

class PrinterException implements Exception {
  final String message;
  PrinterException(this.message);

  @override
  String toString() => message;
}
