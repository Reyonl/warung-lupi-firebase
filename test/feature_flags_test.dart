import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/core/config/feature_flags.dart';

void main() {
  group('FeatureFlags Tests', () {
    tearDown(() {
      FeatureFlags.setOverrideForTesting(
        all: null,
        customers: null,
        categories: null,
        products: null,
        transactions: null,
        expenses: null,
        dashboard: null,
        cigarettes: null,
      );
    });

    test('Default values are all false', () {
      expect(FeatureFlags.useFirestoreAll, isFalse);
      expect(FeatureFlags.useFirestoreCustomers, isFalse);
      expect(FeatureFlags.useFirestoreCategories, isFalse);
      expect(FeatureFlags.useFirestoreProducts, isFalse);
      expect(FeatureFlags.useFirestoreTransactions, isFalse);
      expect(FeatureFlags.useFirestoreExpenses, isFalse);
      expect(FeatureFlags.useFirestoreDashboard, isFalse);
      expect(FeatureFlags.useFirestoreCigarettes, isFalse);
    });

    test('Individual module overrides work independently', () {
      FeatureFlags.setOverrideForTesting(customers: true);
      expect(FeatureFlags.useFirestoreCustomers, isTrue);
      expect(FeatureFlags.useFirestoreProducts, isFalse);
      expect(FeatureFlags.useFirestoreTransactions, isFalse);

      FeatureFlags.setOverrideForTesting(products: true, transactions: true);
      expect(FeatureFlags.useFirestoreProducts, isTrue);
      expect(FeatureFlags.useFirestoreTransactions, isTrue);
      expect(FeatureFlags.useFirestoreExpenses, isFalse);
    });

    test('useFirestoreAll overrides all modules', () {
      FeatureFlags.setOverrideForTesting(all: true);
      expect(FeatureFlags.useFirestoreAll, isTrue);
      expect(FeatureFlags.useFirestoreCustomers, isTrue);
      expect(FeatureFlags.useFirestoreCategories, isTrue);
      expect(FeatureFlags.useFirestoreProducts, isTrue);
      expect(FeatureFlags.useFirestoreTransactions, isTrue);
      expect(FeatureFlags.useFirestoreExpenses, isTrue);
      expect(FeatureFlags.useFirestoreDashboard, isTrue);
      expect(FeatureFlags.useFirestoreCigarettes, isTrue);
    });
  });
}
