import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../providers/repositories.dart';
import '../utils/format.dart';
import '../widgets/widgets.dart';
import 'bon/bon_create_screen.dart';
import 'bon/bon_detail_screen.dart';
import 'bon/bon_list_screen.dart';
import 'customers/customer_form_screen.dart';
import 'expenses/expense_list_screen.dart';
import 'products/product_list_screen.dart';
import '../core/storage/prefs.dart';
import 'reports/sales_report_screen.dart';
import 'settings/settings_screen.dart';

/// Dashboard — meniru `pages/Dashboard.jsx` v2 (sky-blue, border-first).
/// Sapaan → focal "Penjualan hari ini" → Aksi cepat → list transaksi terbaru.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _savedPrinter = '';

  @override
  void initState() {
    super.initState();
    _checkPrinter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DashboardProvider>().load();
    });
  }

  Future<void> _checkPrinter() async {
    final name = await Prefs.getPrinterName();
    if (mounted) setState(() => _savedPrinter = name);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  String _todayLabel() {
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final n = DateTime.now();
    return '${days[n.weekday - 1]}, ${n.day} ${months[n.month - 1]} ${n.year}';
  }

  void _openBuatBon() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BonCreateScreen()));
  }

  void _openDetail(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BonDetailScreen(transactionId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();

    return RefreshIndicator(
      color: AppColors.brand600,
      onRefresh: () => context.read<DashboardProvider>().load(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sapaan — bukan headline landing page
            Text(
              _greeting(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _todayLabel(),
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                _checkPrinter();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _savedPrinter.isNotEmpty ? AppColors.brand50 : AppColors.chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _savedPrinter.isNotEmpty ? AppColors.brand200 : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.print_outlined,
                      size: 14,
                      color: _savedPrinter.isNotEmpty ? AppColors.brand700 : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _savedPrinter.isNotEmpty
                          ? 'Printer: ' + _savedPrinter
                          : 'Printer thermal belum diatur (ketuk untuk atur)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _savedPrinter.isNotEmpty ? AppColors.brand700 : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (dash.loading && dash.data == null)
              const LoadingState(text: 'Memuat dashboard...')
            else if (dash.error != null && dash.data == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InlineMessage(dash.error!),
                  TextButton(
                    onPressed: () => context.read<DashboardProvider>().load(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand600,
                    ),
                    child: const Text('Coba lagi'),
                  ),
                ],
              )
            else if (dash.data != null) ...[
              _FocalToday(data: dash.data!),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(height: 1),
              ),
              _QuickActions(onCreate: _openBuatBon),
              const SizedBox(height: 28),
              _RecentBon(recent: dash.data!.recent, onTap: _openDetail),
            ] else
              const SizedBox(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Focal point: penjualan hari ini — angka besar; tenang bila belum ada.
class _FocalToday extends StatelessWidget {
  final DashboardData data;
  const _FocalToday({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Penjualan hari ini',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        if (data.totalHariIni > 0)
          Text(
            formatRupiah(data.totalHariIni),
            style: const TextStyle(
              fontSize: 32,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColors.textMain,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          )
        else
          const Text(
            'Belum ada penjualan hari ini.',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${data.bonHariIni} transaksi',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const _Dot(),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
                children: [
                  const TextSpan(text: 'Lunas hari ini '),
                  TextSpan(
                    text: formatRupiah(data.lunasHariIni),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: data.lunasHariIni > 0
                          ? AppColors.successText
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (data.masihHutang > 0) ...[
              const _Dot(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BonListScreen()),
                ),
                child: Text(
                  'Sisa hutang ${formatRupiah(data.masihHutang)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFFC4C9D0),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            // Padanan web: link "Pengeluaran RpX" → /pengeluaran (bila ada).
            if (data.pengeluaranHariIni > 0) ...[
              const _Dot(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ExpenseListScreen()),
                ),
                child: Text(
                  'Pengeluaran ${formatRupiah(data.pengeluaranHariIni)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFFC4C9D0),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) =>
      const Text('·', style: TextStyle(fontSize: 13, color: Color(0xFF98A2B3)));
}

/// Aksi cepat — teks kecil, bukan giant cards (padanan web v2).
class _QuickActions extends StatelessWidget {
  final VoidCallback onCreate;
  const _QuickActions({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aksi cepat',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionChip(label: 'Buat Bon', primary: true, onTap: onCreate),
            _ActionChip(
              label: 'Tambah Item',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProductListScreen()),
              ),
            ),
            _ActionChip(
              label: 'Tambah Pelanggan',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
              ),
            ),
            _ActionChip(
              label: 'Laporan Penjualan',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesReportScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.brand600 : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: primary ? null : Border.all(color: AppColors.borderStrong),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: primary ? Colors.white : AppColors.textMain,
          ),
        ),
      ),
    );
  }
}

/// Transaksi terbaru — list polos + divider, tanpa card per baris.
class _RecentBon extends StatelessWidget {
  final List<TransactionSummary> recent;
  final ValueChanged<int> onTap;

  const _RecentBon({required this.recent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Transaksi terbaru',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BonListScreen())),
              child: const Text(
                'Lihat semua',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brand600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: recent.isEmpty
              ? EmptyState(
                  title: 'Belum ada transaksi',
                  subtitle: 'Bon yang dibuat akan muncul di sini.',
                  action: BrandButton(
                    label: 'Buat Bon',
                    icon: Icons.add,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BonCreateScreen(),
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < recent.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      InkWell(
                        onTap: () => onTap(recent[i].id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  recent[i].customerName ?? 'Umum',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textMain,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                recent[i].transactionDate,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 12),
                              recent[i].status == 'draft'
                                  ? StatusBadge.bonStatus('draft')
                                  : StatusBadge.payment(
                                      recent[i].paymentStatus ?? 'unpaid',
                                    ),
                              const SizedBox(width: 10),
                              Text(
                                formatRupiah(recent[i].totalAmount),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMain,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
