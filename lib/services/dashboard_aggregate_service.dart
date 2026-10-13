import '../models/models.dart';
import '../providers/repositories.dart';

/// Dokumen ringkasan harian untuk koleksi `daily_summary/{yyyy-MM-dd}`.
class DailySummaryDocument {
  final String date;
  final int saleTotal;
  final int saleCount;
  final int paidTotal;
  final int unpaidTotal;
  final int expenseTotal;
  final int expenseManual;
  final int expenseBon;

  const DailySummaryDocument({
    required this.date,
    required this.saleTotal,
    required this.saleCount,
    required this.paidTotal,
    required this.unpaidTotal,
    required this.expenseTotal,
    required this.expenseManual,
    required this.expenseBon,
  });

  Map<String, dynamic> toFirestoreDocument() => {
        'date': date,
        'saleTotal': saleTotal,
        'saleCount': saleCount,
        'paidTotal': paidTotal,
        'unpaidTotal': unpaidTotal,
        'expenseTotal': expenseTotal,
        'expenseManual': expenseManual,
        'expenseBon': expenseBon,
      };
}

/// Service agregasi dashboard & daily summary.
class DashboardAggregateService {
  DashboardAggregateService._();

  /// Menghitung ringkasan harian untuk 1 tanggal tertentu.
  static DailySummaryDocument computeDailySummary({
    required String date,
    required List<Map<String, dynamic>> transactionsForDay,
    required List<Map<String, dynamic>> expensesForDay,
  }) {
    int saleTotal = 0;
    int saleCount = 0;
    int paidTotal = 0;
    int unpaidTotal = 0;

    for (final tx in transactionsForDay) {
      final totalRaw = tx['total_amount'] ?? tx['totalAmount'];
      final int total = totalRaw is num
          ? totalRaw.toInt()
          : (int.tryParse(totalRaw?.toString() ?? '0') ?? 0);
      final status = (tx['payment_status'] ?? tx['paymentStatus'])
          ?.toString()
          .toLowerCase();

      saleTotal += total;
      saleCount++;

      if (status == 'paid') {
        paidTotal += total;
      } else {
        unpaidTotal += total;
      }
    }

    int expenseTotal = 0;
    int expenseManual = 0;
    int expenseBon = 0;

    for (final exp in expensesForDay) {
      final amountRaw = exp['amount'];
      final int amount = amountRaw is num
          ? amountRaw.toInt()
          : (int.tryParse(amountRaw?.toString() ?? '0') ?? 0);
      final source = (exp['source'] ?? 'manual').toString().toLowerCase();

      expenseTotal += amount;
      if (source == 'bon') {
        expenseBon += amount;
      } else {
        expenseManual += amount;
      }
    }

    return DailySummaryDocument(
      date: date,
      saleTotal: saleTotal,
      saleCount: saleCount,
      paidTotal: paidTotal,
      unpaidTotal: unpaidTotal,
      expenseTotal: expenseTotal,
      expenseManual: expenseManual,
      expenseBon: expenseBon,
    );
  }

  /// Menghitung statistik lengkap dashboard dari seluruh transaksi & pengeluaran.
  static DashboardData computeDashboardStats({
    required String todayDateStr,
    required List<Map<String, dynamic>> allTransactions,
    required List<Map<String, dynamic>> allExpenses,
    required int activeCustomersCount,
    List<TransactionSummary> recent = const [],
  }) {
    int countToday = 0;
    int totalToday = 0;
    int lunasHariIni = 0;
    int lunasTotal = 0;
    int masihHutang = 0;

    for (final tx in allTransactions) {
      final txDate = (tx['transaction_date'] ?? tx['date'])?.toString() ?? '';
      final totalRaw = tx['total_amount'] ?? tx['totalAmount'];
      final int total = totalRaw is num
          ? totalRaw.toInt()
          : (int.tryParse(totalRaw?.toString() ?? '0') ?? 0);
      final payStatus = (tx['payment_status'] ?? tx['paymentStatus'])
          ?.toString()
          .toLowerCase();

      final isToday = txDate == todayDateStr;

      if (isToday) {
        countToday++;
        totalToday += total;
        if (payStatus == 'paid') {
          lunasHariIni += total;
        }
      }

      if (payStatus == 'paid') {
        lunasTotal += total;
      } else {
        masihHutang += total;
      }
    }

    int todayExpense = 0;
    int totalExpense = 0;

    for (final exp in allExpenses) {
      final expDate = (exp['expense_date'] ?? exp['date'])?.toString() ?? '';
      final amountRaw = exp['amount'];
      final int amount = amountRaw is num
          ? amountRaw.toInt()
          : (int.tryParse(amountRaw?.toString() ?? '0') ?? 0);

      totalExpense += amount;
      if (expDate == todayDateStr) {
        todayExpense += amount;
      }
    }

    return DashboardData(
      bonHariIni: countToday,
      totalHariIni: totalToday,
      lunasHariIni: lunasHariIni,
      lunasTotal: lunasTotal,
      masihHutang: masihHutang,
      pengeluaranHariIni: todayExpense,
      pengeluaranTotal: totalExpense,
      totalPelanggan: activeCustomersCount,
      recent: recent,
    );
  }
}
