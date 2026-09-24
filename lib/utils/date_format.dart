/// Shared date labels. Month names were previously duplicated as local
/// const lists in home_screen, editor, entry_sheet, and note_storage.
const List<String> kMonthNamesLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> kMonthNamesShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String monthName(int month) => kMonthNamesLong[month - 1];

String monthShort(int month) => kMonthNamesShort[month - 1];

String _two(int n) => n.toString().padLeft(2, '0');

/// ISO-style label used in money tables: 2026-09-06.
String shortDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Human label used in forms: Sep 6, 2026.
String mediumDate(DateTime d) => '${monthShort(d.month)} ${d.day}, ${d.year}';

/// Short label used in quick-note titles: Sep 6.
String dayLabel(DateTime d) => '${monthShort(d.month)} ${d.day}';

const List<String> kWeekdayNamesShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Human day label for recent-transaction rows: Today / Yesterday / weekday
/// abbreviation within the last 6 days, absolute M/D beyond (and for dates
/// further in the future than tomorrow). [now] is injectable for tests.
String relativeDayLabel(DateTime d, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff >= 2 && diff <= 6) return kWeekdayNamesShort[day.weekday - 1];
  if (diff < 0 && diff >= -6) return kWeekdayNamesShort[day.weekday - 1];
  return '${d.month}/${d.day}';
}
