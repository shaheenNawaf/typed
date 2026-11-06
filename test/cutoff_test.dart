import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/cutoff.dart';

void main() {
  const std = PaydaySettings.standard; // 15th and 30th

  group('cutoffFor', () {
    test('between the 15th and the 30th', () {
      final c = cutoffFor(std, DateTime(2026, 11, 20, 9));
      expect(c.start, DateTime(2026, 11, 15));
      expect(c.nextPayday, DateTime(2026, 11, 30));
      expect(c.end, DateTime(2026, 11, 29));
      expect(c.totalDays, 15);
      expect(c.dayIndex(DateTime(2026, 11, 20, 23)), 6);
      expect(c.daysLeft(DateTime(2026, 11, 20)), 10);
    });

    test('early in the month the cutoff began last month', () {
      final c = cutoffFor(std, DateTime(2026, 11, 7));
      expect(c.start, DateTime(2026, 10, 30));
      expect(c.nextPayday, DateTime(2026, 11, 15));
      expect(c.rangeLabel, 'Oct 30 – Nov 14');
    });

    test('31st of a long month belongs to the 30th cutoff', () {
      final c = cutoffFor(std, DateTime(2026, 10, 31));
      expect(c.start, DateTime(2026, 10, 30));
      expect(c.nextPayday, DateTime(2026, 11, 15));
    });

    test('February: the 30th falls on the last day', () {
      expect(cutoffFor(std, DateTime(2027, 2, 20)).nextPayday,
          DateTime(2027, 2, 28));
      expect(cutoffFor(std, DateTime(2028, 2, 29)).start,
          DateTime(2028, 2, 29));
      expect(cutoffFor(std, DateTime(2027, 3, 1)).start,
          DateTime(2027, 2, 28));
    });

    test('on payday a new cutoff starts', () {
      expect(isPayday(std, DateTime(2026, 11, 15, 8)), isTrue);
      expect(isPayday(std, DateTime(2026, 11, 14, 8)), isFalse);
      final c = cutoffFor(std, DateTime(2026, 11, 15));
      expect(c.dayIndex(DateTime(2026, 11, 15)), 1);
      expect(previousCutoff(std, c).start, DateTime(2026, 10, 30));
    });

    test('once a month, and the last day', () {
      final monthly = cutoffFor(const PaydaySettings([5]), DateTime(2026, 11, 2));
      expect(monthly.start, DateTime(2026, 10, 5));
      expect(monthly.nextPayday, DateTime(2026, 11, 5));
      final last = cutoffFor(const PaydaySettings([31]), DateTime(2026, 11, 7));
      expect(last.start, DateTime(2026, 10, 31));
      expect(last.nextPayday, DateTime(2026, 11, 30));
    });
  });

  test('labels', () {
    expect(std.label, '15th and 30th');
    expect(const PaydaySettings([15, 31]).label, '15th and last day');
    expect(const PaydaySettings([31]).label, 'Last day of the month');
    expect(const PaydaySettings([5]).label, 'The 5th of each month');
    expect([1, 2, 3, 11, 12, 13, 21, 22].map(ordinal),
        ['1st', '2nd', '3rd', '11th', '12th', '13th', '21st', '22nd']);
  });

  group('cutoffMoney', () {
    final now = DateTime(2026, 11, 7, 12);
    final cutoff = cutoffFor(std, now); // Oct 30 – Nov 14, day 9 of 16
    MoneyEntry e(int pesos, DateTime d,
            {String cat = 'Food', String type = 'expense', bool demo = false, String? cur}) =>
        MoneyEntry(
          id: '${d.millisecondsSinceEpoch}$pesos',
          amount: pesos * 100,
          category: cat,
          date: d,
          type: type,
          currency: cur,
          isDemo: demo,
        );
    Note ledger(List<MoneyEntry> entries) => Note(
          id: 'f',
          title: 'Nov',
          content: '',
          tags: const [],
          type: 'expense',
          currency: 'PHP',
          amounts: entries,
        );

    test('spent since payday, by currency; income and samples left out', () {
      final m = cutoffMoney([
        ledger([
          e(500, DateTime(2026, 10, 29)), // before payday
          e(1000, DateTime(2026, 10, 30, 8)),
          e(2000, DateTime(2026, 11, 3), cat: 'Groceries'),
          e(700, DateTime(2026, 11, 7, 9)),
          e(15000, DateTime(2026, 11, 1), type: 'income'),
          e(900, DateTime(2026, 11, 2), demo: true),
          e(50, DateTime(2026, 11, 2), cur: 'USD'),
          e(400, DateTime(2026, 11, 8)), // tomorrow
        ]),
      ], cutoff, null, now);
      expect(m.currency, 'PHP');
      expect(m.spent, 370000);
      expect(m.todaySpent, 70000);
      expect(m.topCategory, 'Groceries');
      expect(m.anyLogged, isTrue);
      expect(m.left, isNull);
      expect(m.perDaySpent, (370000 / 9).round());
    });

    test('with a budget: left, per day and pace', () {
      const budget = CutoffBudget(1000000, 'PHP'); // ₱10,000
      Note spend(int pesos) => ledger([e(pesos, DateTime(2026, 11, 5))]);
      final onPace = cutoffMoney([spend(4660)], cutoff, budget, now);
      expect(onPace.left, 534000);
      expect(onPace.daysLeft, 8);
      expect(onPace.perDayLeft, 66750);
      expect(onPace.ideal, (1000000 * 9 / 16).round());
      expect(onPace.status, PaceStatus.onPace);
      expect(
        cutoffMoney([spend(7000)], cutoff, budget, now).status,
        PaceStatus.overPace,
      );
      final over = cutoffMoney([spend(10500)], cutoff, budget, now);
      expect(over.status, PaceStatus.overBudget);
      expect(over.left, -50000);
      expect(over.perDayLeft, 0);
    });

    test('a past cutoff stops at its last day', () {
      final prev = previousCutoff(std, cutoffFor(std, DateTime(2026, 11, 15)));
      final m = cutoffMoney([
        ledger([
          e(800, DateTime(2026, 11, 14)),
          e(300, DateTime(2026, 11, 15)),
        ]),
      ], prev, null, DateTime(2026, 11, 15, 9));
      expect(m.spent, 80000);
    });

    test('only sample data counts as nothing logged', () {
      final m = cutoffMoney([
        ledger([e(900, DateTime(2026, 11, 2), demo: true)]),
      ], cutoff, null, now);
      expect(m.anyLogged, isFalse);
      expect(m.spent, 0);
    });
  });
}
