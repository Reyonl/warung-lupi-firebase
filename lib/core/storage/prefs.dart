import 'package:shared_preferences/shared_preferences.dart';

/// Prefs — wrapper shared_preferences untuk pengaturan lokal printer thermal.
class Prefs {
  Prefs._();

  static const _thermalSize = 'thermalSize';
  static const _printerName = 'savedPrinterName';
  static const _printerId = 'savedPrinterId';

  static Future<String> getThermalSize() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_thermalSize) ?? '58mm';
  }

  static Future<void> setThermalSize(String size) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_thermalSize, size);
  }

  static Future<String> getPrinterName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_printerName) ?? '';
  }

  static Future<String> getPrinterId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_printerId) ?? '';
  }

  static Future<void> setPrinter(String? name, String? id) async {
    final p = await SharedPreferences.getInstance();
    if (name != null) await p.setString(_printerName, name);
    if (id != null) await p.setString(_printerId, id);
  }
}
