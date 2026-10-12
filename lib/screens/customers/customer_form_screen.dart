import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../repositories/repository_factory.dart';
import '../../widgets/widgets.dart';

/// Form Pelanggan — meniru `pages/customers/CustomerForm.jsx`.
/// Nama wajib, No HP & Catatan opsional; error validasi per-field dari server.
class CustomerFormScreen extends StatefulWidget {
  final int? customerId;

  const CustomerFormScreen({super.key, this.customerId});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _phone = TextEditingController();
  late final TextEditingController _notes = TextEditingController();

  bool _isEdit = false;
  bool _fetchLoading = false;
  bool _submitLoading = false;
  String? _serverError;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.customerId != null;
    if (_isEdit) {
      _fetch();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _fetchLoading = true;
      _serverError = null;
    });
    try {
      final repo = RepositoryFactory.customerRepository();
      final c = await repo.show(widget.customerId!);
      if (!mounted) return;
      _name.text = c.name;
      _phone.text = c.phone ?? '';
      _notes.text = c.notes ?? '';
      setState(() => _fetchLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = 'Gagal memuat data pelanggan.';
        _fetchLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _serverError = null;
      _successMsg = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitLoading = true);
    try {
      final prov = context.read<CustomerProvider>();
      await prov.save(
        id: widget.customerId,
        name: _name.text,
        phone: _phone.text.isEmpty ? null : _phone.text,
        notes: _notes.text.isEmpty ? null : _notes.text,
      );
      if (!mounted) return;
      setState(() {
        _successMsg = _isEdit
            ? 'Data pelanggan berhasil diperbarui.'
            : 'Pelanggan baru berhasil ditambahkan.';
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = 'Gagal menyimpan data. Periksa kembali.';
      });
    } finally {
      if (mounted) setState(() => _submitLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan'),
      ),
      body: _fetchLoading
          ? const LoadingState(text: 'Memuat data...')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_serverError != null) InlineMessage(_serverError!),
                      if (_successMsg != null)
                        InlineMessage(_successMsg!, isError: false),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              FormField2(
                                label: 'Nama Pelanggan',
                                required: true,
                                child: TextFormField(
                                  controller: _name,
                                  decoration: const InputDecoration(
                                    hintText: 'Contoh: Budi Santoso',
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Nama pelanggan wajib diisi.'
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FormField2(
                                label: 'No. HP',
                                child: TextFormField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    hintText: 'Contoh: 08123456789',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              FormField2(
                                label: 'Catatan',
                                child: TextFormField(
                                  controller: _notes,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    hintText: 'Catatan opsional...',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlineButton(
                                    label: 'Batal',
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                  const SizedBox(width: 12),
                                  DarkButton(
                                    label: _isEdit
                                        ? (_submitLoading
                                              ? 'Menyimpan...'
                                              : 'Simpan')
                                        : (_submitLoading
                                              ? 'Menambahkan...'
                                              : 'Tambah'),
                                    loading: _submitLoading,
                                    onPressed: _submit,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Field wrapper konsisten (padanan komponen Field di CustomerForm.jsx).
class FormField2 extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;

  const FormField2({
    super.key,
    required this.label,
    this.required = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: AppColors.dangerText)),
              ],
            ],
          ),
        ),
        child,
      ],
    );
  }
}
