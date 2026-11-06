import '../models/note.dart';
import 'date_format.dart';
import 'note_kind.dart';

/// Paydays and the cutoff between them — how money is lived in the
/// Philippines: paid on the 15th and the 30th ("kinsenas at katapusan"),
/// so the question is "will it last until the next payday?", not "what did
/// I spend this calendar month?".

/// When pay arrives: days of the month (31 means the last day). The
/// default is the 15th and the 30th; in February the 30th is the 28th/29th.
class PaydaySettings {
  final List<int> days;

  const PaydaySettings(this.days);

  static const standard = PaydaySettings([15, 30]);
  static const prefsKey = 'payday_v1';

  factory PaydaySettings.fromJson(Map<String, dynamic> json) {
    final days =
        ((json['days'] as List?) ?? const [])
            .whereType<int>()
            .where((d) => d >= 1 && d <= 31)
            .toSet()
            .toList()
          ..sort();
    return days.isEmpty ? standard : PaydaySettings(days);
  }

  Map<String, dynamic> toJson() => {'days': days};

  /// "15th and 30th", "15th and last day", "Last day of the month".
  String get label {
    String one(int d) => d == 31 ? 'last day' : ordinal(d);
    if (days.length == 1) {
      return days.first == 31
          ? 'Last day of the month'
          : 'The ${ordinal(days.first)} of each month';
    }
    return '${one(days[0])} and ${one(days[1])}'.replaceFirstMapped(
      RegExp(r'^\w'),
      (m) => m[0]!.toUpperCase(),
    );
  }

  /// The paydays falling in [year]/[month], in order.
  List<DateTime> paydaysIn(int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    return {
      for (final d in days) DateTime(year, month, d > last ? last : d),
    }.toList()..sort();
  }

  @override
  bool operator ==(Object other) =>
      other is PaydaySettings && other.days.join(',') == days.join(',');

  @override
  int get hashCode => days.join(',').hashCode;
}

/// An optional budget for each cutoff, in one currency.
class CutoffBudget {
  final int amount;
  final String currency;

  const CutoffBudget(this.amount, this.currency);

  static const prefsKey = 'cutoff_budget_v1';

  static CutoffBudget? fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final currency = json['currency'];
    if (amount is! int || amount <= 0 || currency is! String) return null;
    return CutoffBudget(amount, currency);
  }

  Map<String, dynamic> toJson() => {'amount': amount, 'currency': currency};
}

/// One pay period: from a payday up to the day before the next.
class Cutoff {
  final DateTime start;
  final DateTime nextPayday;

  const Cutoff(this.start, this.nextPayday);

  DateTime get end => nextPayday.subtract(const Duration(days: 1));
  int get totalDays => _days(start, nextPayday);
  int dayIndex(DateTime now) => _days(start, _day(now)) + 1;
  int daysLeft(DateTime now) => _days(_day(now), nextPayday);

  /// "Oct 30 – Nov 14".
  String get rangeLabel =>
      '${monthShort(start.month)} ${start.day} – '
      '${monthShort(end.month)} ${end.day}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _days(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// "1st", "2nd", "15th", "30th".
String ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

/// The cutoff [now] falls in.
Cutoff cutoffFor(PaydaySettings settings, DateTime now) {
  final today = _day(now);
  final paydays = [
    for (var m = -2; m <= 2; m++)
      ...settings.paydaysIn(today.year, today.month + m),
  ];
  final start = paydays.lastWhere((d) => !d.isAfter(today));
  final next = paydays.firstWhere((d) => d.isAfter(today));
  return Cutoff(start, next);
}

/// The cutoff before [current].
Cutoff previousCutoff(PaydaySettings settings, Cutoff current) =>
    cutoffFor(settings, current.start.subtract(const Duration(days: 1)));

/// True when [now] is a payday.
bool isPayday(PaydaySettings settings, DateTime now) =>
    cutoffFor(settings, now).start == _day(now);

enum PaceStatus { onPace, overPace, overBudget }

/// What a cutoff's spending looks like.
class CutoffMoney {
  final Cutoff cutoff;
  final String currency;

  /// Spent from the payday through [asOf] (or the cutoff's end).
  final int spent;
  final int todaySpent;
  final CutoffBudget? budget;

  /// The category with the most spent, if any.
  final String? topCategory;

  /// Any real (non-sample) money was ever logged.
  final bool anyLogged;

  /// The day the figures are for (today, or the cutoff's last day).
  final DateTime asOf;

  const CutoffMoney({
    required this.cutoff,
    required this.currency,
    required this.spent,
    required this.todaySpent,
    required this.budget,
    required this.topCategory,
    required this.anyLogged,
    required this.asOf,
  });

  int get dayIndex => cutoff.dayIndex(asOf);
  int get daysLeft => cutoff.daysLeft(asOf);

  /// Budget left (negative when over); null without a budget.
  int? get left => budget == null ? null : budget!.amount - spent;

  /// What could be spent each remaining day (never below zero).
  int? get perDayLeft {
    final l = left;
    if (l == null) return null;
    return l <= 0 ? 0 : (l / daysLeft).floor();
  }

  /// Average spent per day so far.
  int get perDaySpent => (spent / dayIndex).round();

  /// Where spending should be by today on an even pace.
  int? get ideal => budget == null
      ? null
      : (budget!.amount * dayIndex / cutoff.totalDays).round();

  PaceStatus get status {
    final b = budget;
    if (b == null) return PaceStatus.onPace;
    if (spent > b.amount) return PaceStatus.overBudget;
    return spent <= ideal! * 1.05 ? PaceStatus.onPace : PaceStatus.overPace;
  }
}

/// Totals [cutoff]'s expenses up to [asOf] (inclusive). Sample data never
/// counts. Without a budget, the currency is the one most spent in.
CutoffMoney cutoffMoney(
  List<Note> notes,
  Cutoff cutoff,
  CutoffBudget? budget,
  DateTime asOf,
) {
  final day = _day(asOf).isAfter(cutoff.end) ? cutoff.end : _day(asOf);
  final from = cutoff.start;
  final until = day.add(const Duration(days: 1));
  final byCurrency = <String, int>{};
  final todayBy = <String, int>{};
  final byCategory = <String, Map<String, int>>{};
  var anyLogged = false;
  for (final n in notes) {
    if (!isVisibleFinanceNote(n)) continue;
    for (final e in n.amounts) {
      if (e.isDemo) continue;
      anyLogged = true;
      if ((e.type ?? n.type) != 'expense') continue;
      if (e.date.isBefore(from) || !e.date.isBefore(until)) continue;
      final cur = e.currency ?? n.currency ?? 'PHP';
      byCurrency[cur] = (byCurrency[cur] ?? 0) + e.amount;
      if (!e.date.isBefore(day)) todayBy[cur] = (todayBy[cur] ?? 0) + e.amount;
      final cats = byCategory.putIfAbsent(cur, () => {});
      cats[e.category] = (cats[e.category] ?? 0) + e.amount;
    }
  }
  var currency = budget?.currency;
  if (currency == null) {
    currency = 'PHP';
    var best = -1;
    byCurrency.forEach((cur, total) {
      if (total > best) {
        best = total;
        currency = cur;
      }
    });
  }
  String? top;
  var topAmount = 0;
  (byCategory[currency] ?? const {}).forEach((cat, total) {
    if (total > topAmount) {
      topAmount = total;
      top = cat;
    }
  });
  return CutoffMoney(
    cutoff: cutoff,
    currency: currency!,
    spent: byCurrency[currency] ?? 0,
    todaySpent: todayBy[currency] ?? 0,
    budget: budget,
    topCategory: top,
    anyLogged: anyLogged,
    asOf: day,
  );
}
