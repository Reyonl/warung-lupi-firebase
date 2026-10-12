import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/format.dart';
import '../../utils/promo.dart';
import '../../widgets/widgets.dart';
import 'bon_detail_screen.dart';

/// Buat/Edit Bon — meniru `pages/transactions/CreateTransaction.jsx`.
///
/// Alur bisnis yang dipertahankan 1:1:
/// 1. Header (pelanggan + tanggal + catatan) → tombol "Mulai Input Catatan"
///    (POST /transactions → draft). Setelah tersimpan, pelanggan/tanggal terkunci.
/// 2. Tambah item: pilih produk (atau "+ Input Manual / Item Lain"), keterangan,
///    qty, harga. Subtotal dihitung otomatis + **promo** (gorengan 3→5000,
///    donat/nagasari/lemper/jajanan 2→5000).
/// 3. Status pembayaran (Sudah Dibayar / Berhutang).
/// 4. "Simpan Bon" (disabled bila 0 item) → status completed → ke Detail.
class BonCreateScreen extends StatefulWidget {
  final int? editTransactionId;
  const BonCreateScreen({super.key, this.editTransactionId});

  @override
  State<BonCreateScreen> createState() => _BonCreateScreenState();
}

class _BonCreateScreenState extends State<BonCreateScreen> {
  // Header form
  int? _customerId;
  DateTime _transactionDate = DateTime.now();
  final _notesCtrl = TextEditingController();

  // Item form
  Product? _formItem;
  bool _isManualItem = false;
  final _manualNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  final _qtyFocusNode = FocusNode();
  int _formSubtotal = 0;
  int? _editingItemId;

  String? _error;
  bool _loadingRef = false;

  /// Sedang menyimpan/menyelesaikan bon. Dipakai untuk menonaktifkan tombol
  /// "Simpan Bon" agar tidak terkirim dua kali (mencegah bon duplikat) dan
  /// memberi umpan balik "Menyimpan..." kepada pengguna.
  bool _savingBon = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final prov = context.read<BonDraftProvider>();
    final custProv = context.read<CustomerProvider>();
    final prodProv = context.read<ProductProvider>();

    // Mode buat baru: buang draft yang tertahan di memori supaya form tidak
    // mewarisi pelanggan/tanggal/item dari bon sebelumnya (bug: "Buat Bon"
    // selalu memakai ulang draft terakhir).
    if (widget.editTransactionId == null && prov.hasDraft) {
      prov.startNew();
      // Draft lama tetap tersimpan di server (status "draft") dan bisa
      // dilanjutkan dari Riwayat Bon → Edit.
      if (mounted) {
        showToast(
          context,
          'Bon sebelumnya belum diselesaikan. Draft tersimpan di Riwayat Bon.',
        );
      }
    }

    // Muat referensi (pelanggan aktif & produk aktif) — sama dgn Promise.all di React
    _loadingRef = true;
    setState(() {});
    try {
      await Future.wait([
        custProv.load(),
        prodProv.loadCategories(),
        prodProv.load(),
      ]);
    } catch (_) {}
    _loadingRef = false;
    if (mounted) setState(() {});

    // Mode edit: muat transaksi
    final editId = widget.editTransactionId;
    if (editId != null) {
      await prov.loadExisting(editId);
      if (prov.error != null && mounted) {
        setState(() => _error = prov.error);
      }
      if (mounted) {
        setState(() {
          _customerId = prov.customerId;
          _notesCtrl.text = prov.notes;
          try {
            _transactionDate = DateTime.parse(prov.transactionDate);
          } catch (_) {}
        });
      }
    } else if (prov.transactionId != null && prov.headerSaved) {
      // Sudah ada draft (mis. kembali dari layar detail atau perpindahan tab):
      // pulihkan header DAN form item agar tidak tertinggal state edit lama.
      if (mounted) {
        setState(() {
          _customerId = prov.customerId;
          _notesCtrl.text = prov.notes;
          try {
            _transactionDate = DateTime.parse(prov.transactionDate);
          } catch (_) {}
          // _editingItemId harus dikosongkan setiap kali layar dibangun ulang;
          // kalau tidak, form item bisa dalam mode "Edit Item" dengan id item
          // dari sesi sebelumnya.
          _editingItemId = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _manualNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  // ---- Header ----
  Future<void> _saveHeader() async {
    final prov = context.read<BonDraftProvider>();
    if (_customerId == null) {
      setState(() => _error = 'Pelanggan dan tanggal wajib diisi.');
      return;
    }
    setState(() => _error = null);
    prov.customerId = _customerId;
    prov.transactionDate = toInputDate(_transactionDate);
    prov.notes = _notesCtrl.text;
    final err = await prov.saveHeader();
    if (err == null && mounted) {
      // setelah tersimpan, pelanggan/tanggal terkunci (headerSaved=true)
      setState(() {});
    } else if (err != null && mounted) {
      // Tampilkan pesan asli dari ApiClient/Laravel, bukan pesan generik.
      setState(() => _error = err);
    }
  }

  Future<void> _updatePaymentStatus(String status) async {
    final err = await context.read<BonDraftProvider>().updatePaymentStatus(
      status,
    );
    if (!mounted) return;
    setState(() {});
    if (err != null) showToast(context, err, error: true);
  }

  // ---- Item ----
  /// Parse harga dari teks terformat (mis. "-9.000" → -9000).
  /// Padanan `handlePriceChange` di website (negative = potongan).
  int _priceValue() {
    final raw = _priceCtrl.text.replaceAll('.', '');
    final clean = sanitizePriceInput(raw);
    final parsed = int.tryParse(clean.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
    return clean.startsWith('-') ? -parsed.abs() : parsed;
  }

  void _handlePriceChange(String raw) {
    // sanitasi harga — polanya sama dengan handlePriceChange di CreateTransaction.jsx
    var clean = sanitizePriceInput(raw.replaceAll('.', ''));
    if (clean == '') clean = '0';
    final parsed = int.tryParse(clean.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final negative = clean.startsWith('-');
    final shown = negative ? '-$parsed' : '$parsed';
    _priceCtrl.value = TextEditingValue(
      text: formatPriceDisplay(shown.isEmpty ? '0' : shown),
      selection: TextSelection.collapsed(offset: _priceCtrl.text.length),
    );
    setState(() => _formSubtotal = _calcSubtotal());
  }

  int _calcSubtotal() {
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final price = _priceValue();
    final name = _isManualItem ? _manualNameCtrl.text : (_formItem?.name ?? '');
    return calculatePromoSubtotal(name, qty, price);
  }

  void _onItemFieldsChanged() {
    setState(() => _formSubtotal = _calcSubtotal());
  }

  Future<void> _addItem() async {
    final prov = context.read<BonDraftProvider>();
    if (prov.transactionId == null) {
      setState(() => _error = 'Simpan header bon terlebih dahulu.');
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final price = _priceValue();
    final name = _isManualItem ? _manualNameCtrl.text.trim() : _formItem?.name;

    if (name == null ||
        name.isEmpty ||
        qty <= 0 ||
        _priceCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Item, Qty, dan Harga harus valid.');
      return;
    }

    setState(() => _error = null);
    final sub = calculatePromoSubtotal(name, qty, price);

    String? err;
    if (_editingItemId != null) {
      err = await prov.updateItem(
        _editingItemId!,
        productId: _isManualItem ? null : _formItem?.id,
        productName: name,
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        quantity: qty,
        unit: _formItem?.unit ?? 'pcs',
        unitPrice: price,
        subtotal: sub,
      );
    } else {
      err = await prov.addItem(
        productId: _isManualItem ? null : _formItem?.id,
        productName: name,
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        quantity: qty,
        unit: _formItem?.unit ?? 'pcs',
        unitPrice: price,
        subtotal: sub,
      );
    }

    if (err == null) {
      if (mounted) {
        _resetItemForm();
        setState(() {});
      }
    } else if (mounted) {
      setState(() => _error = err);
    }
  }

  void _resetItemForm() {
    setState(() {
      _formItem = null;
      _isManualItem = false;
      _editingItemId = null;
      _manualNameCtrl.clear();
      _descriptionCtrl.clear();
      _qtyCtrl.text = '1';
      _priceCtrl.clear();
      _formSubtotal = 0;
    });
  }

  void _handleEditItem(TransactionItem item) {
    final prodProv = context.read<ProductProvider>();
    setState(() {
      _editingItemId = item.id;
      if (item.productId != null) {
        _isManualItem = false;
        _formItem =
            prodProv.products
                .where((p) => p.id == item.productId)
                .firstOrNull ??
            Product(
              id: item.productId!,
              name: item.productName,
              defaultPrice: item.unitPrice,
              unit: item.unit,
              isActive: true,
            );
      } else {
        _isManualItem = true;
        _manualNameCtrl.text = item.productName;
        _formItem = null;
      }
      _descriptionCtrl.text = item.description ?? '';
      _qtyCtrl.text = item.quantity.toString();
      _priceCtrl.text = item.unitPrice.toString();
      _formSubtotal = item.subtotal;
    });
  }

  Future<void> _removeItem(int itemId) async {
    final prov = context.read<BonDraftProvider>();
    final err = await prov.removeItem(itemId);
    if (err != null && mounted) showToast(context, err, error: true);
    if (mounted) setState(() {});
  }

  Future<void> _finalizeBon() async {
    if (_savingBon) return; // cegah double-submit → bon duplikat
    final prov = context.read<BonDraftProvider>();
    setState(() {
      _savingBon = true;
      _error = null;
    });
    final err = await prov.finalizeBon();
    if (!mounted) return;
    setState(() => _savingBon = false);
    if (err == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BonDetailScreen(
            transactionId: prov.transactionId!,
            // Urutan drag & drop di layar ini dibawa ke Detail supaya preview,
            // cetak thermal, PDF, PNG, copy, dan RawBT memakai urutan pilihan
            // pengguna (backend tidak menyimpan urutan).
            customItemOrder: prov.itemOrderIds,
          ),
        ),
      );
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<BonDraftProvider>();
    final custProv = context.watch<CustomerProvider>();
    final prodProv = context.watch<ProductProvider>();

    final isEdit = widget.editTransactionId != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(isEdit ? 'Edit Bon' : 'Buat Bon')),
      body:
          _loadingRef &&
              !prov.headerSaved &&
              custProv.customers.isEmpty &&
              custProv.error == null
          ? const LoadingState(text: 'Memuat...')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) InlineMessage(_error!),

                      // Kegagalan memuat referensi (pelanggan/item) — tanpa ini
                      // pengguna hanya melihat dropdown kosong tanpa penjelasan.
                      if (custProv.error != null)
                        InlineMessage('Pelanggan: ${custProv.error!}'),
                      if (prodProv.error != null)
                        InlineMessage('Item: ${prodProv.error!}'),

                      // ---- 1. Header Section ----
                      _HeaderCard(
                        customerId: _customerId,
                        customers: custProv.customers,
                        savedCustomerId: prov.customerId,
                        savedCustomerName: prov.customerName,
                        date: _transactionDate,
                        headerSaved: prov.headerSaved,
                        onCustomerChanged: (id) =>
                            setState(() => _customerId = id),
                        onDateChanged: (d) =>
                            setState(() => _transactionDate = d),
                        onSaveHeader: _saveHeader,
                        saving: prov.loading,
                      ),

                      if (prov.headerSaved) ...[
                        const Divider(height: 40),

                        // ---- 2. Form Input Item ----
                        Text(
                          _editingItemId != null
                              ? 'Edit Item'
                              : 'Tambah Catatan',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ItemFormCard(
                          formItem: _formItem,
                          isManualItem: _isManualItem,
                          products: prodProv.products,
                          qtyCtrl: _qtyCtrl,
                          priceCtrl: _priceCtrl,
                          qtyFocusNode: _qtyFocusNode,
                          manualNameCtrl: _manualNameCtrl,
                          descriptionCtrl: _descriptionCtrl,
                          subtotal: _formSubtotal,
                          editingItemId: _editingItemId,
                          onItemChanged: _onItemFieldsChanged,
                          onPriceChanged: _handlePriceChange,
                          onSelectProduct: (p) {
                            setState(() {
                              _formItem = p;
                              _isManualItem = false;
                              _qtyCtrl.text = '1';
                              _priceCtrl.text = formatPriceDisplay(
                                p.defaultPrice.toString(),
                              );
                              _formSubtotal = _calcSubtotal();
                              FocusScope.of(context)
                                  .requestFocus(_qtyFocusNode);
                            });
                          },
                          onSelectManual: () {
                            setState(() {
                              _isManualItem = true;
                              _formItem = null;
                              _priceCtrl.clear();
                              _formSubtotal = 0;
                            });
                          },
                          onClearItem: () {
                            setState(() {
                              _formItem = null;
                              _isManualItem = false;
                              _manualNameCtrl.clear();
                              _priceCtrl.clear();
                              _qtyCtrl.text = '1';
                              _formSubtotal = 0;
                            });
                          },
                          onCancelManual: () {
                            setState(() {
                              _isManualItem = false;
                              _manualNameCtrl.clear();
                            });
                          },
                          onAddItem: _addItem,
                          onCancelEdit: _resetItemForm,
                        ),
                        const Divider(height: 40),

                        // ---- 3. Daftar Catatan ----
                        const Text(
                          'Daftar Catatan',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (prov.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'Belum ada item ditambahkan.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.gray500,
                              ),
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: prov.orderedItems.length,
                            onReorder: prov.moveItem,
                            itemBuilder: (context, index) {
                              final item = prov.orderedItems[index];
                              return KeyedSubtree(
                                key: ValueKey(item.id),
                                child: _ItemRow(
                                  item: item,
                                  editing: _editingItemId == item.id,
                                  onEdit: () => _handleEditItem(item),
                                  onDelete: () => _removeItem(item.id),
                                ),
                              );
                            },
                          ),

                        const Divider(height: 40),

                        // ---- 4. Total & Status Pembayaran ----
                        _TotalCard(
                          totalAmount: prov.totalAmount,
                          items: prov.orderedItems,
                          paymentStatus: prov.paymentStatus,
                          onPaymentStatus: _updatePaymentStatus,
                          onEditItem: _handleEditItem,
                          onDeleteDeduction: _removeItem,
                        ),

                        // ---- 5. Action ----
                        const SizedBox(height: 16),
                        BrandButton(
                          label: _savingBon ? 'Menyimpan...' : 'Simpan Bon',
                          loading: _savingBon,
                          onPressed: prov.items.isEmpty ? null : _finalizeBon,
                          expand: true,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ============================ Header ============================
class _HeaderCard extends StatelessWidget {
  final int? customerId;
  final List<Customer> customers;

  /// Pelanggan yang tersimpan di backend (untuk bon yang sudah tersimpan).
  final int? savedCustomerId;
  final String savedCustomerName;
  final DateTime date;
  final bool headerSaved;
  final ValueChanged<int?> onCustomerChanged;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onSaveHeader;
  final bool saving;

  const _HeaderCard({
    required this.customerId,
    required this.customers,
    required this.savedCustomerId,
    required this.savedCustomerName,
    required this.date,
    required this.headerSaved,
    required this.onCustomerChanged,
    required this.onDateChanged,
    required this.onSaveHeader,
    required this.saving,
  });

  /// Item dropdown pelanggan. Saat header sudah tersimpan, pelanggan lama
  /// yang sudah nonaktif tidak ada di `customers` (hanya pelanggan aktif yang
  /// dimuat) sehingga harus ditambahkan manual — kalau tidak, dropdown
  /// kehilangan nilainya dan menampilkan hint kosong.
  String? get _customerDisplayName {
    if (customerId == null) return null;
    final c = customers.where((x) => x.id == customerId).firstOrNull;
    if (c != null) return c.name;
    if (headerSaved && savedCustomerId == customerId) {
      return savedCustomerName.isEmpty
          ? 'Pelanggan #$savedCustomerId'
          : '$savedCustomerName (nonaktif)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pelanggan + Tanggal
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 520;
                final customerField = _FieldLabel(
                  label: 'Pelanggan',
                  child: CustomerSearchField(
                    initialCustomerId: customerId,
                    initialCustomerName: _customerDisplayName,
                    enabled: !headerSaved,
                    onSelected: (id) => onCustomerChanged(id),
                    onClear: () => onCustomerChanged(null),
                  ),
                );
                final dateField = _FieldLabel(
                  label: 'Tanggal',
                  child: InkWell(
                    onTap: headerSaved
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) onDateChanged(d);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.borderStrong),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(
                            toInputDate(date),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textMain,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.calendar_today,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                if (!isWide) {
                  return Column(
                    children: [
                      customerField,
                      const SizedBox(height: 14),
                      dateField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: customerField),
                    const SizedBox(width: 14),
                    Expanded(child: dateField),
                  ],
                );
              },
            ),
            if (!headerSaved) ...[
              const SizedBox(height: 14),
              DarkButton(
                label: 'Mulai Input Catatan',
                loading: saving,
                onPressed: onSaveHeader,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldLabel({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ============================ Item Form ============================
class _ItemFormCard extends StatelessWidget {
  final Product? formItem;
  final bool isManualItem;
  final List<Product> products;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final FocusNode qtyFocusNode;
  final TextEditingController manualNameCtrl;
  final TextEditingController descriptionCtrl;
  final int subtotal;
  final int? editingItemId;
  final VoidCallback onItemChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<Product> onSelectProduct;
  final VoidCallback onSelectManual;
  final VoidCallback onClearItem;
  final VoidCallback onCancelManual;
  final VoidCallback onAddItem;
  final VoidCallback onCancelEdit;

  const _ItemFormCard({
    required this.formItem,
    required this.isManualItem,
    required this.products,
    required this.qtyCtrl,
    required this.priceCtrl,
    required this.qtyFocusNode,
    required this.manualNameCtrl,
    required this.descriptionCtrl,
    required this.subtotal,
    required this.editingItemId,
    required this.onItemChanged,
    required this.onPriceChanged,
    required this.onSelectProduct,
    required this.onSelectManual,
    required this.onClearItem,
    required this.onCancelManual,
    required this.onAddItem,
    required this.onCancelEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item (searchable product field + manual)
            if (!isManualItem)
              _FieldLabel(
                label: 'Item',
                child: formItem != null
                    ? _SelectedItemTile(
                        product: formItem!,
                        onClear: onClearItem,
                      )
                    : ProductSearchField(
                        onSelected: onSelectProduct,
                        onSelectManual: onSelectManual,
                      ),
              )
            else
              _FieldLabel(
                label: 'Item (manual)',
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: manualNameCtrl,
                        autofocus: true,
                        onChanged: (_) => onItemChanged(),
                        decoration: const InputDecoration(
                          hintText: 'Nama item',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onCancelManual,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.gray500,
                      ),
                    ),
                  ],
                ),
              ),
            if (formItem != null && !isManualItem)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Ubah harga di bawah jika perlu (boleh minus untuk potongan).',
                  style: TextStyle(fontSize: 11, color: AppColors.gray500),
                ),
              ),
            const SizedBox(height: 14),
            // Keterangan
            _FieldLabel(
              label: 'Keterangan (opsional)',
              child: TextField(
                controller: descriptionCtrl,
                onChanged: (_) => onItemChanged(),
                decoration: const InputDecoration(hintText: 'Contoh: Tegar'),
              ),
            ),
            const SizedBox(height: 14),
            // Qty + Harga
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _FieldLabel(
                    label: 'Qty',
                    child: TextField(
                      controller: qtyCtrl,
                      focusNode: qtyFocusNode,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      onChanged: (_) => onItemChanged(),
                      decoration: const InputDecoration(hintText: '1'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _FieldLabel(
                    label: 'Harga',
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                      ],
                      textAlign: TextAlign.right,
                      onChanged: onPriceChanged,
                      decoration: InputDecoration(
                        hintText: '0',
                        helperText: 'Minus = potongan (mis. -9.000)',
                        helperStyle: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Subtotal otomatis (promo)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal (auto)',
                  style: TextStyle(
                    fontSize: 13,
                    color: isPromo() ? AppColors.brand700 : AppColors.textMuted,
                  ),
                ),
                Text(
                  formatRupiah(subtotal),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
              ],
            ),
            if (isPromo())
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Promo berlaku: gorengan 3@5000 • donat/nagasari/lemper/jajanan 2@5000',
                  style: TextStyle(fontSize: 11, color: AppColors.brand700),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: editingItemId != null
                      ? DarkButton(label: '✓ Update', onPressed: onAddItem)
                      : DarkButton(label: '+ Tambah', onPressed: onAddItem),
                ),
                if (editingItemId != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlineButton(
                      label: 'Batal Edit',
                      onPressed: onCancelEdit,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool isPromo() {
    final name = isManualItem ? manualNameCtrl.text : (formItem?.name ?? '');
    final lower = name.toLowerCase();
    return lower.contains('gorengan') ||
        ['donat', 'nagasari', 'lemper', 'jajanan'].any(lower.contains);
  }
}

// ============================ Selected Item Tile ============================
/// Kartu ringkas item yang sudah dipilih lewat [ProductSearchField].
/// Menampilkan nama + harga default + unit, dengan tombol [X] untuk ganti
/// item (kembali ke mode pencarian).
class _SelectedItemTile extends StatelessWidget {
  final Product product;
  final VoidCallback onClear;

  const _SelectedItemTile({required this.product, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.brand600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
          ),
          Text(
            '${formatRupiah(product.defaultPrice)} / ${product.unit}',
            style: const TextStyle(fontSize: 12, color: AppColors.gray600),
          ),
          IconButton(
            tooltip: 'Ganti item',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18, color: AppColors.gray500),
          ),
        ],
      ),
    );
  }
}

// ============================ Item Row ============================
class _ItemRow extends StatelessWidget {
  final TransactionItem item;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemRow({
    required this.item,
    required this.editing,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                if (item.description != null && item.description!.isNotEmpty)
                  Text(
                    item.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} x ${formatRupiah(item.unitPrice)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.gray600,
                  ),
                ),
                if (item.unitPrice < 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.dangerBorder),
                        ),
                        child: Text(
                          'POTONGAN',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.dangerText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatRupiah(item.unitPrice.abs()),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dangerText,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRupiah(item.subtotal),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onEdit,
                    child: Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: editing ? AppColors.brand600 : AppColors.gray600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: onDelete,
                    child: const Text(
                      'Hapus',
                      style: TextStyle(fontSize: 12, color: AppColors.gray600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================ Total ============================
class _TotalCard extends StatelessWidget {
  final int totalAmount;
  final List<TransactionItem> items;
  final String paymentStatus;
  final ValueChanged<String> onPaymentStatus;
  final ValueChanged<TransactionItem> onEditItem;
  final ValueChanged<int> onDeleteDeduction;

  const _TotalCard({
    required this.totalAmount,
    required this.items,
    required this.paymentStatus,
    required this.onPaymentStatus,
    required this.onEditItem,
    required this.onDeleteDeduction,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = paymentStatus == 'paid';
    final split = splitItems(items);
    final totalBefore = split.totalBefore;
    final totalDeduct = split.totalDeduct;
    final finalTotal = split.finalTotal;
    // Web computed finalTotal = totalBefore - totalDeduct == SUM(subtotal);
    // totalAmount dari server = SUM(subtotal) → sama. Tampilkan server value.
    final total = totalAmount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMain,
                  ),
                ),
                Text(
                  formatRupiah(total),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: total < 0
                        ? AppColors.dangerText
                        : AppColors.textMain,
                  ),
                ),
              ],
            ),
            if (split.hasDeductions) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              // Breakdown: Total Sebelum Potongan → Pengurangan → Total Setelah
              _BreakdownHeader(),
              const SizedBox(height: 4),
              _breakdownRow(
                'Total Sebelum Potongan',
                formatRupiah(totalBefore),
              ),
              const SizedBox(height: 10),
              _DeductionList(
                deductions: split.deductions,
                onEditItem: onEditItem,
                onDeleteDeduction: onDeleteDeduction,
              ),
              _breakdownRow(
                'Total Pengurangan',
                '-${formatRupiah(totalDeduct)}',
                color: AppColors.dangerText,
                bold: true,
              ),
              const SizedBox(height: 10),
              _breakdownRow(
                'Total Setelah Potongan',
                formatRupiah(finalTotal),
                color: finalTotal < 0
                    ? AppColors.dangerText
                    : AppColors.textMain,
                bold: true,
                large: true,
              ),
              const Divider(height: 24),
            ] else
              const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Status Pembayaran',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'paid',
                        label: Text('Sudah Dibayar'),
                        icon: Icon(Icons.check, size: 16),
                      ),
                      ButtonSegment(
                        value: 'unpaid',
                        label: Text('Berhutang'),
                        icon: Icon(Icons.warning_amber, size: 16),
                      ),
                    ],
                    selected: {paymentStatus},
                    onSelectionChanged: (s) => onPaymentStatus(s.first),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: isPaid
                          ? AppColors.successText
                          : AppColors.warningText,
                      selectedForegroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.borderStrong),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                isPaid
                    ? '✓ Transaksi ini sudah lunas'
                    : '⚠ Masih ada hutang yang belum dibayar',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isPaid ? AppColors.successText : AppColors.warningText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownRow(
    String label,
    String value, {
    Color color = AppColors.textMain,
    bool bold = false,
    bool large = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: large ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? AppColors.textMain : AppColors.gray600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: large ? 18 : 14,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label blok pengurangan (padanan web "Pengurangan").
class _BreakdownHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text(
      'Pengurangan',
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.dangerText,
      ),
    );
  }
}

/// Daftar baris potongan — tiap baris punya tombol Edit & Hapus.
class _DeductionList extends StatelessWidget {
  final List<TransactionItem> deductions;
  final ValueChanged<TransactionItem> onEditItem;
  final ValueChanged<int> onDeleteDeduction;

  const _DeductionList({
    required this.deductions,
    required this.onEditItem,
    required this.onDeleteDeduction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.dangerBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < deductions.length; i++) ...[
            if (i > 0) const Divider(height: 16, color: AppColors.dangerBorder),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    deductions[i].productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '-${formatRupiah(deductions[i].subtotal.abs())}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dangerText,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                InkWell(
                  onTap: () => onEditItem(deductions[i]),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.edit, size: 15, color: AppColors.gray600),
                  ),
                ),
                InkWell(
                  onTap: () => onDeleteDeduction(deductions[i].id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      size: 15,
                      color: AppColors.gray600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
