import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_test/flutter_test.dart';
import 'package:rekapan_warung/core/api/api_client.dart';
import 'package:rekapan_warung/models/models.dart';
import 'package:rekapan_warung/repositories/firestore_repositories.dart';
import 'package:rekapan_warung/services/customer_rules_service.dart';

void main() {
  group('Firestore Model Serialization & Deserialization', () {
    test('Category toDocument & fromDocument', () {
      final category = Category(id: 3, name: 'Rokok', productsCount: 15);
      final doc = category.toDocument();

      expect(doc['name'], 'Rokok');
      expect(doc['legacyId'], 3);

      final fromDoc = Category.fromDocument('legacy_3', {
        ...doc,
        'productsCount': 15,
      });
      expect(fromDoc.id, 3);
      expect(fromDoc.name, 'Rokok');
      expect(fromDoc.productsCount, 15);

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

    test('Expense toDocument & fromDocument (legacy_ and tx_ prefixes)', () {
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

      final bonExp = Expense.fromDocument('bon_tx_999_item_1', {
        'date': '2026-10-13',
        'title': 'Potongan Bon',
        'amount': 15000,
        'source': 'bon',
        'transactionId': 'tx_999',
      });
      expect(bonExp.transactionId, 999);
      expect(bonExp.isFromBon, isTrue);
    });

    test('Transaction.fromDocument resolves customerName and non-zero ID for random Firestore IDs', () {
      final randomDoc = {
        'number': 'INV-20261013-001',
        'date': '2026-10-13',
        'customerId': 'legacy_58',
        'customerName': 'ALI DAGING',
        'totalAmount': 150000,
        'status': 'draft',
        'paymentStatus': 'unpaid',
      };

      // Kasus Firestore docId acak tanpa legacyId
      final parsed = Transaction.fromDocument('hLG5lMsUR4L9i2UV1DJ5', randomDoc);
      expect(parsed.id > 0, true);
      expect(parsed.id, 20261013001); // Dari invoice number INV-20261013-001
      expect(parsed.customer, isNotNull);
      expect(parsed.customer?.name, 'ALI DAGING');
      expect(parsed.transactionNumber, 'INV-20261013-001');
    });

    test('TransactionItem.fromDocument handles item_ prefix correctly', () {
      final itemDoc = {
        'id': 1776077589123,
        'legacyId': 1776077589123,
        'productName': 'Gorengan Tempe',
        'quantity': 3,
        'unit': 'pcs',
        'unitPrice': 2000,
        'subtotal': 5000,
      };

      final parsed = TransactionItem.fromDocument('item_1776077589123', itemDoc);
      expect(parsed.id, 1776077589123);
      expect(parsed.productName, 'Gorengan Tempe');
      expect(parsed.subtotal, 5000);
    });

    test('FirestoreBackupService.toJsonSafe converts Timestamp and strips FieldValue', () {
      final ts = Timestamp.fromDate(DateTime.utc(2026, 10, 13, 6, 0, 0));
      final raw = {
        'name': 'Budi',
        'createdAt': ts,
        'updatedAt': FieldValue.serverTimestamp(),
        'nested': [
          {'ts': ts, 'sentinel': FieldValue.delete()},
        ],
      };

      final safe = FirestoreBackupService.toJsonSafe(raw) as Map<String, dynamic>;
      final encoded = jsonEncode(safe);
      expect(encoded, contains(ts.toDate().toIso8601String()));
      expect(safe.containsKey('updatedAt'), isFalse);
      expect((safe['nested'] as List).first.containsKey('sentinel'), isFalse);
    });

    test('ApiClient.errorMessage surfaces CustomerDeletionException and Exception messages', () {
      expect(
        ApiClient.errorMessage(
          const CustomerDeletionException('Pelanggan masih punya bon.'),
        ),
        'Pelanggan masih punya bon.',
      );
      expect(
        ApiClient.errorMessage(
          Exception('Tidak bisa dihapus — masih ada item dalam kategori ini.'),
        ),
        'Tidak bisa dihapus — masih ada item dalam kategori ini.',
      );
    });
  });
}
