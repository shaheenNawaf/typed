import '../models/note.dart';
import '../utils/markdown_display.dart';
import '../utils/note_kind.dart';
import '../utils/note_storage.dart';

/// Monday's look back at last week: what got done, what was written, and
/// where the money went — a fresh-start moment, never a scorecard.
class WeekRecap {
  /// Monday of last week.
  final DateTime start;

  /// Tasks finished; null when no count was kept yet (first week).
  final int? tasksDone;
  final int notes;
  final int voiceMemos;

  /// Spent each day, Monday first, in [currency].
  final List<int> spentByDay;
  final String currency;

  /// The category that rose most against the week before, if notable.
  final String? risingCategory;
  final int risingBy;

  const WeekRecap({
    required this.start,
    required this.tasksDone,
    required this.notes,
    required this.voiceMemos,
    required this.spentByDay,
    required this.currency,
    required this.risingCategory,
    required this.risingBy,
  });

  DateTime get end => start.add(const Duration(days: 6));
  int get spent => spentByDay.fold(0, (a, b) => a + b);

  /// Index (0 = Monday) of the day with the most spent; null when none.
  int? get biggestDay {
    var best = -1;
    int? at;
    for (var i = 0; i < 7; i++) {
      if (spentByDay[i] > best && spentByDay[i] > 0) {
        best = spentByDay[i];
        at = i;
      }
    }
    return at;
  }

  bool get hasActivity =>
      (tasksDone ?? 0) > 0 || notes > 0 || voiceMemos > 0 || spent > 0;
}

/// Local midnight [n] days after [d].
DateTime _dayPlus(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Last week (Monday to Sunday) as of [now]. [doneLog] maps local epoch
/// days to tasks finished that day.
WeekRecap buildWeekRecap(
  List<Note> notes,
  Map<int, int> doneLog,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final thisMonday = _dayPlus(today, -(today.weekday - 1));
  final start = _dayPlus(thisMonday, -7);
  final before = _dayPlus(start, -7);
  bool inWeek(DateTime d, DateTime from) =>
      !d.isBefore(from) && d.isBefore(_dayPlus(from, 7));

  final firstDay = localEpochDay(start);
  final logged = [for (var i = 0; i < 7; i++) doneLog[firstDay + i]];
  final tasksDone = logged.every((v) => v == null)
      ? null
      : logged.fold<int>(0, (a, b) => a + (b ?? 0));

  var written = 0;
  var voice = 0;
  for (final n in notes) {
    if (n.isDeleted || isSeedNote(n) || isFinanceNote(n)) continue;
    if (!inWeek(n.createdAt, start)) continue;
    if (n.tags.contains('voice')) {
      voice++;
    } else {
      written++;
    }
  }

  // Spending: per day last week, and per category for both weeks, in the
  // currency spent most.
  final byCurrency = <String, List<int>>{};
  final catNow = <String, Map<String, int>>{};
  final catBefore = <String, Map<String, int>>{};
  for (final n in notes) {
    if (!isVisibleFinanceNote(n)) continue;
    for (final e in n.amounts) {
      if (e.isDemo || (e.type ?? n.type) != 'expense') continue;
      final cur = e.currency ?? n.currency ?? 'PHP';
      if (inWeek(e.date, start)) {
        final days = byCurrency.putIfAbsent(cur, () => List.filled(7, 0));
        final i = DateTime(
          e.date.year,
          e.date.month,
          e.date.day,
        ).difference(start).inDays.clamp(0, 6);
        days[i] += e.amount;
        final cats = catNow.putIfAbsent(cur, () => {});
        cats[e.category] = (cats[e.category] ?? 0) + e.amount;
      } else if (inWeek(e.date, before)) {
        final cats = catBefore.putIfAbsent(cur, () => {});
        cats[e.category] = (cats[e.category] ?? 0) + e.amount;
      }
    }
  }
  var currency = 'PHP';
  var most = -1;
  byCurrency.forEach((cur, days) {
    final total = days.fold(0, (a, b) => a + b);
    if (total > most) {
      most = total;
      currency = cur;
    }
  });

  // A category is "rising" when it grew by at least 200 (whole units) and
  // 20% on the week before.
  String? rising;
  var risingBy = 0;
  final prev = catBefore[currency] ?? const {};
  (catNow[currency] ?? const {}).forEach((cat, total) {
    final was = prev[cat] ?? 0;
    final up = total - was;
    if (up >= 20000 && (was == 0 || up >= was * 0.2) && up > risingBy) {
      rising = cat;
      risingBy = up;
    }
  });

  return WeekRecap(
    start: start,
    tasksDone: tasksDone,
    notes: written,
    voiceMemos: voice,
    spentByDay: byCurrency[currency] ?? List.filled(7, 0),
    currency: currency,
    risingCategory: rising,
    risingBy: risingBy,
  );
}
