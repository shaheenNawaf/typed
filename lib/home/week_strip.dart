import '../models/note.dart';
import '../utils/markdown_display.dart';
import '../utils/note_kind.dart';
import '../utils/note_storage.dart';
import '../utils/task_dates.dart';

/// One day on Home's week strip: what got done, what is due, what was spent.
class StripDay {
  final DateTime day;

  /// Tasks finished that day (from the done log); 0 when none were kept.
  final int done;

  /// Open tasks dated that day.
  final int due;

  /// Spent that day, in the strip's currency (minor units).
  final int spent;

  const StripDay({
    required this.day,
    required this.done,
    required this.due,
    required this.spent,
  });

  bool get isEmpty => done == 0 && due == 0 && spent == 0;
}

/// Seven days around [now]: three back, today, three ahead. Past days show
/// what was done and spent; today and ahead also show what is due. Sample
/// money never counts. Spending is in the currency spent most this week.
({List<StripDay> days, String currency}) buildWeekStrip(
  List<Note> notes,
  Map<int, int> doneLog,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final days = [
    for (var i = -3; i <= 3; i++) DateTime(today.year, today.month, today.day + i),
  ];
  final first = days.first;
  int? indexOf(DateTime d) {
    final i = DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays;
    return i >= 0 && i < 7 ? i : null;
  }

  final due = List.filled(7, 0);
  for (final n in notes) {
    if (!isTaskNote(n)) continue;
    for (final item in parseChecklist(n.content)) {
      if (item.done) continue;
      final when = splitTaskDate(item.text, now).when;
      if (when == null) continue;
      final i = indexOf(when.day);
      if (i != null && i >= 3) due[i]++;
    }
  }

  final byCurrency = <String, List<int>>{};
  for (final n in notes) {
    if (!isVisibleFinanceNote(n)) continue;
    for (final e in n.amounts) {
      if (e.isDemo || (e.type ?? n.type) != 'expense') continue;
      final i = indexOf(e.date);
      if (i == null || i > 3) continue;
      final cur = e.currency ?? n.currency ?? 'PHP';
      byCurrency.putIfAbsent(cur, () => List.filled(7, 0))[i] += e.amount;
    }
  }
  var currency = 'PHP';
  var most = -1;
  byCurrency.forEach((cur, list) {
    final total = list.fold(0, (a, b) => a + b);
    if (total > most) {
      most = total;
      currency = cur;
    }
  });
  final spent = byCurrency[currency] ?? List.filled(7, 0);

  return (
    days: [
      for (var i = 0; i < 7; i++)
        StripDay(
          day: days[i],
          done: i <= 3 ? (doneLog[localEpochDay(days[i])] ?? 0) : 0,
          due: due[i],
          spent: spent[i],
        ),
    ],
    currency: currency,
  );
}
