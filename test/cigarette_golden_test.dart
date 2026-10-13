import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/services/cigarette_classifier.dart';

void main() {
  group('CigaretteClassifier Unit Tests', () {
    test('normalize trims and collapses spaces to lowercase', () {
      expect(
        CigaretteClassifier.normalize('  Rokok   SURYA  16  '),
        'rokok surya 16',
      );
      expect(CigaretteClassifier.normalize(null), '');
    });

    test('textIsCigarette identifies keyword rokok', () {
      expect(CigaretteClassifier.textIsCigarette('Rokok'), isTrue);
      expect(
        CigaretteClassifier.textIsCigarette('Gudang Garam Rokok Filter'),
        isTrue,
      );
      expect(CigaretteClassifier.textIsCigarette('Kopi Susu'), isFalse);
      expect(CigaretteClassifier.textIsCigarette(null), isFalse);
    });

    test('isCigarette: Category-based is primary source', () {
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: 'Rokok',
          productName: 'Bang Lee',
        ),
        isTrue,
      );
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: 'Rokok',
          productName: 'SURYA 16',
        ),
        isTrue,
      );
    });

    test('isCigarette: Fallback to productName', () {
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: null,
          productName: 'Rokok Surya',
        ),
        isTrue,
      );
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: 'Lainnya',
          productName: 'Beli Rokok Sampoerna',
        ),
        isTrue,
      );
    });

    test('isCigarette: Fallback to description', () {
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: null,
          productName: 'Titip Beli',
          description: 'rokok magnum',
        ),
        isTrue,
      );
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: null,
          productName: 'Titip Beli',
          description: 'sabun mandi',
        ),
        isFalse,
      );
    });

    test('isCigarette: non-cigarette returns false', () {
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: 'Makanan',
          productName: 'Gorengan',
        ),
        isFalse,
      );
      expect(
        CigaretteClassifier.isCigarette(
          categoryName: 'Minuman',
          productName: 'Es Teh Manis',
        ),
        isFalse,
      );
    });

    test('generateReport reads camelCase customerName and categoryName from Firestore docs', () {
      final report = CigaretteClassifier.generateReport([
        {
          'id': 101,
          'number': 'INV-20261013-001',
          'date': '2026-10-13',
          'customerName': 'Pak RT',
          'status': 'completed',
          'paymentStatus': 'unpaid',
          'items': [
            {
              'productName': 'Sampoerna Mild 16',
              'categoryName': 'Rokok',
              'quantity': 2,
              'subtotal': 64000,
            },
          ],
        },
      ]);

      expect(report.summary.cigaretteQuantity, 2);
      expect(report.summary.cigaretteSales, 64000);
      expect(report.bons.single.customerName, 'Pak RT');
      expect(report.items.single.productName, 'Sampoerna Mild 16');
    });
  });

  group('Cigarette Report Golden Test (EC2 Fixture Comparison)', () {
    late List<Map<String, dynamic>> snapshotDataset;
    late Map<String, dynamic> goldenFixture;

    setUpAll(() {
      final datasetFile = File('test/fixtures/snapshot_dataset.json');
      snapshotDataset = (jsonDecode(datasetFile.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

      final fixtureFile = File('test/fixtures/cigarette_report_fixture.json');
      goldenFixture = jsonDecode(fixtureFile.readAsStringSync())
          as Map<String, dynamic>;
    });

    test('Dart port generates identical summary as EC2 Laravel CigaretteReportService', () {
      final report = CigaretteClassifier.generateReport(snapshotDataset);

      final expectedSummary = goldenFixture['summary'] as Map<String, dynamic>;

      expect(report.summary.cigaretteQuantity, expectedSummary['cigarette_quantity']);
      expect(report.summary.cigaretteSales, expectedSummary['cigarette_sales']);
      expect(report.summary.bonCount, expectedSummary['bon_count']);
      expect(report.summary.paidSales, expectedSummary['paid_sales']);
      expect(report.summary.unpaidSales, expectedSummary['unpaid_sales']);
    });

    test('Dart port generates identical item breakdown as EC2 Laravel service', () {
      final report = CigaretteClassifier.generateReport(snapshotDataset);

      final expectedItems = (goldenFixture['items'] as List)
          .cast<Map<String, dynamic>>();

      expect(report.items.length, expectedItems.length);

      for (int i = 0; i < expectedItems.length; i++) {
        expect(report.items[i].productName, expectedItems[i]['product_name']);
        expect(report.items[i].totalQuantity, expectedItems[i]['total_quantity']);
        expect(report.items[i].totalSales, expectedItems[i]['total_sales']);
      }
    });

    test('Dart port generates identical transaction list as EC2 Laravel service', () {
      final report = CigaretteClassifier.generateReport(snapshotDataset);

      final expectedTxData = (goldenFixture['transactions']['data'] as List)
          .cast<Map<String, dynamic>>();

      expect(report.bons.length, expectedTxData.length);

      for (int i = 0; i < expectedTxData.length; i++) {
        final actual = report.bons[i];
        final expected = expectedTxData[i];

        expect(actual.id, expected['id']);
        expect(actual.transactionNumber, expected['transaction_number']);
        expect(actual.transactionDate, expected['transaction_date']);
        expect(actual.customerName, expected['customer_name']);
        expect(actual.paymentStatus, expected['payment_status']);
        expect(actual.cigaretteQuantity, expected['cigarette_quantity']);
        expect(actual.cigaretteTotal, expected['cigarette_total']);
      }
    });

    test('Dart port generates identical products filter list as EC2 Laravel service', () {
      final report = CigaretteClassifier.generateReport(snapshotDataset);

      final expectedProducts = (goldenFixture['products'] as List).cast<String>();

      expect(report.products, expectedProducts);
    });
  });
}
