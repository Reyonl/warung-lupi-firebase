import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/repositories/firestore_repositories.dart';
import 'package:rekapan_warung/repositories/repository_factory.dart';

void main() {
  group('RepositoryFactory Tests', () {
    test('Yields Cloud Firestore repositories for all modules', () {
      expect(
        RepositoryFactory.customerRepository(),
        isA<FirestoreCustomerRepository>(),
      );
      expect(
        RepositoryFactory.categoryRepository(),
        isA<FirestoreCategoryRepository>(),
      );
      expect(
        RepositoryFactory.productRepository(),
        isA<FirestoreProductRepository>(),
      );
      expect(
        RepositoryFactory.transactionRepository(),
        isA<FirestoreTransactionRepository>(),
      );
      expect(
        RepositoryFactory.expenseRepository(),
        isA<FirestoreExpenseRepository>(),
      );
      expect(
        RepositoryFactory.dashboardRepository(),
        isA<FirestoreDashboardRepository>(),
      );
      expect(
        RepositoryFactory.cigaretteReportRepository(),
        isA<FirestoreCigaretteReportRepository>(),
      );
    });
  });
}
