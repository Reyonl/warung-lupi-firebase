import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/core/config/feature_flags.dart';
import 'package:rekapan_warung/providers/repositories.dart';
import 'package:rekapan_warung/repositories/firestore_repositories.dart';
import 'package:rekapan_warung/repositories/repository_factory.dart';

void main() {
  group('RepositoryFactory Tests', () {
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

    test('Yields default Firestore repositories on cutover', () {
      expect(RepositoryFactory.customerRepository(), isA<FirestoreCustomerRepository>());
      expect(RepositoryFactory.categoryRepository(), isA<FirestoreCategoryRepository>());
      expect(RepositoryFactory.productRepository(), isA<FirestoreProductRepository>());
      expect(RepositoryFactory.transactionRepository(), isA<FirestoreTransactionRepository>());
      expect(RepositoryFactory.expenseRepository(), isA<FirestoreExpenseRepository>());
      expect(RepositoryFactory.dashboardRepository(), isA<FirestoreDashboardRepository>());
      expect(RepositoryFactory.cigaretteReportRepository(), isA<FirestoreCigaretteReportRepository>());
    });

    test('Yields legacy Dio repositories when rollback flag all is false', () {
      FeatureFlags.setOverrideForTesting(all: false);
      expect(RepositoryFactory.customerRepository(), isA<CustomerRepository>());
      expect(RepositoryFactory.customerRepository(), isNot(isA<FirestoreCustomerRepository>()));

      expect(RepositoryFactory.categoryRepository(), isA<CategoryRepository>());
      expect(RepositoryFactory.categoryRepository(), isNot(isA<FirestoreCategoryRepository>()));

      expect(RepositoryFactory.productRepository(), isA<ProductRepository>());
      expect(RepositoryFactory.productRepository(), isNot(isA<FirestoreProductRepository>()));

      expect(RepositoryFactory.transactionRepository(), isA<TransactionRepository>());
      expect(RepositoryFactory.transactionRepository(), isNot(isA<FirestoreTransactionRepository>()));

      expect(RepositoryFactory.expenseRepository(), isA<ExpenseRepository>());
      expect(RepositoryFactory.expenseRepository(), isNot(isA<FirestoreExpenseRepository>()));

      expect(RepositoryFactory.dashboardRepository(), isA<DashboardRepository>());
      expect(RepositoryFactory.dashboardRepository(), isNot(isA<FirestoreDashboardRepository>()));

      expect(RepositoryFactory.cigaretteReportRepository(), isA<CigaretteReportRepository>());
      expect(RepositoryFactory.cigaretteReportRepository(), isNot(isA<FirestoreCigaretteReportRepository>()));
    });

    test('Yields individual rolled back Dio repository while others remain Firestore', () {
      FeatureFlags.setOverrideForTesting(customers: false);

      expect(RepositoryFactory.customerRepository(), isA<CustomerRepository>());
      expect(RepositoryFactory.productRepository(), isA<FirestoreProductRepository>());
      expect(RepositoryFactory.categoryRepository(), isA<FirestoreCategoryRepository>());
    });

    test('Yields all Firestore repositories when useFirestoreAll is true', () {
      FeatureFlags.setOverrideForTesting(all: true);

      expect(RepositoryFactory.customerRepository(), isA<FirestoreCustomerRepository>());
      expect(RepositoryFactory.categoryRepository(), isA<FirestoreCategoryRepository>());
      expect(RepositoryFactory.productRepository(), isA<FirestoreProductRepository>());
      expect(RepositoryFactory.transactionRepository(), isA<FirestoreTransactionRepository>());
      expect(RepositoryFactory.expenseRepository(), isA<FirestoreExpenseRepository>());
      expect(RepositoryFactory.dashboardRepository(), isA<FirestoreDashboardRepository>());
      expect(RepositoryFactory.cigaretteReportRepository(), isA<FirestoreCigaretteReportRepository>());
    });
  });
}
