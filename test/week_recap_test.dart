import 'package:flutter_test/flutter_test.dart';
import 'package:typed/home/week_recap.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/note_storage.dart';

void main() {
  // Monday, Nov 9 2026: last week is Nov 2 (Mon) – Nov 8 (Sun).
  final now = DateTime(2026, 11, 9, 10);

  Note note(String id, DateTime created, {List<String> tags = const []}) =>
      Note(id: id, title: id, content: '', tags: tags, createdAt: created);

  MoneyEntry spend(int pesos, DateTime d, String cat, {bool demo = false}) =>
      MoneyEntry(
        id: '$cat${d.day}$pesos',
        amount: pesos * 100,
        category: cat,
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
        createdAt: DateTime(2026, 11, 3),
      );

  test('counts last week only', () {
    final r = buildWeekRecap([
      note('a', DateTime(2026, 11, 3, 9)),
      note('b', DateTime(2026, 11, 8, 23)),
      note('v', DateTime(2026, 11, 4), tags: const ['voice']),
      note('old', DateTime(2026, 10, 30)),
      note('now', DateTime(2026, 11, 9, 8)),
      note('x_guide', DateTime(2026, 11, 3), tags: const ['guide']),
      ledger([]),
    ], {
      localEpochDay(DateTime(2026, 11, 3)): 2,
      localEpochDay(DateTime(2026, 11, 5)): 3,
      localEpochDay(DateTime(2026, 11, 9)): 9, // this week
    }, now);
    expect(r.start, DateTime(2026, 11, 2));
    expect(r.end, DateTime(2026, 11, 8));
    expect(r.notes, 2);
    expect(r.voiceMemos, 1);
    expect(r.tasksDone, 5);
    expect(r.hasActivity, isTrue);
  });

  test('no done log yet shows no task count', () {
    final r = buildWeekRecap([note('a', DateTime(2026, 11, 3))], {}, now);
    expect(r.tasksDone, isNull);
  });

  test('spending by day, the biggest day, and a rising category', () {
    final r = buildWeekRecap([
      ledger([
        spend(200, DateTime(2026, 11, 2, 12), 'Transport'),
        spend(1000, DateTime(2026, 11, 5, 19), 'Food'),
        spend(300, DateTime(2026, 10, 29), 'Food'), // the week before
        spend(5000, DateTime(2026, 11, 6), 'Food', demo: true),
      ]),
    ], {}, now);
    expect(r.spentByDay, [20000, 0, 0, 100000, 0, 0, 0]);
    expect(r.spent, 120000);
    expect(r.biggestDay, 3); // Thursday
    expect(r.risingCategory, 'Food');
    expect(r.risingBy, 70000);
  });

  test('a small change is not called out', () {
    final r = buildWeekRecap([
      ledger([
        spend(1000, DateTime(2026, 11, 5), 'Food'),
        spend(900, DateTime(2026, 10, 29), 'Food'),
      ]),
    ], {}, now);
    expect(r.risingCategory, isNull);
  });

  test('a quiet week has nothing to show', () {
    expect(buildWeekRecap([], {}, now).hasActivity, isFalse);
  });
}
