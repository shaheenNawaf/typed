import '../models/note.dart';

class WritingStreak {
  final int days;
  final bool writtenToday;
  final int activeDays;

  const WritingStreak({
    required this.days,
    required this.writtenToday,
    required this.activeDays,
  });

  Map<String, dynamic> toJson() => {
    'streak': days,
    'writtenToday': writtenToday,
    'total': activeDays,
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
  var cursor = writtenToday ? today : today.subtract(const Duration(days: 1));
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  return WritingStreak(
    days: streak,
    writtenToday: writtenToday,
    activeDays: days.length,
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
