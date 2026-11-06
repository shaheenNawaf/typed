import '../voice/when_parser.dart';
import 'date_format.dart';

/// Dates on task lines.
///
/// A dated task is stored as `- [ ] <text> — <label>`, where the label is
/// [SpokenWhen.label] ("Fri, Nov 6", "Fri, Nov 6, 2 PM", "Fri, Nov 6,
/// 2:30 PM", "Fri, Nov 6, evening"). Voice memos write it; Home reads it
/// back to know what is due, and rewrites it to move a task to another day.
/// Anything else after a dash stays ordinary text ("Plan — big picture").

/// [text] is the task without its date (raw: markdown is kept).
typedef TaskDate = ({String text, SpokenWhen? when});

const _sep = ' — ';

final _label = RegExp(
  r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), '
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2})'
  r'(?:, (?:(\d{1,2})(?::(\d{2}))? (AM|PM)|(morning|afternoon|evening|tonight)))?$',
);

/// Splits a task line's text into the task and its date. A suffix that is
/// not a date label leaves the whole line as the text.
TaskDate splitTaskDate(String raw, DateTime now) {
  final i = raw.lastIndexOf(_sep);
  if (i <= 0) return (text: raw, when: null);
  final when = parseTaskLabel(raw.substring(i + _sep.length).trim(), now);
  if (when == null) return (text: raw, when: null);
  return (text: raw.substring(0, i).trimRight(), when: when);
}

/// The line text for [text] due [when] (no date when [when] is null).
String withTaskDate(String text, SpokenWhen? when) =>
    when == null ? text : '$text$_sep${when.label}';

/// [when] moved to [day], keeping its time or part of the day.
SpokenWhen moveToDay(SpokenWhen? when, DateTime day) => SpokenWhen(
  DateTime(day.year, day.month, day.day),
  hour: when?.hour,
  minute: when?.minute,
  partOfDay: when?.partOfDay,
);

/// Reads a [SpokenWhen.label] back. Labels carry no year: the year that
/// puts the date nearest to [now] (and on the right weekday) wins, so
/// "Thu, Jan 2" written in late December means the coming January.
SpokenWhen? parseTaskLabel(String label, DateTime now) {
  final m = _label.firstMatch(label);
  if (m == null) return null;
  final weekday = kWeekdayNamesShort.indexOf(m[1]!) + 1;
  final month = kMonthNamesShort.indexOf(m[2]!) + 1;
  final dayNum = int.parse(m[3]!);
  final today = DateTime(now.year, now.month, now.day);
  DateTime? best;
  var bestScore = 1 << 30;
  for (final y in [now.year - 1, now.year, now.year + 1]) {
    final d = DateTime(y, month, dayNum);
    if (d.month != month) continue; // Feb 30 and friends
    final distance = d.difference(today).inDays.abs();
    // A matching weekday outweighs a few months of distance.
    final score = distance + (d.weekday == weekday ? 0 : 400);
    if (score < bestScore) {
      best = d;
      bestScore = score;
    }
  }
  if (best == null) return null;
  int? hour;
  int? minute;
  if (m[6] != null) {
    final h = int.parse(m[4]!);
    if (h < 1 || h > 12) return null;
    hour = h % 12 + (m[6] == 'PM' ? 12 : 0);
    minute = int.tryParse(m[5] ?? '') ?? 0;
    if (minute > 59) return null;
  }
  return SpokenWhen(best, hour: hour, minute: minute, partOfDay: m[7]);
}
