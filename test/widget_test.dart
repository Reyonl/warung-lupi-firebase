// Smoke test tanpa network: widget test murni + unit test logika promo.
//
// CATATAN: jangan pump seluruh app (RekapanWarungApp) di sini — DashboardScreen
// memicu request network via dio, dan di lingkungan testWidgets (FakeAsync)
// request tersebut tidak pernah selesai sehingga timer Dio tetap pending.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rekapan_warung/core/theme/app_theme.dart';
import 'package:rekapan_warung/models/models.dart';
import 'package:rekapan_warung/utils/promo.dart';
import 'package:rekapan_warung/widgets/thermal_receipt.dart';
import 'package:rekapan_warung/widgets/widgets.dart';

/// Bon uji: 2 penambahan (5.000 + 7.000) + 1 potongan (-5.000).
/// Nomor bon sengaja pendek: font uji flutter_test bersifat monospace persegi
/// (tiap glyph 1em) sehingga nomor 16 karakter pada lebar 58mm memicu overflow
/// layout palsu yang tidak terjadi di produksi.
Transaction _receiptTransaction() {
  return Transaction(
    id: 1,
    transactionNumber: 'INV-001',
    transactionDate: '2026-10-12',
    totalAmount: 7000,
    status: 'completed',
    paymentStatus: 'paid',
    customer: const Customer(id: 1, name: 'Untung', isActive: true),
    items: const [
      TransactionItem(
        id: 1,
        productName: 'Nasi Uduk',
        quantity: 1,
        unit: 'pcs',
        unitPrice: 5000,
        subtotal: 5000,
      ),
      TransactionItem(
        id: 2,
        productName: 'Aqua',
        quantity: 1,
        unit: 'pcs',
        unitPrice: 7000,
        subtotal: 7000,
      ),
      TransactionItem(
        id: 3,
        productName: 'Gorengan',
        quantity: 1,
        unit: 'pcs',
        unitPrice: -5000,
        subtotal: -5000,
      ),
    ],
  );
}

void main() {
  group('AppFormField', () {
    testWidgets('renders label with required marker', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppFormField(
              label: 'Nama Item',
              required: true,
              child: const TextField(),
            ),
          ),
        ),
      );

      expect(find.text('Nama Item'), findsOneWidget);
      expect(find.text('*'), findsOneWidget);
    });
  });

  group('StatusBadge', () {
    testWidgets('renders Aktif for active customer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: StatusBadge.active(isActive: true)),
        ),
      );

      expect(find.text('Aktif'), findsOneWidget);
    });

    testWidgets('renders Nonaktif for inactive customer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: StatusBadge.active(isActive: false)),
        ),
      );

      expect(find.text('Nonaktif'), findsOneWidget);
    });
  });

  group('calculatePromoSubtotal', () {
    test('gorengan: tiap 3 pcs = Rp5.000, sisa × harga', () {
      // 5 pcs @2000 → promoQty 1 (5000) + sisa 2 (4000) = 9000
      expect(calculatePromoSubtotal('Gorengan Tahu', 5, 2000), 9000);
      // 3 pcs → 5000
      expect(calculatePromoSubtotal('Gorengan Pisang', 3, 2000), 5000);
      // 1 pcs → 2000
      expect(calculatePromoSubtotal('Gorengan', 1, 2000), 2000);
    });

    test('donat/nagasari/lemper/jajanan: tiap 2 pcs = Rp5.000', () {
      // 5 pcs @1500 → promoQty 2 (10000) + sisa 1 (1500) = 11500
      expect(calculatePromoSubtotal('Donat Coklat', 5, 1500), 11500);
      expect(calculatePromoSubtotal('nagasari', 4, 1500), 10000);
      expect(calculatePromoSubtotal('lemper ayam', 2, 1500), 5000);
      expect(calculatePromoSubtotal('Donat', 2, 3000), 5000);
      expect(calculatePromoSubtotal('Nagasari', 2, 3000), 5000);
      expect(calculatePromoSubtotal('Lemper', 2, 3000), 5000);
      expect(calculatePromoSubtotal('Sosis Solo', 2, 3000), 5000);
      expect(calculatePromoSubtotal('sosis solo ayam', 3, 3000), 8000);
      expect(calculatePromoSubtotal('Sosis', 2, 3000), 5000);
      expect(calculatePromoSubtotal('Jajanan pasar', 1, 1500), 1500);
    });

    test('item lain: qty × harga', () {
      expect(calculatePromoSubtotal('Es Teh', 3, 5000), 15000);
    });
  });

  group('formatPriceDisplay', () {
    test('memformat angka ribuan id-ID', () {
      expect(formatPriceDisplay(1234567), '1.234.567');
      expect(formatPriceDisplay(-5000), '-5.000');
      expect(formatPriceDisplay(''), '');
    });
  });

  group('ThermalReceipt — blok POTONGAN (mirror web)', () {
    testWidgets('item minus dipisah: POTONGAN + Sebelum Potongan + TOTAL', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThermalReceipt(
                transaction: _receiptTransaction(),
                size: '80mm', // fontSize 14 di 58mm overflow palsu di font uji
                preview: true,
              ),
            ),
          ),
        ),
      );

      // Penambahan normal
      expect(find.text('Nasi Uduk'), findsOneWidget);
      expect(find.text('Aqua'), findsOneWidget);
      // Blok potongan terpisah
      expect(find.text('POTONGAN'), findsOneWidget);
      expect(find.text('Gorengan'), findsOneWidget);
      // "-5.000" (subtotal potongan, tanda minus)
      expect(find.text('-5.000'), findsOneWidget);
      // Total: Sebelum Potongan (12.000) → TOTAL (7.000).
      // "7.000" muncul 2×: subtotal Aqua + nilai TOTAL.
      expect(find.text('Sebelum Potongan'), findsOneWidget);
      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('7.000'), findsNWidgets(2));
    });
  });
}
