import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/task_dates.dart';
import 'package:typed/voice/when_parser.dart';

void main() {
  // Saturday, Nov 7 2026, mid-morning.
  final now = DateTime(2026, 11, 7, 10);

  group('splitTaskDate', () {
    test('every label form round-trips', () {
      for (final when in [
        SpokenWhen(DateTime(2026, 11, 6)),
        SpokenWhen(DateTime(2026, 11, 6), hour: 14, minute: 0),
        SpokenWhen(DateTime(2026, 11, 6), hour: 14, minute: 30),
        SpokenWhen(DateTime(2026, 11, 9), hour: 9, minute: 5),
        SpokenWhen(DateTime(2026, 11, 7), hour: 0, minute: 0),
        SpokenWhen(DateTime(2026, 11, 7), hour: 12, minute: 0),
        SpokenWhen(DateTime(2026, 11, 8), partOfDay: 'evening'),
        SpokenWhen(DateTime(2026, 11, 8), partOfDay: 'tonight'),
      ]) {
        final line = withTaskDate('Call the dentist', when);
        final back = splitTaskDate(line, now);
        expect(back.text, 'Call the dentist', reason: line);
        expect(back.when!.label, when.label, reason: line);
        expect(back.when!.day, when.day, reason: line);
      }
    });

    test('the year is the one nearest now, on the right weekday', () {
      final dec = DateTime(2026, 12, 28);
      // Jan 2 2027 is a Saturday.
      expect(splitTaskDate('Pay rent — Sat, Jan 2', dec).when!.day,
          DateTime(2027, 1, 2));
      final jan = DateTime(2027, 1, 3);
      // Dec 28 2026 is a Monday.
      expect(splitTaskDate('Pay rent — Mon, Dec 28', jan).when!.day,
          DateTime(2026, 12, 28));
    });

    test('a dash that is not a date stays part of the text', () {
      for (final line in [
        'Plan — big picture',
        'Read — Mon, Nov',
        'Call — Fri, Feb 30',
        'Call — Fri, Nov 6, 13 PM',
        'No date here',
      ]) {
        final s = splitTaskDate(line, now);
        expect(s.text, line);
        expect(s.when, isNull);
      }
    });

    test('only the last dash is the date', () {
      final s = splitTaskDate('Plan — the trip — Fri, Nov 6', now);
      expect(s.text, 'Plan — the trip');
      expect(s.when!.day, DateTime(2026, 11, 6));
    });
  });

  test('moveToDay keeps the time', () {
    final w = SpokenWhen(DateTime(2026, 11, 6), hour: 14, minute: 30);
    final moved = moveToDay(w, DateTime(2026, 11, 8, 23));
    expect(moved.day, DateTime(2026, 11, 8));
    expect(moved.hour, 14);
    expect(moved.minute, 30);
    expect(moveToDay(null, DateTime(2026, 11, 8)).label, 'Sun, Nov 8');
  });
}
