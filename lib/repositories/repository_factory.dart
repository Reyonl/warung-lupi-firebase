import '../core/config/feature_flags.dart';
import '../providers/repositories.dart';
import 'firestore_repositories.dart';

/// Factory yang mengembalikan implementasi Repository berdasarkan [FeatureFlags].
///
/// Jika flag Firestore aktif untuk modul terkait, mengembalikan `FirestoreXxxRepository`.
/// Jika flag tidak aktif (default), mengembalikan instance `XxxRepository` asli berbasis Dio/REST.
class RepositoryFactory {
  RepositoryFactory._();

  static CustomerRepository customerRepository() =>
      FeatureFlags.useFirestoreCustomers
          ? FirestoreCustomerRepository()
          : CustomerRepository();

  static CategoryRepository categoryRepository() =>
      FeatureFlags.useFirestoreCategories
          ? FirestoreCategoryRepository()
          : CategoryRepository();

  static ProductRepository productRepository() =>
      FeatureFlags.useFirestoreProducts
          ? FirestoreProductRepository()
          : ProductRepository();

  static TransactionRepository transactionRepository() =>
      FeatureFlags.useFirestoreTransactions
          ? FirestoreTransactionRepository()
          : TransactionRepository();

  static ExpenseRepository expenseRepository() =>
      FeatureFlags.useFirestoreExpenses
          ? FirestoreExpenseRepository()
          : ExpenseRepository();

  static DashboardRepository dashboardRepository() =>
      FeatureFlags.useFirestoreDashboard
          ? FirestoreDashboardRepository()
          : DashboardRepository();

  static CigaretteReportRepository cigaretteReportRepository() =>
      FeatureFlags.useFirestoreCigarettes
          ? FirestoreCigaretteReportRepository()
          : CigaretteReportRepository();
}
