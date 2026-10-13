import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/navigation.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'providers/providers.dart';
import 'repositories/repository_factory.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase, Offline Persistence, & Anonymous Auth
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(milliseconds: 800));
    }
  } catch (_) {}

  runApp(const RekapanWarungApp());
}

class RekapanWarungApp extends StatelessWidget {
  const RekapanWarungApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              DashboardProvider(RepositoryFactory.dashboardRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              CustomerProvider(RepositoryFactory.customerRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              CategoryProvider(RepositoryFactory.categoryRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProductProvider(RepositoryFactory.productRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => TransactionListProvider(
            RepositoryFactory.transactionRepository(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => CigaretteReportProvider(
            RepositoryFactory.cigaretteReportRepository(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ExpenseProvider(RepositoryFactory.expenseRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              BonDraftProvider(RepositoryFactory.transactionRepository()),
        ),
      ],
      child: MaterialApp(
        navigatorKey: Nav.navigatorKey,
        title: 'Warung Lupi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        home: const HomeShell(),
      ),
    );
  }
}
