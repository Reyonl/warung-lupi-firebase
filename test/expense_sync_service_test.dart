import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/services/expense_sync_service.dart';

void main() {
  group('ExpenseSyncService', () {
    test('identifies negative subtotal as expense item', () {
      expect(ExpenseSyncService.isExpenseItem(-25000), isTrue);
      expect(ExpenseSyncService.isExpenseItem(-1), isTrue);
      expect(ExpenseSyncService.isExpenseItem(0), isFalse);
      expect(ExpenseSyncService.isExpenseItem(15000), isFalse);
    });

    test('generates synced expense for negative subtotal with absolute amount', () {
      final exp = ExpenseSyncService.generateExpense(
        transactionId: '101',
        itemId: '505',
        transactionDate: '2026-10-12',
        productName: 'POTONGAN BELANJA',
        description: 'Diskon langganan',
        subtotal: -30000,
      );

      expect(exp, isNotNull);
      expect(exp!.docId, 'bon_101_505');
      expect(exp.syncKey, 'bon:101:505');
      expect(exp.amount, 30000); // absolute integer
      expect(exp.source, 'bon');
      expect(exp.date, '2026-10-12');
      expect(exp.title, 'POTONGAN BELANJA');
      expect(exp.notes, 'Diskon langganan');

      final doc = exp.toFirestoreDocument(legacyId: 99);
      expect(doc['amount'], 30000);
      expect(doc['legacyId'], 99);
      expect(doc['syncKey'], 'bon:101:505');
    });

    test('returns null for non-negative subtotal', () {
      final exp = ExpenseSyncService.generateExpense(
        transactionId: '101',
        itemId: '506',
        transactionDate: '2026-10-12',
        productName: 'AQUA',
        subtotal: 5000,
      );

      expect(exp, isNull);
    });

    test('isBelongsToTransaction checks docId prefix', () {
      expect(
        ExpenseSyncService.isBelongsToTransaction('bon_101_505', '101'),
        isTrue,
      );
      expect(
        ExpenseSyncService.isBelongsToTransaction('bon_102_505', '101'),
        isFalse,
      );
      expect(
        ExpenseSyncService.isBelongsToTransaction('manual_999', '101'),
        isFalse,
      );
    });
  });
}
