import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/utils/finance_utils.dart';

MoneyEntry _entry(num amount, {String? currency}) => MoneyEntry.fromJson({
      'id': 'm1',
      'amount': amount,
      'category': 'Food',
      'date': '2026-09-01T00:00:00.000',
      'currency': currency,
    });

void main() {
  group('parseAmountToMinor', () {
    test('parses dot and comma decimal separators', () {
      expect(parseAmountToMinor('12.34', 'PHP'), 1234);
      expect(parseAmountToMinor('12,34', 'PHP'), 1234);
      expect(parseAmountToMinor(' 12.34 ', 'PHP'), 1234);
    });

    test('zero-decimal currencies accept whole amounts only', () {
      expect(parseAmountToMinor('1200', 'JPY'), 1200);
      expect(parseAmountToMinor('1200.00', 'JPY'), isNull);
    });

    test('rejects more fractional digits than the currency has', () {
      expect(parseAmountToMinor('1.234567', 'PHP'), isNull);
      expect(parseAmountToMinor('12.', 'PHP'), isNull);
      expect(parseAmountToMinor('', 'PHP'), isNull);
      expect(parseAmountToMinor('abc', 'PHP'), isNull);
      expect(parseAmountToMinor('-5', 'PHP'), isNull);
    });

    test('pads short fractions to the currency exponent', () {
      expect(parseAmountToMinor('12.3', 'PHP'), 1230);
      expect(parseAmountToMinor('12', 'PHP'), 1200);
    });
  });

  group('formatMinor', () {
    test('formats with grouping and currency decimals', () {
      expect(formatMinor(1234, 'PHP'), '12.34');
      expect(formatMinor(120000, 'JPY'), '120,000');
      expect(formatMinor(1500000, 'PHP'), '15,000.00');
      expect(formatMinor(-150, 'PHP'), '-1.50');
      expect(formatMinor(-25000, 'PHP'), '-250.00');
      expect(formatMinor(-1250000, 'PHP'), '-12,500.00');
    });

    test('formatMinorAmount prefixes the symbol', () {
      expect(formatMinorAmount(18000, 'PHP'), '₱180.00');
      expect(formatMinorAmount(1200, 'JPY'), '¥1,200');
    });
  });

  group('legacy document migration', () {
    test('double amounts are majors, ints are minor units', () {
      expect(_entry(180.0, currency: 'PHP').amount, 18000);
      expect(_entry(18000, currency: 'PHP').amount, 18000);
      expect(_entry(1200.0, currency: 'JPY').amount, 1200);
      expect(_entry(500000.5).amount, 50000050);
    });

    test('budget limits migrate the same way', () {
      final legacy = Budget.fromJson({
        'id': 'b1',
        'category': 'Food',
        'limit': 5000.0,
      });
      expect(legacy.limit, 500000);
      expect(Budget.fromJson({
        'id': 'b2',
        'category': 'Food',
        'limit': 500000,
      }).limit, 500000);
    });

    test('round-trip through toJson keeps minor units intact', () {
      final entry = _entry(180.0, currency: 'PHP');
      expect(_entry(entry.toJson()['amount'] as int, currency: 'PHP').amount,
          18000);
    });
  });

  group('exact money arithmetic', () {
    test('the 0.1 + 0.2 case is exact in minor units', () {
      final a = parseAmountToMinor('0.10', 'PHP')!;
      final b = parseAmountToMinor('0.20', 'PHP')!;
      expect(a + b, 30);
      expect(formatMinor(a + b, 'PHP'), '0.30');
    });

    test('budget boundary is exact', () {
      final budget = Budget(
          id: 'b', category: 'Food', limit: parseAmountToMinor('500', 'PHP')!);
      final spent = parseAmountToMinor('250.00', 'PHP')! * 2;
      expect(spent == budget.limit, isTrue);
      expect(spent > budget.limit, isFalse);
    });
  });
}
