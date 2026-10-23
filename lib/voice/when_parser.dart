import '../utils/date_format.dart';

/// When a spoken task is due, resolved against the day it was said.
class SpokenWhen {
  /// The calendar day (time of day zeroed).
  final DateTime day;

  /// Hour and minute when a clock time was said ("at 3", "3:30 pm").
  final int? hour;
  final int? minute;

  /// "morning", "afternoon", "evening" or "tonight" when said without a
  /// clock time.
  final String? partOfDay;

  const SpokenWhen(this.day, {this.hour, this.minute, this.partOfDay});

  /// When a reminder for it should fire: the clock time if one was said,
  /// else a sensible hour for the part of the day, else 9 AM.
  DateTime get at {
    final (h, m) = hour != null
        ? (hour!, minute ?? 0)
        : switch (partOfDay) {
            'morning' => (9, 0),
            'afternoon' => (14, 0),
            'evening' => (18, 0),
            'tonight' => (20, 0),
            _ => (9, 0),
          };
    return DateTime(day.year, day.month, day.day, h, m);
  }

  /// [label] for a picked date/time (the review sheet's date chip).
  factory SpokenWhen.fromDateTime(DateTime at, {bool hasTime = true}) =>
      SpokenWhen(
        DateTime(at.year, at.month, at.day),
        hour: hasTime ? at.hour : null,
        minute: hasTime ? at.minute : null,
      );

  /// "Mon, Oct 20", "Mon, Oct 20, 3 PM", "Mon, Oct 20, 3:30 PM",
  /// "Mon, Oct 20, evening". Absolute on purpose: "tomorrow" in a note
  /// read next week would mean the wrong day.
  String get label {
    final date =
        '${kWeekdayNamesShort[day.weekday - 1]}, '
        '${monthShort(day.month)} ${day.day}';
    if (hour != null) {
      final h = hour! % 12 == 0 ? 12 : hour! % 12;
      final m = (minute ?? 0) == 0
          ? ''
          : ':${minute.toString().padLeft(2, '0')}';
      return '$date, $h$m ${hour! < 12 ? 'AM' : 'PM'}';
    }
    if (partOfDay != null) return '$date, $partOfDay';
    return date;
  }
}

/// A task's text with its spoken date or time taken out.
class WhenMatch {
  final String text;
  final SpokenWhen when;
  const WhenMatch(this.text, this.when);
}

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];
const _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

final _weekdayRe = _weekdays.join('|');
final _monthRe = _months
    .map((m) => m.length > 3 ? '${m.substring(0, 3)}(?:${m.substring(3)})?' : m)
    .join('|');

// ── day phrases ───────────────────────────────────────────────────────────

final _dayPattern = RegExp(
  '\\b(?:'
  '(?<dat>(?:the\\s+)?day\\s+after\\s+tomorrow)'
  '|(?<tomorrow>tomorrow|tmrw|tomorow)'
  '|(?<today>today|tonight)'
  '|(?<weekend>(?:this\\s+)?weekend)'
  '|(?<nextweek>next\\s+week)'
  '|(?<inn>in\\s+(?<n>\\d+|a|one|two|three|four|five|six|seven)\\s+(?<unit>days?|weeks?))'
  '|(?:(?<mod>this|next|on|by|until|till)\\s+)?(?<wd>$_weekdayRe)'
  '|(?:on\\s+)?(?:the\\s+)?(?<d1>\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(?<m1>$_monthRe)'
  '|(?:on\\s+)?(?<m2>$_monthRe)\\s+(?:the\\s+)?(?<d2>\\d{1,2})(?:st|nd|rd|th)?'
  ')\\b',
  caseSensitive: false,
);

// ── time phrases ──────────────────────────────────────────────────────────

final _timePattern = RegExp(
  r'\b(?:'
  r'(?:at|by|around|before)\s+(?<named>noon|midday|midnight)'
  r'|(?<named2>noon|midnight)'
  r'|(?:(?:at|by|around|before)\s+)?(?<h>\d{1,2})(?::(?<m>\d{2}))?\s*(?<ap>a\.?m\.?|p\.?m\.?)'
  r'|(?:at|by|around|before)\s+(?<h2>\d{1,2})(?::(?<m2>\d{2}))?(?!\s*(?:days?|weeks?|minutes?|hours?|percent|%|of\b))'
  r"|(?<o>\d{1,2})\s+o'?clock"
  r'|(?:in\s+the\s+|this\s+)?(?<part>morning|afternoon|evening)'
  r')\b',
  caseSensitive: false,
);

const _words = {
  'a': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
};

/// Finds a spoken date and/or time in [task], resolves it against [now] and
/// returns the task with that phrase removed. Null when nothing was said.
WhenMatch? parseSpokenWhen(String task, DateTime now) {
  final m = _parse(task, now);
  if (m == null || m.text.isEmpty) return null;
  return m;
}

/// The date or time when [phrase] is nothing else ("Tomorrow", "For the
/// weekend", "Okay, on Friday"); null when it says more than that.
SpokenWhen? parseWhenOnly(String phrase, DateTime now) {
  final m = _parse(phrase, now);
  if (m == null) return null;
  final rest = m.text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z' ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_glue.contains(w));
  return rest.isEmpty ? m.when : null;
}

const _glue = {
  'for',
  'the',
  'on',
  'at',
  'by',
  'this',
  'next',
  'so',
  'okay',
  'ok',
  'and',
  'um',
  'uh',
  'well',
  'right',
  'then',
  'also',
  'stuff',
  'things',
  'plan',
};

WhenMatch? _parse(String task, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  var text = task;
  DateTime? day;
  String? part;
  int? hour;
  int? minute;

  final d = _dayPattern.firstMatch(text);
  if (d != null) {
    day = _resolveDay(d, today, now);
    if (d.namedGroup('today')?.toLowerCase() == 'tonight') part = 'tonight';
    if (day != null) text = _cut(text, d);
  }

  final t = _timePattern.firstMatch(text);
  if (t != null) {
    final named = (t.namedGroup('named') ?? t.namedGroup('named2'))
        ?.toLowerCase();
    if (named != null) {
      hour = named == 'midnight' ? 0 : 12;
      minute = 0;
    } else if (t.namedGroup('h') != null) {
      hour = int.parse(t.namedGroup('h')!) % 12;
      minute = int.tryParse(t.namedGroup('m') ?? '') ?? 0;
      if (t.namedGroup('ap')!.toLowerCase().startsWith('p')) hour += 12;
    } else if (t.namedGroup('h2') != null || t.namedGroup('o') != null) {
      final h = int.parse(t.namedGroup('h2') ?? t.namedGroup('o')!);
      minute = int.tryParse(t.namedGroup('m2') ?? '') ?? 0;
      // A bare "at 3" in a to-do is almost always the afternoon; 8–11 are
      // mornings; "tonight at 9" is evening.
      hour = part == 'tonight' && h < 12
          ? h + 12
          : (h >= 1 && h <= 7)
          ? h + 12
          : h;
    } else {
      part = t.namedGroup('part')!.toLowerCase();
    }
    if (hour != null && hour > 23) hour = null;
    if (hour != null || part != null) text = _cut(text, t);
  }

  if (day == null && hour == null && part == null) return null;
  // A time with no day means today, or tomorrow once that time has passed.
  day ??=
      hour != null &&
          (hour < now.hour || (hour == now.hour && (minute ?? 0) <= now.minute))
      ? today.add(const Duration(days: 1))
      : today;
  if (hour != null) part = null;
  final cleaned = text
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceFirst(
        RegExp(r'\s+(?:on|at|by|for|this|until|till)$', caseSensitive: false),
        '',
      )
      .replaceFirst(RegExp(r'[\s,;-]+$'), '')
      .trim();
  return WhenMatch(
    cleaned,
    SpokenWhen(
      day,
      hour: hour,
      minute: hour == null ? null : minute,
      partOfDay: part,
    ),
  );
}

String _cut(String text, RegExpMatch m) =>
    (text.substring(0, m.start) + text.substring(m.end)).trim();

DateTime? _resolveDay(RegExpMatch d, DateTime today, DateTime now) {
  if (d.namedGroup('dat') != null) return today.add(const Duration(days: 2));
  if (d.namedGroup('tomorrow') != null) {
    return today.add(const Duration(days: 1));
  }
  if (d.namedGroup('today') != null) return today;
  if (d.namedGroup('weekend') != null) {
    // The coming Saturday (today, if it is Saturday).
    return today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));
  }
  if (d.namedGroup('nextweek') != null) {
    return today.add(Duration(days: 8 - today.weekday)); // next Monday
  }
  if (d.namedGroup('inn') != null) {
    final raw = d.namedGroup('n')!.toLowerCase();
    final n = int.tryParse(raw) ?? _words[raw] ?? 1;
    final weeks = d.namedGroup('unit')!.toLowerCase().startsWith('w');
    return today.add(Duration(days: weeks ? n * 7 : n));
  }
  final wd = d.namedGroup('wd');
  if (wd != null) {
    final target = _weekdays.indexOf(wd.toLowerCase()) + 1;
    final mod = d.namedGroup('mod')?.toLowerCase();
    var ahead = (target - today.weekday) % 7;
    if (ahead == 0 && mod != 'this') ahead = 7;
    // "next Friday" said early in the week skips the one coming up.
    if (mod == 'next' && today.weekday + ahead <= 7) ahead += 7;
    return today.add(Duration(days: ahead));
  }
  final m = d.namedGroup('m1') ?? d.namedGroup('m2');
  final dd = d.namedGroup('d1') ?? d.namedGroup('d2');
  if (m != null && dd != null) {
    final month =
        _months.indexWhere(
          (x) => x.startsWith(m.toLowerCase().substring(0, 3)),
        ) +
        1;
    final dayNum = int.parse(dd);
    if (month < 1 || dayNum < 1 || dayNum > 31) return null;
    var date = DateTime(today.year, month, dayNum);
    if (date.month != month) return null; // Feb 31 and friends
    // A date already past this year means next year's.
    if (date.isBefore(today)) date = DateTime(today.year + 1, month, dayNum);
    return date;
  }
  return null;
}
