import 'package:flutter_test/flutter_test.dart';
import 'package:typed/home/week_strip.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/cutoff.dart';
import 'package:typed/utils/note_storage.dart';

void main() {
  // Sunday, Nov 15 2026: the strip runs Thu 12 – Wed 18.
  final now = DateTime(2026, 11, 15, 10);

  MoneyEntry spend(int pesos, DateTime d, {bool demo = false}) => MoneyEntry(
        id: 'e${d.day}$pesos',
        amount: pesos * 100,
        category: 'Food',
        date: d,
        type: 'expense',
        isDemo: demo,
      );

  Note ledger(List<MoneyEntry> entries) => Note(
        id: 'fin',
        title: 'Money',
        content: '',
        tags: const [],
        type: 'expense',
        currency: 'PHP',
        amounts: entries,
      );

  test('three days back, today, three ahead', () {
    final s = buildWeekStrip(const [], const {}, now);
    expect(s.days.map((d) => d.day.day), [12, 13, 14, 15, 16, 17, 18]);
    expect(s.days.every((d) => d.isEmpty), isTrue);
  });

  test('done from the log, due from task dates, spending without samples',
      () {
    final tasks = Note(
      id: 't',
      title: 'Errands',
      type: 'todo',
      tags: const ['todo'],
      content: '- [ ] Call the dentist — Sun, Nov 15\n'
          '- [ ] Pay rent — Tue, Nov 17\n'
          '- [x] Bins — Tue, Nov 17\n'
          '- [ ] Old thing — Thu, Nov 12\n',
    );
    final s = buildWeekStrip(
      [
        tasks,
        ledger([
          spend(250, DateTime(2026, 11, 13, 12)),
          spend(100, DateTime(2026, 11, 15, 9)),
          spend(999, DateTime(2026, 11, 14), demo: true),
          spend(500, DateTime(2026, 11, 16)),
        ]),
      ],
      {localEpochDay(DateTime(2026, 11, 14)): 2},
      now,
    );
    final byDay = {for (final d in s.days) d.day.day: d};
    expect(byDay[14]!.done, 2);
    expect(byDay[15]!.due, 1);
    expect(byDay[17]!.due, 1, reason: 'done items never count as due');
    expect(byDay[12]!.due, 0, reason: 'past days show what was done, not due');
    expect(byDay[13]!.spent, 25000);
    expect(byDay[14]!.spent, 0, reason: 'sample entries never count');
    expect(byDay[15]!.spent, 10000);
    expect(byDay[16]!.spent, 0, reason: 'nothing is spent ahead of today');
  });

  test('cutoff money splits spending by day of the period', () {
    // Nov 20: the period began on payday, the 15th.
    final mid = DateTime(2026, 11, 20, 10);
    final cutoff = cutoffFor(PaydaySettings.standard, mid);
    final m = cutoffMoney(
      [
        ledger([
          spend(300, cutoff.start),
          spend(120, DateTime(2026, 11, 20, 8)),
          spend(80, DateTime(2026, 11, 20, 9)),
        ]),
      ],
      cutoff,
      null,
      mid,
    );
    expect(m.spentByDay.length, cutoff.totalDays);
    expect(m.spentByDay.first, 30000);
    expect(m.spentByDay[m.dayIndex - 1], 20000);
    expect(m.spentByDay.fold<int>(0, (a, b) => a + b), m.spent);
  });
}
