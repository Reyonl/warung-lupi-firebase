import '../storage/prefs.dart';

/// Feature flag manager untuk transisi bertahap Dio (Laravel) ➔ Cloud Firestore.
///
/// Prioritas:
/// 1. Override runtime dari [Prefs] (jika disetel pengguna via UI Pengaturan).
/// 2. Nilai `--dart-define` saat compile time.
/// 3. Default: `false` (selalu memakai Dio/REST API).
class FeatureFlags {
  FeatureFlags._();

  // Environment variables compile-time (Fase 8: Default cutover ke Cloud Firestore)
  static const bool _envAll = bool.fromEnvironment('USE_FIRESTORE_ALL', defaultValue: true);
  static const bool _envCustomers = bool.fromEnvironment('USE_FIRESTORE_CUSTOMERS', defaultValue: false);
  static const bool _envCategories = bool.fromEnvironment('USE_FIRESTORE_CATEGORIES', defaultValue: false);
  static const bool _envProducts = bool.fromEnvironment('USE_FIRESTORE_PRODUCTS', defaultValue: false);
  static const bool _envTransactions = bool.fromEnvironment('USE_FIRESTORE_TRANSACTIONS', defaultValue: false);
  static const bool _envExpenses = bool.fromEnvironment('USE_FIRESTORE_EXPENSES', defaultValue: false);
  static const bool _envDashboard = bool.fromEnvironment('USE_FIRESTORE_DASHBOARD', defaultValue: false);
  static const bool _envCigarettes = bool.fromEnvironment('USE_FIRESTORE_CIGARETTES', defaultValue: false);

  // Cache in-memory untuk runtime overrides dari Prefs
  static bool? _prefCustomers;
  static bool? _prefCategories;
  static bool? _prefProducts;
  static bool? _prefTransactions;
  static bool? _prefExpenses;
  static bool? _prefDashboard;
  static bool? _prefCigarettes;
  static bool? _prefAll;

  /// Memuat preferensi runtime flag dari storage saat aplikasi start.
  static Future<void> init() async {
    final p = await Prefs.getFirestoreFlags();
    _prefAll = p['all'];
    _prefCustomers = p['customers'];
    _prefCategories = p['categories'];
    _prefProducts = p['products'];
    _prefTransactions = p['transactions'];
    _prefExpenses = p['expenses'];
    _prefDashboard = p['dashboard'];
    _prefCigarettes = p['cigarettes'];
  }

  static bool get useFirestoreAll => _prefAll ?? _envAll;

  static bool get useFirestoreCustomers =>
      _prefCustomers ?? (useFirestoreAll || _envCustomers);

  static bool get useFirestoreCategories =>
      _prefCategories ?? (useFirestoreAll || _envCategories);

  static bool get useFirestoreProducts =>
      _prefProducts ?? (useFirestoreAll || _envProducts);

  static bool get useFirestoreTransactions =>
      _prefTransactions ?? (useFirestoreAll || _envTransactions);

  static bool get useFirestoreExpenses =>
      _prefExpenses ?? (useFirestoreAll || _envExpenses);

  static bool get useFirestoreDashboard =>
      _prefDashboard ?? (useFirestoreAll || _envDashboard);

  static bool get useFirestoreCigarettes =>
      _prefCigarettes ?? (useFirestoreAll || _envCigarettes);

  /// Helper untuk testing: reset atau set flag langsung.
  static void setOverrideForTesting({
    bool? all,
    bool? customers,
    bool? categories,
    bool? products,
    bool? transactions,
    bool? expenses,
    bool? dashboard,
    bool? cigarettes,
  }) {
    _prefAll = all;
    _prefCustomers = customers;
    _prefCategories = categories;
    _prefProducts = products;
    _prefTransactions = transactions;
    _prefExpenses = expenses;
    _prefDashboard = dashboard;
    _prefCigarettes = cigarettes;
  }
}
