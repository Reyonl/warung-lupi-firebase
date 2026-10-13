import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/format.dart';
import '../../widgets/widgets.dart';
import '../bon/bon_detail_screen.dart';
import 'customer_form_screen.dart';

/// Daftar Pelanggan — meniru `pages/customers/CustomerList.jsx`.
/// Search (debounce), filter Aktif/Semua (default Aktif), toggle aktif,
/// edit → navigasi, hapus → confirm dialog, klik nama → riwayat bon.
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final Debouncer _debouncer = Debouncer(350, () {});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CustomerProvider>().load();
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(Customer c) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Hapus Pelanggan',
      message:
          'Apakah Anda yakin ingin menghapus pelanggan "${c.name}"? '
          'Tindakan ini tidak dapat dibatalkan.',
    );
    if (ok == true && mounted) {
      final msg = await context.read<CustomerProvider>().delete(c);
      if (mounted) {
        showToast(
          context,
          msg!,
          error: msg != 'Pelanggan "${c.name}" berhasil dihapus.',
        );
      }
    }
  }

  Future<void> _toggleActive(Customer c) async {
    final prov = context.read<CustomerProvider>();
    final action = await prov.toggleActive(c);
    if (action != null && mounted) {
      showToast(context, 'Pelanggan "${c.name}" berhasil $action.');
    } else if (action == null && mounted) {
      showToast(
        context,
        prov.error ?? 'Gagal mengubah status pelanggan.',
        error: true,
      );
    }
  }

  void _openForm({int? id}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(customerId: id),
        settings: const RouteSettings(name: '/pelanggan/form'),
      ),
    );
  }

  void _showCustomerHistory(Customer c) {
    final future = context.read<CustomerProvider>().transactions(c.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Riwayat Bon: ${c.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: FutureBuilder<List<TransactionSummary>>(
                  future: future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const LoadingState(
                        text: 'Memuat riwayat bon...',
                      );
                    }
                    if (snap.hasError) {
                      return InlineMessage('Gagal memuat riwayat: ${snap.error}');
                    }
                    final list = snap.data ?? const [];
                    if (list.isEmpty) {
                      return const EmptyState(
                        title: 'Belum ada riwayat bon.',
                        subtitle:
                            'Pelanggan ini belum memiliki catatan transaksi.',
                      );
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final t = list[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            t.transactionNumber,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMain,
                            ),
                          ),
                          subtitle: Text(
                            formatDate(t.transactionDate),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatRupiah(t.totalAmount),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMain,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusBadge.payment(t.paymentStatus ?? 'unpaid'),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(this.context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    BonDetailScreen(transactionId: t.id),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<CustomerProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: PageHeader(
            title: 'Pelanggan',
            actions: [
              DarkButton(
                label: 'Tambah Pelanggan',
                icon: Icons.person_add_alt,
                onPressed: () => _openForm(),
              ),
            ],
          ),
        ),
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                onChanged: (v) {
                  // debounce 350ms — meniru `setTimeout(fetch, 350)` di React
                  _debouncer.run(
                    () => context.read<CustomerProvider>().doSearch(v),
                  );
                },
                decoration: const InputDecoration(
                  hintText: 'Cari nama pelanggan...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Aktif')),
                  ButtonSegment(value: false, label: Text('Semua')),
                ],
                selected: {prov.filterActive},
                onSelectionChanged: (s) =>
                    context.read<CustomerProvider>().setFilterActive(s.first),
                style: SegmentedButton.styleFrom(
                  foregroundColor: AppColors.textMain,
                  selectedForegroundColor: AppColors.textMain,
                  selectedBackgroundColor: AppColors.gray100,
                  side: const BorderSide(color: AppColors.borderStrong),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(prov)),
      ],
    );
  }

  Widget _buildBody(CustomerProvider prov) {
    if (prov.loading && prov.customers.isEmpty) {
      return const LoadingState(text: 'Memuat data...');
    }
    if (prov.error != null && prov.customers.isEmpty) {
      return InlineMessage(prov.error!);
    }
    if (prov.customers.isEmpty) {
      return const EmptyState(
        title: 'Tidak ada pelanggan ditemukan',
        subtitle: 'Sesuaikan kata kunci pencarian atau filter status.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => prov.load(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: prov.customers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, idx) {
          final c = prov.customers[idx];
          return _CustomerTile(
            customer: c,
            toggling: prov.togglingId == c.id,
            onTapHistory: () => _showCustomerHistory(c),
            onEdit: () => _openForm(id: c.id),
            onToggle: () => _toggleActive(c),
            onDelete: () => _confirmDelete(c),
          );
        },
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final bool toggling;
  final VoidCallback onTapHistory;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _CustomerTile({
    required this.customer,
    required this.toggling,
    required this.onTapHistory,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onTapHistory,
                  child: Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  customer.phone ?? '—',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          StatusBadge.active(isActive: customer.isActive),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'history') onTapHistory();
              if (v == 'edit') onEdit();
              if (v == 'toggle') onToggle();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'history', child: Text('Riwayat Bon')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(customer.isActive ? 'Nonaktifkan' : 'Aktifkan'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
            icon: const Icon(
              Icons.more_vert,
              size: 20,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
