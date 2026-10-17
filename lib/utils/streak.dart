import '../models/note.dart';

class WritingStreak {
  final int days;
  final bool writtenToday;
  final int activeDays;

  /// Whether each of the last 7 days had writing, oldest first, today last.
  final List<bool> lastSevenDays;

  const WritingStreak({
    required this.days,
    required this.writtenToday,
    required this.activeDays,
    this.lastSevenDays = const [],
  });

  Map<String, dynamic> toJson() => {
    'streak': days,
    'writtenToday': writtenToday,
    'total': activeDays,
    'week': lastSevenDays,
  };
}

WritingStreak computeWritingStreak(List<Note> notes, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final days = <DateTime>{};
  for (final note in notes) {
    if (note.isArchived || note.isDeleted) continue;
    days.add(_dateOnly(note.updatedAt));
  }

  final writtenToday = days.contains(today);
  // Calendar steps, not 24h ones: across a DST change `subtract(1 day)` from
  // midnight lands at 23:00/01:00, misses the date set and breaks the streak.
  DateTime back(DateTime day, int n) =>
      DateTime(day.year, day.month, day.day - n);
  var cursor = writtenToday ? today : back(today, 1);
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = back(cursor, 1);
  }

  return WritingStreak(
    days: streak,
    writtenToday: writtenToday,
    activeDays: days.length,
    lastSevenDays: [for (var i = 6; i >= 0; i--) days.contains(back(today, i))],
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
