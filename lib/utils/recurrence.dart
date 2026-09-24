/// Pure, calendar-safe recurrence math for repeating money entries.
///
/// Occurrences are computed from the master's anchor date rather than
/// iteratively from the previous occurrence, so month-end clamping never
/// permanently drifts a series (Jan 31 -> Feb 28 -> Mar 31, not Mar 28).
library;

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The [index]-th (1-based) occurrence of a series anchored at [anchor].
DateTime occurrenceFor(DateTime anchor, String interval, int index) {
  final n = index < 1 ? 1 : index;
  switch (interval) {
    case 'weekly':
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + n * 7,
        anchor.hour,
        anchor.minute,
        anchor.second,
        anchor.millisecond,
        anchor.microsecond,
      );
    case 'monthly':
      final totalMonths = anchor.month - 1 + n;
      final year = anchor.year + totalMonths ~/ 12;
      final month = totalMonths % 12 + 1;
      return DateTime(
        year,
        month,
        anchor.day.clamp(1, _daysInMonth(year, month)),
        anchor.hour,
        anchor.minute,
        anchor.second,
        anchor.millisecond,
        anchor.microsecond,
      );
    case 'yearly':
      final year = anchor.year + n;
      return DateTime(
        year,
        anchor.month,
        anchor.day.clamp(1, _daysInMonth(year, anchor.month)),
        anchor.hour,
        anchor.minute,
        anchor.second,
        anchor.millisecond,
        anchor.microsecond,
      );
    case 'daily':
    default:
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + n,
        anchor.hour,
        anchor.minute,
        anchor.second,
        anchor.millisecond,
        anchor.microsecond,
      );
  }
}

/// First occurrence index that is not already covered by [lastGenerated].
int _startIndex(DateTime anchor, String interval, DateTime after) {
  final dayDiff = dateOnly(after).difference(dateOnly(anchor)).inDays;
  final n = switch (interval) {
    'weekly' => dayDiff ~/ 7,
    'monthly' => (after.year - anchor.year) * 12 + (after.month - anchor.month),
    'yearly' => after.year - anchor.year,
    _ => dayDiff,
  };
  return n < 0 ? 1 : n + 1;
}

/// Occurrence dates strictly after [lastGenerated] up to [today], honouring
/// an optional [end] bound. Hard-capped at [maxCount] so a long-dormant
/// master cannot backfill thousands of entries in a single launch.
List<DateTime> plannedOccurrences({
  required DateTime anchor,
  required String interval,
  required DateTime lastGenerated,
  required DateTime today,
  DateTime? end,
  int maxCount = 1000,
}) {
  final upTo = dateOnly(today);
  final endDate = end == null ? null : dateOnly(end);
  final lastDate = dateOnly(lastGenerated);
  final result = <DateTime>[];
  var index = _startIndex(anchor, interval, lastGenerated);
  while (result.length < maxCount) {
    final occurrence = dateOnly(occurrenceFor(anchor, interval, index));
    index++;
    if (occurrence.isAfter(upTo) ||
        (endDate != null && occurrence.isAfter(endDate))) {
      break;
    }
    if (!occurrence.isAfter(lastDate)) continue;
    result.add(occurrence);
  }
  return result;
}
