import 'date_format.dart';

/// Calendar-day distance from [d] to [now]: 0 = same day, -1 = yesterday.
///
/// Both operands are truncated to midnight first, so the result is a whole
/// number of calendar days in the device's local timezone and never a
/// partial day. This is the single source of truth shared by the section
/// header and the row timestamp — the two used to disagree because one
/// counted calendar days and the other counted elapsed hours.
int calendarDayDiff(DateTime d, DateTime now) {
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(now.year, now.month, now.day);
  return a.difference(b).inDays;
}

/// Section header a note belongs to. Unchanged semantics from the old
/// `NoteList._dateSection`; only the injectable `now` is new.
String dateSection(DateTime d, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = calendarDayDiff(d, ref);
  if (diff >= 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff > -7) return 'This Week';
  return 'Older';
}

/// Timestamp shown on a note card. Always derived from the SAME calendar-day
/// bucket as [dateSection], so it can never contradict its header.
///
/// - today            -> elapsed clock: "just now", "5m ago", "3h ago"
/// - yesterday        -> 24h clock time: "23:00"
/// - 2..6 days ago    -> weekday abbrev: "Wed"
/// - 7+ days / future -> ISO date: "2026-09-06"
String relativeTime(DateTime d, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = calendarDayDiff(d, ref);
  if (diff >= 0) {
    final elapsed = ref.difference(d);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    return '${elapsed.inHours}h ago';
  }
  if (diff == -1) return _twoDigitHourMinute(d);
  if (diff > -7) return _weekdayAbbrev(d);
  return _isoDate(d);
}

String _twoDigitHourMinute(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _weekdayAbbrev(DateTime d) => kWeekdayNamesShort[d.weekday - 1];

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';