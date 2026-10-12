import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/services/invoice_number_service.dart';

void main() {
  group('InvoiceNumberService', () {
    test('formatOfficialNumber formats with padding', () {
      expect(
        InvoiceNumberService.formatOfficialNumber('2026-10-12', 1),
        'INV-20261012-001',
      );
      expect(
        InvoiceNumberService.formatOfficialNumber('2026-10-12', 42),
        'INV-20261012-042',
      );
      expect(
        InvoiceNumberService.formatOfficialNumber('20261012', 105),
        'INV-20261012-105',
      );
    });

    test('generateOfflineDraftNumber produces DRAFT- prefix', () {
      final draft = InvoiceNumberService.generateOfflineDraftNumber(
        '2026-10-12',
        uniqueSuffix: 'TEST01',
      );
      expect(draft, 'DRAFT-20261012-TEST01');
      expect(InvoiceNumberService.isDraft(draft), isTrue);
    });

    test('isDraft identifies official vs draft numbers', () {
      expect(InvoiceNumberService.isDraft('INV-20261012-001'), isFalse);
      expect(InvoiceNumberService.isDraft('DRAFT-20261012-ABC'), isTrue);
      expect(InvoiceNumberService.isDraft('TEMP-12345'), isTrue);
      expect(InvoiceNumberService.isDraft(null), isTrue);
      expect(InvoiceNumberService.isDraft(''), isTrue);
    });

    test('extractDatePart extracts yyyyMMdd', () {
      expect(
        InvoiceNumberService.extractDatePart('INV-20261012-001'),
        '20261012',
      );
      expect(
        InvoiceNumberService.extractDatePart('DRAFT-20261012-XYZ'),
        '20261012',
      );
      expect(InvoiceNumberService.extractDatePart('INVALID'), isNull);
    });

    test('counterDocId formats counter document path', () {
      expect(
        InvoiceNumberService.counterDocId('2026-10-12'),
        'invoice_20261012',
      );
    });
  });
}
