import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/printer_service.dart';
import '../../utils/format.dart';
import '../../widgets/widgets.dart';

/// Preset rentang tanggal laporan.
class _Preset {
  final String label;
  final DateTime Function() from;
  final DateTime Function() to;
  const _Preset(this.label, this.from, this.to);
}

List<_Preset> _salesPresets() {
  final now = DateTime.now();
  DateTime shift(int days) => now.add(Duration(days: days));
  return [
    _Preset('Hari ini', () => now, () => now),
    _Preset('Kemarin', () => shift(-1), () => shift(-1)),
    _Preset('7 Hari', () => shift(-6), () => now),
    _Preset(
      'Bulan ini',
      () => DateTime(now.year, now.month, 1),
      () => now,
    ),
  ];
}

/// Layar Laporan Penjualan Detail & Rekap Shift (Material 3 Light Mode).
class SalesReportScreen extends StatefulWidget {
  final bool embedded;

  const SalesReportScreen({super.key, this.embedded = false});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  int _selectedPresetIndex = 0;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<SalesReportProvider>();
      if (!p.hasData) p.load();
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final p = context.read<SalesReportProvider>();
    final current = isFrom ? p.dateFrom : p.dateTo;
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedPresetIndex = -1);
    if (isFrom) {
      p.setDateRange(toInputDate(picked), p.dateTo);
    } else {
      p.setDateRange(p.dateFrom, toInputDate(picked));
    }
  }

  void _applyPreset(int index, _Preset preset) {
    setState(() => _selectedPresetIndex = index);
    context.read<SalesReportProvider>().setDateRange(
          toInputDate(preset.from()),
          toInputDate(preset.to()),
        );
  }

  Future<void> _handlePrintShift(SalesReportData data) async {
    setState(() => _isPrinting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final printerName = prefs.getString('printer_name') ?? '';
      final printerId = prefs.getString('printer_id') ?? '';
      final thermalSize = prefs.getString('thermal_size') ?? '58mm';

      if (printerName.isEmpty && printerId.isEmpty) {
        if (!mounted) return;
        showToast(
          context,
          'Printer belum dipilih. Atur printer di menu Pengaturan.',
        );
        return;
      }

      await PrinterService.instance.printShiftReport(
        report: data,
        thermalSize: thermalSize,
        printerName: printerName,
        printerId: printerId,
      );

      if (!mounted) return;
      showToast(context, 'Rekap shift berhasil dicetak ke printer.');
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Gagal mencetak: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _handleShareWhatsApp(SalesReportData data) async {
    final text = PrinterService.instance.generateShiftReportRawText(data);
    await Share.share(
      text,
      subject: 'Rekap Penjualan Warung Lupi (${data.dateFrom})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SalesReportProvider>();
    final presets = _salesPresets();

    final content = RefreshIndicator(
      color: AppColors.brand600,
      onRefresh: () => prov.load(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            const PageHeader(
              title: 'Laporan Penjualan Detail',
              subtitle:
                  'Rekapitulasi omset, laba bersih, diskon promo, & kas warung.',
            ),
            const SizedBox(height: 16),

            // Filter Presets & Date Picker
            _buildDateFilter(presets, prov),
            const SizedBox(height: 16),

            if (prov.loading && prov.report == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: LoadingState(text: 'Menghitung rekap penjualan...'),
              )
            else if (prov.error != null && prov.report == null)
              InlineMessage(prov.error!)
            else if (prov.report != null) ...[
              _buildKpiGrid(prov.report!),
              const SizedBox(height: 16),
              _buildPaymentBreakdown(prov.report!),
              const SizedBox(height: 16),
              _buildCategoryBreakdown(prov.report!),
              const SizedBox(height: 16),
              _buildTopProducts(prov.report!),
              const SizedBox(height: 24),
              _buildActionButtons(prov.report!),
            ],
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Penjualan Detail'),
      ),
      body: content,
    );
  }

  Widget _buildDateFilter(List<_Preset> presets, SalesReportProvider prov) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(presets.length, (idx) {
                final p = presets[idx];
                final isSelected = _selectedPresetIndex == idx;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(p.label),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.textMain,
                    ),
                    backgroundColor: AppColors.chipBg,
                    selectedColor: AppColors.brand600,
                    showCheckmark: false,
                    onSelected: (_) => _applyPreset(idx, p),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isFrom: true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            prov.dateFrom.isNotEmpty
                                ? prov.dateFrom
                                : 'Dari Tanggal',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMain,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('s/d',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isFrom: false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            prov.dateTo.isNotEmpty
                                ? prov.dateTo
                                : 'Sampai Tanggal',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMain,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(SalesReportData d) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Omset Kotor',
                value: formatRupiah(d.grossSales),
                subtitle: '${d.totalTransactions} transaksi bon',
                icon: Icons.payments_outlined,
                color: AppColors.brand600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Diskon Promo',
                value: formatRupiah(d.promoDiscounts),
                subtitle: 'Potongan bundle',
                icon: Icons.local_offer_outlined,
                color: const Color(0xFFE11D48),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Pengeluaran',
                value: formatRupiah(d.totalExpenses),
                subtitle: 'Beban operasional',
                icon: Icons.receipt_long_outlined,
                color: AppColors.warningText,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Profit Bersih',
                value: formatRupiah(d.netProfit),
                subtitle: 'Omset bersih - beban',
                icon: Icons.trending_up,
                color: AppColors.successText,
                isHighlight: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFFF0FDF4) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight ? AppColors.successBorder : AppColors.border,
          width: isHighlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isHighlight ? AppColors.successText : AppColors.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdown(SalesReportData d) {
    final total = (d.cashTotal + d.nonCashTotal + d.unpaidTotal);
    final double cashPct = total > 0 ? (d.cashTotal / total * 100) : 0;
    final double nonCashPct = total > 0 ? (d.nonCashTotal / total * 100) : 0;
    final double unpaidPct = total > 0 ? (d.unpaidTotal / total * 100) : 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: AppColors.textMain),
              SizedBox(width: 8),
              Text(
                'Metode Pembayaran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPaymentRow(
            label: 'Tunai (Cash)',
            amount: d.cashTotal,
            percentage: cashPct,
            color: AppColors.successText,
          ),
          const Divider(height: 16),
          _buildPaymentRow(
            label: 'QRIS / Non-Tunai',
            amount: d.nonCashTotal,
            percentage: nonCashPct,
            color: AppColors.brand600,
          ),
          const Divider(height: 16),
          _buildPaymentRow(
            label: 'Kasbon (Belum Lunas)',
            amount: d.unpaidTotal,
            percentage: unpaidPct,
            color: AppColors.warningText,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow({
    required String label,
    required int amount,
    required double percentage,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMain),
          ),
        ),
        Text(
          formatRupiah(amount),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.chipBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${percentage.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown(SalesReportData d) {
    if (d.categoryMetrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.category_outlined,
                  size: 16, color: AppColors.textMain),
              SizedBox(width: 8),
              Text(
                'Penjualan per Kategori',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...d.categoryMetrics.map((cat) {
            final double pct = cat.percentage.clamp(0, 100);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cat.categoryName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMain,
                        ),
                      ),
                      Text(
                        '${formatRupiah(cat.totalAmount)} (${cat.totalQty} pcs)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: AppColors.chipBg,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.brand600),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopProducts(SalesReportData d) {
    if (d.topProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star_outline, size: 16, color: AppColors.textMain),
              SizedBox(width: 8),
              Text(
                'Top 5 Produk Terlaris',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(d.topProducts.length, (idx) {
            final p = d.topProducts[idx];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: idx == 0 ? AppColors.brand100 : AppColors.chipBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: idx == 0
                            ? AppColors.brand700
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.productName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                  Text(
                    '${p.quantity} pcs',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatRupiah(p.totalAmount),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActionButtons(SalesReportData d) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isPrinting ? null : () => _handlePrintShift(d),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _isPrinting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print_outlined, size: 18),
            label: Text(
              _isPrinting ? 'Mencetak...' : 'Cetak Rekap Shift (58mm)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _handleShareWhatsApp(d),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.successText,
              side: const BorderSide(color: AppColors.successBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text(
              'Bagikan Laporan (WhatsApp)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
