import '../models/note.dart';
import '../utils/markdown_display.dart';
import '../utils/task_dates.dart';
import '../voice/when_parser.dart';

/// Where an open task stands against today.
enum TaskStanding { overdue, today, undated, tomorrow, later }

/// The rows under Today's focus card, in this order.
enum TodayGroup { overdue, anyTime, morning, afternoon, evening }

const kTodayGroupNames = {
  TodayGroup.overdue: 'Overdue',
  TodayGroup.anyTime: 'Any time',
  TodayGroup.morning: 'Morning',
  TodayGroup.afternoon: 'Afternoon',
  TodayGroup.evening: 'Evening',
};

/// One open checklist line, with its date read off the line.
class TodayItem {
  final Note note;
  final int lineIndex;

  /// The line's text after `- [ ] `, exactly as stored.
  final String raw;

  /// What to show: no date suffix, no inline markdown.
  final String text;
  final SpokenWhen? when;
  final TaskStanding standing;

  const TodayItem({
    required this.note,
    required this.lineIndex,
    required this.raw,
    required this.text,
    required this.when,
    required this.standing,
  });

  String get key => '${note.id}:$lineIndex';

  /// The raw text without its date, ready for a new one.
  String rawWithoutDate(DateTime now) => splitTaskDate(raw, now).text;

  bool get hasTime => when?.hour != null || when?.partOfDay != null;

  TodayGroup get group {
    if (standing == TaskStanding.overdue) return TodayGroup.overdue;
    final w = when;
    if (w == null || !hasTime) return TodayGroup.anyTime;
    if (w.hour != null) {
      return w.hour! < 12
          ? TodayGroup.morning
          : w.hour! < 17
          ? TodayGroup.afternoon
          : TodayGroup.evening;
    }
    return switch (w.partOfDay) {
      'morning' => TodayGroup.morning,
      'afternoon' => TodayGroup.afternoon,
      _ => TodayGroup.evening,
    };
  }

  /// "2:00 PM", "Evening", or empty when there is no time.
  String get timeLabel {
    final w = when;
    if (w == null) return '';
    if (w.hour != null) {
      final h = w.hour! % 12 == 0 ? 12 : w.hour! % 12;
      final m = (w.minute ?? 0).toString().padLeft(2, '0');
      return '$h:$m ${w.hour! < 12 ? 'AM' : 'PM'}';
    }
    final p = w.partOfDay;
    if (p == null) return '';
    return '${p[0].toUpperCase()}${p.substring(1)}';
  }
}

/// What Home's Today block shows.
class TodayPlan {
  /// The one task the card puts first; null on a quiet day.
  final TodayItem? focus;

  /// The rest of today, in [TodayGroup] order.
  final List<TodayItem> rest;

  /// Overdue, due today, and undated tasks, in focus order.
  final List<TodayItem> overdue;
  final List<TodayItem> dueToday;
  final List<TodayItem> undated;
  final List<TodayItem> tomorrow;

  const TodayPlan({
    required this.focus,
    required this.rest,
    required this.overdue,
    required this.dueToday,
    required this.undated,
    required this.tomorrow,
  });

  /// Nothing overdue and nothing due today.
  bool get isQuiet => overdue.isEmpty && dueToday.isEmpty;

  /// Undated tasks Today shows on a busy day.
  List<TodayItem> get undatedShown => undated.take(3).toList();

  /// "for today" in the subline: what Today lists, overdue aside.
  int get forToday => dueToday.length + undatedShown.length;

  bool get isEmpty => overdue.isEmpty && dueToday.isEmpty && undated.isEmpty;
}

/// Every open checklist line across lists, sorted for Home.
///
/// Focus order: overdue (oldest first), due today with a time (by time),
/// due today without one, then undated (freshest list first).
TodayPlan buildTodayPlan(List<Note> notes, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrowDay = today.add(const Duration(days: 1));
  final lists =
      notes
          .where((n) => !n.isArchived && !n.isDeleted && !isSeedNote(n))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final overdue = <TodayItem>[];
  final timed = <TodayItem>[];
  final untimed = <TodayItem>[];
  final undated = <TodayItem>[];
  final tomorrow = <TodayItem>[];
  for (final note in lists) {
    for (final line in parseChecklist(note.content)) {
      if (line.done || line.text.isEmpty) continue;
      final split = splitTaskDate(line.text, now);
      final when = split.when;
      final day = when?.day;
      final standing = day == null
          ? TaskStanding.undated
          : day.isBefore(today)
          ? TaskStanding.overdue
          : day == today
          ? TaskStanding.today
          : day == tomorrowDay
          ? TaskStanding.tomorrow
          : TaskStanding.later;
      final text = stripInlineMarkdown(split.text).trim();
      if (text.isEmpty) continue;
      final item = TodayItem(
        note: note,
        lineIndex: line.lineIndex,
        raw: line.text,
        text: text,
        when: when,
        standing: standing,
      );
      switch (standing) {
        case TaskStanding.overdue:
          overdue.add(item);
        case TaskStanding.today:
          (item.hasTime ? timed : untimed).add(item);
        case TaskStanding.undated:
          undated.add(item);
        case TaskStanding.tomorrow:
          tomorrow.add(item);
        case TaskStanding.later:
          break;
      }
    }
  }
  int byTime(TodayItem a, TodayItem b) => a.when!.at.compareTo(b.when!.at);
  overdue.sort(byTime);
  timed.sort(byTime);
  final tomorrowTimed = tomorrow.where((i) => i.hasTime).toList()..sort(byTime);
  final tomorrowSorted = [
    ...tomorrow.where((i) => !i.hasTime),
    ...tomorrowTimed,
  ];

  final dueToday = [...untimed, ...timed];
  final quiet = overdue.isEmpty && dueToday.isEmpty;
  final focus = quiet ? null : [...overdue, ...timed, ...untimed].first;

  // Rows under the card: the rest of today, grouped by time of day. Built
  // group by group (sort is not stable, and Any time keeps list order).
  final pool = [
    ...overdue,
    ...untimed,
    if (!quiet) ...undated.take(3),
    ...timed,
  ].where((i) => i != focus).toList();
  final rest = [
    for (final g in TodayGroup.values) ...pool.where((i) => i.group == g),
  ];

  return TodayPlan(
    focus: focus,
    rest: rest,
    overdue: overdue,
    dueToday: dueToday,
    undated: undated,
    tomorrow: tomorrowSorted,
  );
}
