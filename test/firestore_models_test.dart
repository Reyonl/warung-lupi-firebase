import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/models/models.dart';

void main() {
  group('Firestore Model Serialization & Deserialization', () {
    test('Category toDocument & fromDocument', () {
      final category = Category(id: 3, name: 'Rokok', productsCount: 15);
      final doc = category.toDocument();

      expect(doc['name'], 'Rokok');
      expect(doc['legacyId'], 3);

      final fromDoc = Category.fromDocument('legacy_3', doc);
      expect(fromDoc.id, 3);
      expect(fromDoc.name, 'Rokok');

      // Test fallback ID dari docId jika legacyId tidak ada
      final fallbackDoc = Category.fromDocument('legacy_7', {'name': 'Minuman'});
      expect(fallbackDoc.id, 7);
      expect(fallbackDoc.name, 'Minuman');
    });

    test('Product toDocument & fromDocument', () {
      final product = Product(
        id: 12,
        categoryId: 3,
        name: 'SAMPOERNA MILD 16',
        defaultPrice: 32000,
        unit: 'bks',
        isActive: true,
      );
      final doc = product.toDocument();

      expect(doc['name'], 'SAMPOERNA MILD 16');
      expect(doc['categoryId'], 'legacy_3');
      expect(doc['defaultPrice'], 32000);
      expect(doc['unit'], 'bks');
      expect(doc['isActive'], true);
      expect(doc['legacyId'], 12);

      final fromDoc = Product.fromDocument('legacy_12', doc);
      expect(fromDoc.id, 12);
      expect(fromDoc.categoryId, 3);
      expect(fromDoc.name, 'SAMPOERNA MILD 16');
      expect(fromDoc.defaultPrice, 32000);
      expect(fromDoc.unit, 'bks');
      expect(fromDoc.isActive, true);
    });

    test('Customer toDocument & fromDocument', () {
      final customer = Customer(
        id: 5,
        name: 'Pak Haji Rohim',
        phone: '081234567890',
        notes: 'Pelanggan setia warung',
        isActive: true,
        transactionsCount: 10,
      );
      final doc = customer.toDocument();

      expect(doc['name'], 'Pak Haji Rohim');
      expect(doc['phone'], '081234567890');
      expect(doc['notes'], 'Pelanggan setia warung');
      expect(doc['isActive'], true);
      expect(doc['legacyId'], 5);

      final fromDoc = Customer.fromDocument('legacy_5', doc, transactionsCount: 10);
      expect(fromDoc.id, 5);
      expect(fromDoc.name, 'Pak Haji Rohim');
      expect(fromDoc.phone, '081234567890');
      expect(fromDoc.notes, 'Pelanggan setia warung');
      expect(fromDoc.isActive, true);
      expect(fromDoc.transactionsCount, 10);
    });

    test('TransactionItem toDocument & fromDocument', () {
      final item = TransactionItem(
        id: 101,
        transactionId: 44,
        productId: 12,
        productName: 'SAMPOERNA MILD 16',
        description: 'Beli 2 bungkus',
        quantity: 2,
        unit: 'bks',
        unitPrice: 32000,
        subtotal: 64000,
      );
      final doc = item.toDocument();

      expect(doc['productId'], 'legacy_12');
      expect(doc['productName'], 'SAMPOERNA MILD 16');
      expect(doc['description'], 'Beli 2 bungkus');
      expect(doc['quantity'], 2);
      expect(doc['unit'], 'bks');
      expect(doc['unitPrice'], 32000);
      expect(doc['subtotal'], 64000);
      expect(doc['legacyId'], 101);

      final fromDoc = TransactionItem.fromDocument('legacy_101', doc, transactionId: 44);
      expect(fromDoc.id, 101);
      expect(fromDoc.transactionId, 44);
      expect(fromDoc.productId, 12);
      expect(fromDoc.productName, 'SAMPOERNA MILD 16');
      expect(fromDoc.quantity, 2);
      expect(fromDoc.unitPrice, 32000);
      expect(fromDoc.subtotal, 64000);
    });

    test('Transaction toDocument & fromDocument', () {
      final tx = Transaction(
        id: 44,
        customerId: 5,
        transactionNumber: 'INV-20261012-001',
        transactionDate: '2026-10-12',
        totalAmount: 64000,
        status: 'completed',
        paymentStatus: 'paid',
        notes: 'Lunas tunai',
        customer: Customer(id: 5, name: 'Pak Haji Rohim', isActive: true),
      );
      final doc = tx.toDocument();

      expect(doc['number'], 'INV-20261012-001');
      expect(doc['date'], '2026-10-12');
      expect(doc['customerId'], 'legacy_5');
      expect(doc['customerName'], 'Pak Haji Rohim');
      expect(doc['totalAmount'], 64000);
      expect(doc['status'], 'completed');
      expect(doc['paymentStatus'], 'paid');
      expect(doc['notes'], 'Lunas tunai');
      expect(doc['legacyId'], 44);

      final fromDoc = Transaction.fromDocument('legacy_44', doc);
      expect(fromDoc.id, 44);
      expect(fromDoc.customerId, 5);
      expect(fromDoc.transactionNumber, 'INV-20261012-001');
      expect(fromDoc.transactionDate, '2026-10-12');
      expect(fromDoc.totalAmount, 64000);
      expect(fromDoc.status, 'completed');
      expect(fromDoc.paymentStatus, 'paid');
    });

    test('Expense toDocument & fromDocument', () {
      final expense = Expense(
        id: 77,
        expenseDate: '2026-10-12',
        title: 'Beli token listrik warung',
        category: 'Operasional',
        amount: 100000,
        source: 'manual',
        notes: 'Token 100rb PLN',
      );
      final doc = expense.toDocument();

      expect(doc['title'], 'Beli token listrik warung');
      expect(doc['date'], '2026-10-12');
      expect(doc['category'], 'Operasional');
      expect(doc['amount'], 100000);
      expect(doc['source'], 'manual');
      expect(doc['notes'], 'Token 100rb PLN');
      expect(doc['legacyId'], 77);

      final fromDoc = Expense.fromDocument('legacy_77', doc);
      expect(fromDoc.id, 77);
      expect(fromDoc.expenseDate, '2026-10-12');
      expect(fromDoc.title, 'Beli token listrik warung');
      expect(fromDoc.category, 'Operasional');
      expect(fromDoc.amount, 100000);
      expect(fromDoc.source, 'manual');
    });
  });
}
