import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/config/feature_flags.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../services/printer_service.dart';
import '../../widgets/widgets.dart';

/// Pengaturan — meniru `pages/settings/PrintSettings.jsx`.
/// - Server API (alamat backend Laravel yang sedang dipakai)
/// - Pilih / Pair printer Bluetooth Classic SPP (dari perangkat yang sudah paired/bonded)
/// - Tes Cetak
/// - Ukuran kertas default 58mm / 80mm (disimpan ke prefs)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _size = '58mm';
  String _printerName = '';
  String _printerId = '';
  bool _loadingPrefs = true;

  // Pairing (Bluetooth Classic paired devices)
  List<PrinterDevice> _available = [];
  bool _scanning = false;
  bool _pairing = false;
  String? _pairError;
  String? _pairSuccess;

  // Test print
  bool _testing = false;
  String? _testError;
  String? _testSuccess;

  // Server API
  final _serverCtrl = TextEditingController();
  bool _testingServer = false;
  String? _serverError;
  String? _serverSuccess;

  // Feature flags Firestore
  Map<String, bool?> _firestoreFlags = {};

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final size = await Prefs.getThermalSize();
    final name = await Prefs.getPrinterName();
    final id = await Prefs.getPrinterId();
    final server = await Prefs.getApiBaseUrl();
    final flags = await Prefs.getFirestoreFlags();
    if (!mounted) return;
    setState(() {
      _size = size;
      _printerName = name;
      _printerId = id;
      // Kosong = memakai default produksi (ditampilkan sebagai hint).
      _serverCtrl.text = server;
      _firestoreFlags = flags;
      _loadingPrefs = false;
    });
  }

  Future<void> _toggleFirestoreFlag(String key, bool val) async {
    await Prefs.setFirestoreFlag(key, val);
    await FeatureFlags.init();
    final flags = await Prefs.getFirestoreFlags();
    if (!mounted) return;
    setState(() => _firestoreFlags = flags);
    showToast(
      context,
      'Flag $key diubah menjadi ${val ? "Firestore" : "REST (Laravel)"}. Restart aplikasi untuk perubahan penuh.',
    );
  }

  /// Simpan alamat server. Kosong → kembali ke default produksi.
  Future<void> _saveServer() async {
    final raw = _serverCtrl.text.trim();
    setState(() {
      _serverError = null;
      _serverSuccess = null;
    });
    if (raw.isNotEmpty && Uri.tryParse(raw)?.hasScheme != true) {
      setState(
        () => _serverError = 'Alamat harus berupa URL lengkap, contoh: https://warunglupi.tplp004.com',
      );
      return;
    }
    // Jangan biarkan produksi turun ke HTTP polos tanpa disadari.
    if (raw.startsWith('http://') &&
        !raw.contains('localhost') &&
        !raw.contains('127.0.0.1') &&
        !RegExp(r'://\d+\.\d+\.\d+\.\d+').hasMatch(raw)) {
      final ok = await showConfirmDialog(
        context,
        title: 'Gunakan HTTP (tanpa HTTPS)?',
        message:
            'Alamat "$raw" memakai HTTP polos. Data bon akan dikirim tanpa enkripsi. Lanjutkan?',
        confirmLabel: 'Lanjutkan',
      );
      if (ok != true) return;
    }

    await Prefs.setApiBaseUrl(raw);
    ApiConfig.runtimeOverride = raw;
    ApiClient.instance.setBaseUrl(raw);
    if (!mounted) return;
    setState(() {
      _serverSuccess = raw.isEmpty
          ? 'Kembali ke server produksi: ${ApiClient.productionBaseUrl}'
          : 'Alamat server disimpan.';
    });
  }

  Future<void> _testServer() async {
    setState(() {
      _testingServer = true;
      _serverError = null;
      _serverSuccess = null;
    });
    final err = await ApiClient.ping();
    if (!mounted) return;
    setState(() {
      _testingServer = false;
      if (err == null) {
        _serverSuccess =
            'Terhubung ke ${ApiClient.activeBaseUrl} — server merespons.';
      } else {
        _serverError = err;
      }
    });
  }

  Future<void> _scanForPrinters() async {
    setState(() {
      _scanning = true;
      _pairError = null;
      _pairSuccess = null;
      _available = [];
    });
    try {
      // Printer thermal Bluetooth Classic harus sudah di-pair lewat
      // Pengaturan Android → Bluetooth. Kita ambil daftar perangkat paired.
      final paired = await PrinterService.instance.bondedPrinters();
      if (!mounted) return;
      if (paired.isEmpty) {
        setState(
          () => _pairError = 'Tidak ada perangkat Bluetooth yang terpasang (paired). Pasangkan printer Anda lewat Pengaturan Android → Bluetooth (PIN umumnya 0000 atau 1234), lalu tekan tombol ini lagi.',
        );
        return;
      }
      setState(() => _available = paired);
    } catch (e) {
      if (mounted)
        setState(() => _pairError = 'Gagal memuat printer: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pair(PrinterDevice device) async {
    setState(() {
      _pairing = true;
      _pairError = null;
      _pairSuccess = null;
    });
    try {
      final name = device.displayName;
      final id = device.mac;

      // Simpan ke prefs (padanan localStorage di web) — MAC sebagai ID.
      await Prefs.setPrinter(name, id);
      PrinterService.instance.setActivePrinter(name: name, mac: id);

      if (mounted) {
        setState(() {
          _printerName = name;
          _printerId = id;
          _available = [];
          _pairSuccess =
              'Printer $name berhasil disimpan sebagai Printer Utama!';
        });
      }
    } catch (e) {
      if (mounted)
        setState(() => _pairError = 'Gagal memilih printer: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _testPrint() async {
    setState(() {
      _testError = null;
      _testSuccess = null;
    });
    if (_printerName.isEmpty) {
      setState(() => _testError = 'Belum ada printer yang dikonfigurasi.');
      return;
    }
    setState(() => _testing = true);
    try {
      await PrinterService.instance.printTest(
        printerName: _printerName,
        printerId: _printerId,
      );
      if (mounted)
        setState(() => _testSuccess = 'Tes cetak berhasil dikirim ke printer!');
    } catch (e) {
      if (mounted)
        setState(
          () => _testError = 'Printer tidak dapat terhubung: ${e.toString()}',
        );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _changeSize(String v) async {
    setState(() => _size = v);
    await Prefs.setThermalSize(v);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pengaturan',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Konfigurasi aplikasi Warung Lupi.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              if (_loadingPrefs)
                const LoadingState(text: 'Memuat pengaturan...')
              else ...[
                _ServerCard(
                  controller: _serverCtrl,
                  activeUrl: ApiClient.activeBaseUrl,
                  productionUrl: ApiClient.productionBaseUrl,
                  isTesting: _testingServer,
                  error: _serverError,
                  success: _serverSuccess,
                  onSave: _saveServer,
                  onTest: _testServer,
                ),
                const SizedBox(height: 16),
                _PrinterCard(
                  printerName: _printerName,
                  printerId: _printerId,
                  available: _available,
                  scanning: _scanning,
                  pairing: _pairing,
                  pairError: _pairError,
                  pairSuccess: _pairSuccess,
                  testing: _testing,
                  testError: _testError,
                  testSuccess: _testSuccess,
                  onScan: _scanForPrinters,
                  onPair: _pair,
                  onTestPrint: _testPrint,
                ),
                const SizedBox(height: 16),
                _SizeCard(size: _size, onChanged: _changeSize),
                const SizedBox(height: 16),
                _FirestoreFlagsCard(
                  flags: _firestoreFlags,
                  onToggle: _toggleFirestoreFlag,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu konfigurasi server API — menampilkan alamat yang sedang dipakai dan
/// memungkinkan menggantinya tanpa build ulang (berguna untuk dev/testing).
class _ServerCard extends StatelessWidget {
  final TextEditingController controller;
  final String activeUrl;
  final String productionUrl;
  final bool isTesting;
  final String? error;
  final String? success;
  final VoidCallback onSave;
  final VoidCallback onTest;

  const _ServerCard({
    required this.controller,
    required this.activeUrl,
    required this.productionUrl,
    required this.isTesting,
    required this.error,
    required this.success,
    required this.onSave,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final isProd = activeUrl == productionUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SERVER API',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.gray800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  activeUrl.isEmpty ? '(relatif /api)' : activeUrl,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              StatusBadge(
                label: isProd ? 'Produksi' : 'Kustom',
                background: isProd ? AppColors.successBg : AppColors.gray100,
                foreground: isProd ? AppColors.successText : AppColors.gray800,
                border: isProd ? AppColors.successBorder : AppColors.gray200,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (error != null) InlineMessage(error!),
          if (success != null) InlineMessage(success!, isError: false),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Alamat server (kosongkan = produksi)',
              hintText: productionUrl,
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DarkButton(label: 'Simpan Alamat', onPressed: onSave),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlineButton(
                  label: isTesting ? 'Menguji...' : 'Tes Koneksi',
                  loading: isTesting,
                  onPressed: onTest,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Semua data (pelanggan, item, bon) dibaca & ditulis ke backend '
            'Laravel di atas — database yang sama dengan aplikasi web.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  final String printerName;
  final String printerId;
  final List<PrinterDevice> available;
  final bool scanning;
  final bool pairing;
  final String? pairError;
  final String? pairSuccess;
  final bool testing;
  final String? testError;
  final String? testSuccess;
  final VoidCallback onScan;
  final ValueChanged<PrinterDevice> onPair;
  final VoidCallback onTestPrint;

  const _PrinterCard({
    required this.printerName,
    required this.printerId,
    required this.available,
    required this.scanning,
    required this.pairing,
    required this.pairError,
    required this.pairSuccess,
    required this.testing,
    required this.testError,
    required this.testSuccess,
    required this.onScan,
    required this.onPair,
    required this.onTestPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRINTER THERMAL',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.gray800,
            ),
          ),
          const SizedBox(height: 16),
          if (pairError != null) InlineMessage(pairError!),
          if (pairSuccess != null) InlineMessage(pairSuccess!, isError: false),
          if (testError != null) InlineMessage(testError!),
          if (testSuccess != null) InlineMessage(testSuccess!, isError: false),

          // Printer utama
          const Text(
            'Printer Utama',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 8),
          if (printerName.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          printerName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          printerId.isEmpty
                              ? 'Konfigurasi tersimpan (tanpa alamat MAC)'
                              : printerId,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: testing ? null : onTestPrint,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand600,
                        side: const BorderSide(color: AppColors.brand600),
                      ),
                      child: Text(
                        testing ? 'Mencetak...' : 'Tes Cetak',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (printerName.isNotEmpty) const SizedBox(height: 8),

          // Pairing area
          if (printerName.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                border: Border.all(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text(
                    'Belum ada printer yang dikonfigurasi.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  BrandButton(
                    label: 'Pair / Pilih Printer',
                    onPressed: scanning ? null : onScan,
                    loading: scanning,
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlineButton(label: 'Ganti Printer', onPressed: onScan),
            ),

          if (available.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Printer Bluetooth Classic yang terpasang (paired) di HP ini:',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            ...available
                .take(8)
                .map(
                  (d) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.print,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    title: Text(
                      d.displayName,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(d.mac, style: const TextStyle(fontSize: 10)),
                    trailing: pairing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => onPair(d),
                            child: const Text(
                              'Pilih',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                  ),
                ),
            const SizedBox(height: 4),
            const Text(
              'Printer harus dipasangkan (paired) dulu lewat Pengaturan Android → Bluetooth. PIN umumnya 0000 atau 1234.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SizeCard extends StatelessWidget {
  final String size;
  final ValueChanged<String> onChanged;

  const _SizeCard({required this.size, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UKURAN KERTAS DEFAULT',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.gray800,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: size,
            isDense: true,
            items: const [
              DropdownMenuItem(value: '58mm', child: Text('58mm (Kecil)')),
              DropdownMenuItem(value: '80mm', child: Text('80mm (Besar)')),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Ukuran kertas yang akan digunakan otomatis saat Anda mencetak bon. Anda tetap dapat mengubahnya sementara saat melihat preview bon.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: DarkButton(
              label: 'Simpan Pengaturan',
              onPressed: () => showToast(
                context,
                'Pengaturan ukuran kertas berhasil disimpan.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirestoreFlagsCard extends StatelessWidget {
  final Map<String, bool?> flags;
  final void Function(String key, bool val) onToggle;

  const _FirestoreFlagsCard({
    required this.flags,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final modules = [
      {'key': 'all', 'label': 'Semua Modul (Override Global)'},
      {'key': 'customers', 'label': 'Pelanggan (Customers)'},
      {'key': 'categories', 'label': 'Kategori (Categories)'},
      {'key': 'products', 'label': 'Produk (Products)'},
      {'key': 'transactions', 'label': 'Transaksi & Bon (Transactions)'},
      {'key': 'expenses', 'label': 'Pengeluaran (Expenses)'},
      {'key': 'dashboard', 'label': 'Dashboard & Ringkasan Harian'},
      {'key': 'cigarettes', 'label': 'Laporan Rokok (Cigarettes)'},
    ];

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_sync, size: 20, color: AppColors.brand600),
                SizedBox(width: 8),
                Text(
                  'MIGRASI FIREBASE (STAGING FEATURE FLAGS)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.gray800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Alihkan komunikasi data per modul dari backend Laravel (REST API) ke Google Cloud Firestore (Staging). Perubahan disimpan ke preferensi lokal.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const Divider(height: 24),
            ...modules.map((m) {
              final key = m['key']!;
              final label = m['label']!;
              final isEnabled = flags[key] == true;
              return SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: key == 'all' ? FontWeight.w700 : FontWeight.normal,
                    color: key == 'all' ? AppColors.brand600 : AppColors.textMain,
                  ),
                ),
                subtitle: Text(
                  isEnabled ? 'Firestore Staging' : 'Laravel REST API',
                  style: TextStyle(
                    fontSize: 11,
                    color: isEnabled ? Colors.green.shade700 : AppColors.textMuted,
                  ),
                ),
                value: isEnabled,
                onChanged: (val) => onToggle(key, val),
              );
            }),
          ],
        ),
      ),
    );
  }
}

