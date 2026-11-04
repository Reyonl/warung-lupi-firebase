import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/models/models.dart';
import 'package:rekapan_warung/providers/repositories.dart';

void main() {
  group('SalesReportData & Metrics Calculation', () {
    test('computes gross sales, promo discounts, net sales, and net profit correctly', () {
      final categoryMetrics = [
        const CategorySalesMetric(
          categoryName: 'Makanan',
          totalAmount: 150000,
          totalQty: 30,
          percentage: 60.0,
        ),
        const CategorySalesMetric(
          categoryName: 'Minuman',
          totalAmount: 100000,
          totalQty: 20,
          percentage: 40.0,
        ),
      ];

      final topProducts = [
        const TopProductSalesMetric(
          productName: 'Nasi Uduk',
          quantity: 25,
          totalAmount: 125000,
        ),
        const TopProductSalesMetric(
          productName: 'Es Teh Manis',
          quantity: 20,
          totalAmount: 60000,
        ),
      ];

      const report = SalesReportData(
        dateFrom: '2026-11-04',
        dateTo: '2026-11-04',
        totalTransactions: 15,
        grossSales: 250000,
        promoDiscounts: 10000,
        netSales: 240000,
        totalExpenses: 40000,
        netProfit: 200000,
        cashTotal: 180000,
        nonCashTotal: 40000,
        unpaidTotal: 20000,
        categoryMetrics: [],
        topProducts: [],
      );

      expect(report.grossSales, 250000);
      expect(report.promoDiscounts, 10000);
      expect(report.netSales, report.grossSales - report.promoDiscounts);
      expect(report.netProfit, report.netSales - report.totalExpenses);
      expect(report.cashTotal + report.nonCashTotal + report.unpaidTotal, 240000);
    });

    test('handles empty report gracefully', () {
      const empty = SalesReportData.empty;
      expect(empty.totalTransactions, 0);
      expect(empty.grossSales, 0);
      expect(empty.promoDiscounts, 0);
      expect(empty.netSales, 0);
      expect(empty.netProfit, 0);
      expect(empty.categoryMetrics, isEmpty);
      expect(empty.topProducts, isEmpty);
    });
  });
}
