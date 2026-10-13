import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/storage/prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../repositories/firestore_repositories.dart';
import '../../services/printer_service.dart';
import '../../widgets/widgets.dart';

/// Pengaturan Warung Lupi:
/// - Backup Data ke File JSON (Google Drive / WhatsApp / Memori HP)
/// - Pilih / Pair printer Bluetooth Classic SPP (dari perangkat yang sudah paired/bonded)
/// - Tes Cetak
/// - Ukuran kertas default 58mm / 80mm
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

  // Backup JSON
  bool _exportingBackup = false;
  String? _backupError;
  String? _backupSuccess;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final size = await Prefs.getThermalSize();
    final name = await Prefs.getPrinterName();
    final id = await Prefs.getPrinterId();
    if (!mounted) return;
    setState(() {
      _size = size;
      _printerName = name;
      _printerId = id;
      _loadingPrefs = false;
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
      final paired = await PrinterService.instance.bondedPrinters();
      if (!mounted) return;
      if (paired.isEmpty) {
        setState(
          () => _pairError =
              'Tidak ada perangkat Bluetooth yang terpasang (paired). Pasangkan printer Anda lewat Pengaturan Android → Bluetooth (PIN umumnya 0000 atau 1234), lalu tekan tombol ini lagi.',
        );
        return;
      }
      setState(() => _available = paired);
    } catch (e) {
      if (mounted) {
        setState(() => _pairError = 'Gagal memuat printer: ${e.toString()}');
      }
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
      if (mounted) {
        setState(() => _pairError = 'Gagal memilih printer: ${e.toString()}');
      }
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
      if (mounted) {
        setState(() => _testSuccess = 'Tes cetak berhasil dikirim ke printer!');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _testError = 'Printer tidak dapat terhubung: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _changeSize(String v) async {
    setState(() => _size = v);
    await Prefs.setThermalSize(v);
  }

  Future<void> _exportBackup() async {
    if (_exportingBackup) return;
    setState(() {
      _exportingBackup = true;
      _backupError = null;
      _backupSuccess = null;
    });
    try {
      final payload = await FirestoreBackupService.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/warung_lupi_backup_$stamp.json');
      await file.writeAsString(jsonStr);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], text: 'Backup Data Warung Lupi ($stamp)');

      final counts = payload['counts'] as Map<String, dynamic>? ?? const {};
      if (mounted) {
        setState(() {
          _backupSuccess =
              'File backup berhasil dibuat (${counts['customers'] ?? 0} pelanggan, '
              '${counts['products'] ?? 0} item, ${counts['transactions'] ?? 0} bon, '
              '${counts['expenses'] ?? 0} pengeluaran).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _backupError = 'Gagal membuat backup: $e');
      }
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
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
                _BackupCard(
                  exporting: _exportingBackup,
                  error: _backupError,
                  success: _backupSuccess,
                  onExport: _exportBackup,
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  final bool exporting;
  final String? error;
  final String? success;
  final VoidCallback onExport;

  const _BackupCard({
    required this.exporting,
    required this.error,
    required this.success,
    required this.onExport,
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
          const Row(
            children: [
              Icon(Icons.backup_outlined, size: 18, color: AppColors.brand600),
              SizedBox(width: 8),
              Text(
                'BACKUP DATA (GOOGLE DRIVE / FILE JSON)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.gray800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (error != null) InlineMessage(error!),
          if (success != null) InlineMessage(success!, isError: false),
          const Text(
            'Ekspor seluruh data warung (Pelanggan, Kategori, Item, Riwayat Bon beserta detail item, dan Pengeluaran) menjadi file .json untuk disimpan ke Google Drive, WhatsApp, atau memori HP.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          BrandButton(
            label: exporting
                ? 'Menyiapkan File Backup...'
                : 'Backup & Simpan ke Google Drive (.json)',
            loading: exporting,
            onPressed: exporting ? null : onExport,
            expand: true,
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
