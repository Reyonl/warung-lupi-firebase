import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Pengaturan menampilkan Backup JSON, Printer Thermal, dan Ukuran Kertas',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('BACKUP DATA (GOOGLE DRIVE / FILE JSON)'), findsOneWidget);
    expect(find.text('Backup & Simpan ke Google Drive (.json)'), findsOneWidget);
    expect(find.text('PRINTER THERMAL'), findsOneWidget);
    expect(find.text('UKURAN KERTAS DEFAULT'), findsOneWidget);
  });
}