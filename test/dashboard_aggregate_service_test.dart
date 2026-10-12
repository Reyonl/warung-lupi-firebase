import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/services/dashboard_aggregate_service.dart';

void main() {
  group('DashboardAggregateService', () {
    test('computeDailySummary computes daily rollups correctly', () {
      final transactions = [
        {'total_amount': 50000, 'payment_status': 'paid'},
        {'total_amount': 30000, 'payment_status': 'unpaid'},
        {'total_amount': 20000, 'payment_status': 'paid'},
      ];

      final expenses = [
        {'amount': 15000, 'source': 'manual'},
        {'amount': 5000, 'source': 'bon'},
      ];

      final summary = DashboardAggregateService.computeDailySummary(
        date: '2026-10-12',
        transactionsForDay: transactions,
        expensesForDay: expenses,
      );

      expect(summary.date, '2026-10-12');
      expect(summary.saleTotal, 100000);
      expect(summary.saleCount, 3);
      expect(summary.paidTotal, 70000);
      expect(summary.unpaidTotal, 30000);
      expect(summary.expenseTotal, 20000);
      expect(summary.expenseManual, 15000);
      expect(summary.expenseBon, 5000);

      final doc = summary.toFirestoreDocument();
      expect(doc['saleTotal'], 100000);
      expect(doc['expenseBon'], 5000);
    });

    test('computeDashboardStats aggregates today and all-time stats accurately', () {
      final allTransactions = [
        {
          'date': '2026-10-12',
          'total_amount': 100000,
          'payment_status': 'paid',
        },
        {
          'date': '2026-10-12',
          'total_amount': 40000,
          'payment_status': 'unpaid',
        },
        {
          'date': '2026-10-11',
          'total_amount': 80000,
          'payment_status': 'unpaid',
        },
        {
          'date': '2026-10-10',
          'total_amount': 60000,
          'payment_status': 'paid',
        },
      ];

      final allExpenses = [
        {'date': '2026-10-12', 'amount': 25000},
        {'date': '2026-10-11', 'amount': 35000},
      ];

      final stats = DashboardAggregateService.computeDashboardStats(
        todayDateStr: '2026-10-12',
        allTransactions: allTransactions,
        allExpenses: allExpenses,
        activeCustomersCount: 38,
      );

      expect(stats.bonHariIni, 2);
      expect(stats.totalHariIni, 140000);
      expect(stats.lunasHariIni, 100000);
      expect(stats.lunasTotal, 160000); // 100k + 60k
      expect(stats.masihHutang, 120000); // 40k + 80k
      expect(stats.pengeluaranHariIni, 25000);
      expect(stats.pengeluaranTotal, 60000);
      expect(stats.totalPelanggan, 38);
    });
  });
}
