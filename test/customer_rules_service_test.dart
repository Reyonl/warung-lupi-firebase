import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/services/customer_rules_service.dart';

void main() {
  group('CustomerRulesService', () {
    test('canDelete returns false when customer has transactions', () {
      expect(CustomerRulesService.canDelete(transactionCount: 3), isFalse);
      expect(CustomerRulesService.canDelete(transactionCount: 1), isFalse);
    });

    test('canDelete returns true when customer has 0 transactions', () {
      expect(CustomerRulesService.canDelete(transactionCount: 0), isTrue);
    });

    test('validateCanDelete throws CustomerDeletionException when transactionCount > 0', () {
      expect(
        () => CustomerRulesService.validateCanDelete(transactionCount: 2),
        throwsA(
          isA<CustomerDeletionException>().having(
            (e) => e.message,
            'message',
            'Pelanggan tidak dapat dihapus karena memiliki riwayat bon.',
          ),
        ),
      );
    });

    test('validateCanDelete succeeds when transactionCount == 0', () {
      expect(
        CustomerRulesService.validateCanDelete(transactionCount: 0),
        isTrue,
      );
    });
  });
}
