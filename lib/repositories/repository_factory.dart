import '../providers/repositories.dart';
import 'firestore_repositories.dart';

/// Factory penyedia instance repository Cloud Firestore.
class RepositoryFactory {
  RepositoryFactory._();

  static CustomerRepository customerRepository() =>
      FirestoreCustomerRepository();

  static CategoryRepository categoryRepository() =>
      FirestoreCategoryRepository();

  static ProductRepository productRepository() => FirestoreProductRepository();

  static TransactionRepository transactionRepository() =>
      FirestoreTransactionRepository();

  static ExpenseRepository expenseRepository() => FirestoreExpenseRepository();

  static DashboardRepository dashboardRepository() =>
      FirestoreDashboardRepository();

  static CigaretteReportRepository cigaretteReportRepository() =>
      FirestoreCigaretteReportRepository();
}
