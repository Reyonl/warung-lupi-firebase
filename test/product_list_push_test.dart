import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rekapan_warung/core/theme/app_theme.dart';
import 'package:rekapan_warung/providers/providers.dart';
import 'package:rekapan_warung/providers/repositories.dart';
import 'package:rekapan_warung/screens/products/product_list_screen.dart';

void main() {
  testWidgets('di-push tanpa Scaffold di atasnya → tetap punya Material', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ProductProvider(
                ProductRepository(),
                CategoryRepository(),
              ),
            ),
          ],
          child: const ProductListScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.takeException(),
      isNull,
      reason: 'ProductListScreen tidak boleh crash saat di-push',
    );
    expect(
      find.byType(TextField),
      findsWidgets,
      reason: 'baris cari item harus ter-render',
    );
    expect(
      find.byType(AppBar),
      findsOneWidget,
      reason: 'mode push → punya AppBar sendiri',
    );
  });

  testWidgets('embedded → TIDAK menambah Scaffold kedua (tetap 1)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ProductProvider(
                ProductRepository(),
                CategoryRepository(),
              ),
            ),
          ],
          child: const Scaffold(body: ProductListScreen(embedded: true)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(
      find.byType(Scaffold),
      findsOneWidget,
      reason: 'mode embedded = body HomeShell; Scaffold ganda menumpuk AppBar',
    );
    expect(find.byType(AppBar), findsNothing);
  });
}
