import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../repositories/repository_factory.dart';
import '../../services/printer_service.dart';
import '../../utils/format.dart';
import '../../widgets/thermal_receipt.dart';
import '../../widgets/widgets.dart';
import 'bon_create_screen.dart';

/// Detail Bon — meniru `pages/transactions/TransactionDetail.jsx`.
/// Preview struk, ganti ukuran 58/80mm, CETAK BLE, Export PDF,
/// Download PNG, Copy teks, RawBT (intent), Edit bon.
class BonDetailScreen extends StatefulWidget {
  final int transactionId;

  /// Urutan id item hasil drag & drop di layar Buat/Edit Bon.
  ///
  /// Backend tidak menyimpan urutan, jadi urutan ini dikirim eksplisit dari
  /// layar Buat/Edit → Detail saat finalisasi. Kosong = ikuti urutan server
  /// (by `id`), yang juga dipakai saat Detail dibuka dari Riwayat Bon.
  final List<int>? customItemOrder;

  const BonDetailScreen({
    super.key,
    required this.transactionId,
    this.customItemOrder,
  });

  @override
  State<BonDetailScreen> createState() => _BonDetailScreenState();
}

class _BonDetailScreenState extends State<BonDetailScreen> {
  Transaction? _t;
  bool _loading = true;
  String? _error;

  /// Ringkasan rokok bon ini (`GET /transactions/{id}/cigarettes`).
  /// null = belum dimuat ATAU bon tanpa rokok → section disembunyikan,
  /// persis `TransactionDetail.jsx` (`rokok && rokok.total_quantity > 0`).
  BonCigaretteSummary? _rokok;

  /// Transaksi yang dipakai SEMUA aksi (preview, cetak thermal, PDF, PNG,
  /// copy, RawBT) dengan urutan item hasil reorder manual bila ada.
  ///
  /// `_t` selalu menyimpan data apa adanya dari server; getter ini yang
  /// menerapkan urutan pilihan pengguna sehingga tidak ada jalur cetak yang
  /// lupa memakai urutan manual.
  Transaction? get _ordered =>
      _t?.withItemOrder(widget.customItemOrder ?? const []);

  String _thermalSize = '58mm';
  bool _isPrinting = false;
  String? _printError;

  final _receiptKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final size = await Prefs.getThermalSize();
    final printerName = await Prefs.getPrinterName();
    if (mounted && printerName.isEmpty) {
      _printError = 'Printer belum dikonfigurasi. Silakan buka menu Pengaturan → Printer Thermal terlebih dahulu.';
    }
    if (mounted) setState(() => _thermalSize = size);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Catatan: jangan panggil BonDraftProvider.refreshItems() di sini —
      // layar ini butuh transaksi yang sedang dilihat (widget.transactionId),
      // bukan draft yang tertahan di provider. Panggilan itu hanya menambah
      // 1 request HTTP yang tidak diperlukan.
      final t = await RepositoryFactory.transactionRepository().show(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _t = t;
        _loading = false;
      });
      // Ringkasan rokok dimuat terpisah (fire-and-forget, seperti web):
      // kegagalan diam saja → section tidak tampil.
      RepositoryFactory.cigaretteReportRepository()
          .bonSummary(widget.transactionId)
          .then((r) {
            if (mounted) setState(() => _rokok = r);
          })
          .catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.errorMessage(e, fallback: 'Bon tidak ditemukan.');
        _loading = false;
      });
    }
  }

  Future<void> _handleSizeChange(String size) async {
    setState(() => _thermalSize = size);
    await Prefs.setThermalSize(size);
  }

  Future<void> _handleCetak() async {
    final t = _ordered;
    if (t == null) return;
    setState(() => _printError = null);
    final printerName = await Prefs.getPrinterName();
    if (printerName.isEmpty) {
      setState(
        () => _printError = 'Printer belum dikonfigurasi. Silakan buka menu Pengaturan → Printer Thermal terlebih dahulu.',
      );
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final printerId = await Prefs.getPrinterId();
      await PrinterService.instance.printReceipt(
        transaction: t,
        thermalSize: _thermalSize,
        printerName: printerName,
        printerId: printerId,
      );
    } catch (e) {
      if (mounted) setState(() => _printError = 'Printer bermasalah: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _handleExportPDF() async {
    final t = _ordered;
    if (t == null) return;
    try {
      await Printing.layoutPdf(
        onLayout: (format) async {
          final doc = await _buildPdf(t, _thermalSize);
          return doc.save();
        },
        name: 'Nota_${t.transactionNumber}',
      );
    } catch (e) {
      if (mounted) showToast(context, 'Gagal export PDF: $e', error: true);
    }
  }

  Future<pw.Document> _buildPdf(Transaction t, String size) async {
    final doc = pw.Document();
    final maxChars = size == '80mm' ? 48 : 32;
    final is58 = size == '58mm';
    final pageWidth = is58 ? 58.0 * PdfPageFormat.mm : 80.0 * PdfPageFormat.mm;

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

    final dateStr = formatDateShort(t.transactionDate);
    final lineDash = '-' * maxChars;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          pageWidth,
          200 * PdfPageFormat.mm,
          marginAll: 0,
        ),
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              'WARUNG LUPI',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                font: pw.Font.courier(),
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'Ke pasar membeli semangka',
              style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'Jangan lupa mampir ke Lupi',
              style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            lineDash,
            style: pw.TextStyle(fontSize: 8, font: pw.Font.courier()),
          ),
          pw.Text(
            rightAlign('No.', t.transactionNumber),
            style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
          ),
          pw.Text(
            rightAlign('Tanggal', dateStr),
            style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
          ),
          pw.Text(
            rightAlign('Pelanggan', t.customer?.name ?? 'Umum'),
            style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
          ),
          pw.Text(
            lineDash,
            style: pw.TextStyle(fontSize: 8, font: pw.Font.courier()),
          ),
          ...splitItems(t.items).adds.expand((item) {
            final name =
                (item.description != null && item.description!.isNotEmpty)
                ? '${item.productName} - ${item.description}'
                : item.productName;
            final lines = wrapText(name);
            return [
              ...lines.map(
                (l) => pw.Text(
                  l,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    font: pw.Font.courier(),
                  ),
                ),
              ),
              pw.Text(
                rightAlign(
                  '${item.quantity} x ${formatNumber(item.unitPrice)}',
                  formatNumber(item.subtotal),
                ),
                style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
              ),
            ];
          }),
          if (splitItems(t.items).deductions.isNotEmpty) ...[
            pw.Text(
              lineDash,
              style: pw.TextStyle(fontSize: 8, font: pw.Font.courier()),
            ),
            pw.Text(
              centerText('POTONGAN'),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                font: pw.Font.courier(),
              ),
            ),
            ...splitItems(t.items).deductions.expand((item) {
              final name =
                  (item.description != null && item.description!.isNotEmpty)
                  ? '${item.productName} - ${item.description}'
                  : item.productName;
              final lines = wrapText(name);
              return [
                ...lines.map(
                  (l) => pw.Text(
                    l,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      font: pw.Font.courier(),
                    ),
                  ),
                ),
                pw.Text(
                  rightAlign(
                    '${item.quantity} x ${formatNumber(item.unitPrice)}',
                    '-${formatNumber(item.subtotal.abs())}',
                  ),
                  style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
                ),
              ];
            }),
          ],
          pw.Text(
            lineDash,
            style: pw.TextStyle(fontSize: 8, font: pw.Font.courier()),
          ),
          if (splitItems(t.items).deductions.isNotEmpty)
            pw.Text(
              rightAlign(
                'Sebelum Potongan',
                formatNumber(splitItems(t.items).totalBefore),
              ),
              style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
            ),
          pw.Text(
            rightAlign('TOTAL', formatNumber(t.totalAmount)),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              font: pw.Font.courier(),
            ),
          ),
          if (t.notes != null && t.notes!.isNotEmpty)
            pw.Text(
              '\nCatatan: ${t.notes}',
              style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
            ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              centerText('Terima kasih sudah belanja'),
              style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
            ),
          ),
          pw.Center(
            child: pw.Text(
              centerText('Semoga puas di hati'),
              style: pw.TextStyle(fontSize: 9, font: pw.Font.courier()),
            ),
          ),
        ],
      ),
    );
    return doc;
  }

  // Download PNG dari preview widget (padanan html2canvas)
  Future<void> _handleDownloadImage() async {
    final t = _ordered;
    if (t == null) return;
    try {
      final boundary =
          _receiptKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('render object');
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('byteData');
      final dir = await getApplicationDocumentsDirectory();
      final file = await File('${dir.path}/Nota_${t.transactionNumber}.png')
          .writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Nota ${t.transactionNumber}');
      if (mounted)
        showToast(context, 'Gambar nota berhasil disimpan & dibagikan.');
    } catch (e) {
      if (mounted)
        showToast(context, 'Gagal mendownload gambar nota.', error: true);
    }
  }

  // Copy teks struk (padanan handleCopy)
  Future<void> _handleCopy() async {
    final t = _ordered;
    if (t == null) return;
    final text = PrinterService.instance.generateRawText(t, _thermalSize);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showToast(
        context,
        'Teks struk berhasil disalin! Buka aplikasi Printer Bluetooth Anda lalu paste.',
      );
    }
  }

  // RawBT intent (padanan handleRawBT)
  Future<void> _handleRawBT() async {
    final t = _ordered;
    if (t == null) return;
    final text = PrinterService.instance.generateRawText(t, _thermalSize);
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse(
      'intent:$encoded#Intent;scheme=rawbt;package=ru.a402d.rawbtprinter;end;',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showToast(
          context,
          'Aplikasi RawBT tidak ditemukan. Instal dari Play Store.',
          error: true,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, 'Gagal membuka RawBT.', error: true);
    }
  }

  void _openEdit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BonCreateScreen(editTransactionId: widget.transactionId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Preview Bon'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingState(text: 'Memuat detail bon...');
    if (_error != null || _t == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Data tidak ditemukan',
                style: const TextStyle(
                  color: AppColors.dangerText,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('← Kembali ke Riwayat'),
              ),
            ],
          ),
        ),
      );
    }
    final t = _ordered!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Toolbar bawah: size toggle + aksi
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SizeToggle(
                    selected: _thermalSize,
                    onChanged: _handleSizeChange,
                  ),
                  OutlineButton(
                    label: 'Edit',
                    onPressed: _openEdit,
                    foreground: AppColors.gray600,
                  ),
                  // Download PNG
                  FilledButton(
                    onPressed: _handleDownloadImage,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warningBg,
                      foregroundColor: AppColors.warningText,
                    ),
                    child: const Text(
                      'Download',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  OutlineButton(
                    label: 'Export PDF',
                    onPressed: _handleExportPDF,
                  ),
                  // Copy & RawBT (hidden on small)
                  LayoutBuilder(
                    builder: (context, c) {
                      if (c.maxWidth < 430) return const SizedBox.shrink();
                      return Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _handleCopy,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.gray500,
                            ),
                            child: const Text(
                              'Copy',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          FilledButton(
                            onPressed: _handleRawBT,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.brand600,
                            ),
                            child: const Text(
                              'RawBT',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              if (_printError != null) ...[
                const SizedBox(height: 10),
                InlineMessage(_printError!),
              ],
              const SizedBox(height: 16),
              // Preview struk
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: ThermalReceipt(
                    transaction: t,
                    size: _thermalSize,
                    preview: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Tombol cetak utama
              BrandButton(
                label: _isPrinting ? 'MENCETAK...' : 'CETAK',
                loading: _isPrinting,
                onPressed: _isPrinting ? null : _handleCetak,
                expand: true,
              ),
              // Section Penjualan Rokok — hidden bila bon tidak punya rokok
              if (_rokok != null && _rokok!.totalQuantity > 0) ...[
                const SizedBox(height: 16),
                _RokokSummaryCard(rokok: _rokok!),
              ],
              // Aksi status pembayaran tidak ada di web (dipindah ke edit/create)
            ],
          ),
        ),
      ),
    );
  }
}

/// Card "Penjualan Rokok" pada detail bon — padanan v2 di
/// `TransactionDetail.jsx` (tersembunyi bila bon tidak punya rokok).
class _RokokSummaryCard extends StatelessWidget {
  final BonCigaretteSummary rokok;
  const _RokokSummaryCard({required this.rokok});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Penjualan Rokok',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Text(
                formatRupiah(rokok.totalAmount),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in rokok.items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.totalQuantity} × ${formatNumber(item.unitPrice ?? 0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    child: Text(
                      formatRupiah(item.totalSales),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '${rokok.totalQuantity} batang · ${rokok.items.length} item',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _SizeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['58mm', '80mm'].map((s) {
          final active = selected == s;
          return InkWell(
            onTap: () => onChanged(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: active ? AppColors.gray900 : Colors.white,
              child: Text(
                s,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
