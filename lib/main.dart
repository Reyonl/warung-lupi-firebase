import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/config/feature_flags.dart';
import 'core/navigation.dart';
import 'core/storage/prefs.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'providers/providers.dart';
import 'repositories/repository_factory.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi feature flags untuk peralihan runtime/compile-time
  await FeatureFlags.init();

  // Inisialisasi Firebase jika flag Firestore aktif
  if (FeatureFlags.useFirestoreCustomers ||
      FeatureFlags.useFirestoreCategories ||
      FeatureFlags.useFirestoreProducts ||
      FeatureFlags.useFirestoreTransactions ||
      FeatureFlags.useFirestoreExpenses ||
      FeatureFlags.useFirestoreDashboard ||
      FeatureFlags.useFirestoreCigarettes) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}
  }

  // Terapkan alamat server yang disimpan pengguna (bila ada) SEBELUM widget
  // pertama dibangun, supaya semua request memakai server yang benar.
  // Di produksi tidak ada override → langsung memakai
  // https://warunglupi.tplp004.com (lihat ApiConfig.productionBaseUrl).
  final savedBaseUrl = await Prefs.getApiBaseUrl();
  if (savedBaseUrl.isNotEmpty) {
    ApiConfig.runtimeOverride = savedBaseUrl;
    ApiClient.instance.setBaseUrl(savedBaseUrl);
  }

  runApp(const RekapanWarungApp());
}

class RekapanWarungApp extends StatelessWidget {
  const RekapanWarungApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => DashboardProvider(RepositoryFactory.dashboardRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => CustomerProvider(RepositoryFactory.customerRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => CategoryProvider(RepositoryFactory.categoryRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProductProvider(RepositoryFactory.productRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => TransactionListProvider(RepositoryFactory.transactionRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => CigaretteReportProvider(RepositoryFactory.cigaretteReportRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => ExpenseProvider(RepositoryFactory.expenseRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => BonDraftProvider(RepositoryFactory.transactionRepository()),
        ),
      ],
      child: MaterialApp(
        navigatorKey: Nav.navigatorKey,
        title: 'Warung Lupi',
        debugShowCheckedModeBanner: false,
        // Aplikasi ini dirancang light-only (lihat AppColors). Kunci ke
        // ThemeMode.light supaya dark mode sistem tidak pernah membuat
        // Scaffold gelap + teks gelap (halaman tampak hitam/blank).
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        home: const HomeShell(),
      ),
    );
  }
}
