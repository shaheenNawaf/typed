import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/date_format.dart';
import 'package:typed/utils/date_grouping.dart';

void main() {
  group('dateSection', () {
    final now = DateTime(2026, 9, 26, 12, 0);

    test('same calendar day is Today', () {
      expect(dateSection(DateTime(2026, 9, 26, 0, 1), now: now), 'Today');
      expect(dateSection(DateTime(2026, 9, 26, 23, 59), now: now), 'Today');
    });

    test('one calendar day back is Yesterday', () {
      expect(dateSection(DateTime(2026, 9, 25, 23, 59), now: now), 'Yesterday');
    });

    test('two to six calendar days back is This Week', () {
      expect(dateSection(DateTime(2026, 9, 24), now: now), 'This Week');
      expect(dateSection(DateTime(2026, 9, 20), now: now), 'This Week');
    });

    test('seven or more calendar days back is Older', () {
      expect(dateSection(DateTime(2026, 9, 19), now: now), 'Older');
      expect(dateSection(DateTime(2026, 8, 27), now: now), 'Older');
    });

    test('a future date buckets as Today', () {
      expect(dateSection(DateTime(2026, 9, 27, 12, 0), now: now), 'Today');
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 9, 26, 12, 0);

    test('under a minute is just now', () {
      expect(
        relativeTime(DateTime(2026, 9, 26, 11, 59, 30), now: now),
        'just now',
      );
    });

    test('minutes are counted within the hour', () {
      expect(relativeTime(DateTime(2026, 9, 26, 11, 55), now: now), '5m ago');
    });

    test('hours are counted within the day', () {
      expect(relativeTime(DateTime(2026, 9, 26, 9, 0), now: now), '3h ago');
    });

    test('yesterday shows zero-padded clock time', () {
      expect(relativeTime(DateTime(2026, 9, 25, 9, 5), now: now), '09:05');
    });

    test('two to six days back shows the weekday abbreviation', () {
      expect(relativeTime(DateTime(2026, 9, 23, 12, 0), now: now), 'Wed');
    });

    test('a week or more back shows an ISO date', () {
      expect(
        relativeTime(DateTime(2026, 9, 16, 12, 0), now: now),
        '2026-09-16',
      );
    });
  });

  group('header and timestamp never contradict', () {
    test(
      'a note touched at 23:00 yesterday reads Yesterday 23:00 at 01:00 today',
      () {
        final now = DateTime(2026, 9, 26, 1, 0);
        final d = DateTime(2026, 9, 25, 23, 0);
        expect(dateSection(d, now: now), 'Yesterday');
        expect(relativeTime(d, now: now), '23:00');
      },
    );

    test('a note touched after midnight reads Today with elapsed minutes', () {
      final now = DateTime(2026, 9, 26, 1, 0);
      final d = DateTime(2026, 9, 26, 0, 30);
      expect(dateSection(d, now: now), 'Today');
      expect(relativeTime(d, now: now), '30m ago');
    });

    test('one minute apart across midnight splits Yesterday and Today', () {
      final now = DateTime(2026, 9, 26, 0, 0);
      final d = DateTime(2026, 9, 25, 23, 59);
      expect(dateSection(d, now: now), 'Yesterday');
      expect(relativeTime(d, now: now), '23:59');
    });

    test('same calendar day stays Today even when nearly a day apart', () {
      final now = DateTime(2026, 9, 26, 23, 59);
      final d = DateTime(2026, 9, 26, 0, 1);
      expect(dateSection(d, now: now), 'Today');
      expect(relativeTime(d, now: now), '23h ago');
    });

    test('a future date is Today and just now, never a negative duration', () {
      final now = DateTime(2026, 9, 26, 12, 0);
      final d = DateTime(2026, 9, 27, 12, 0);
      expect(dateSection(d, now: now), 'Today');
      expect(relativeTime(d, now: now), 'just now');
    });

    test('d equal to now is Today and just now', () {
      final now = DateTime(2026, 9, 26, 12, 0);
      expect(dateSection(now, now: now), 'Today');
      expect(relativeTime(now, now: now), 'just now');
    });

    test('a 23-hour gap across midnight still reads Yesterday', () {
      final now = DateTime(2026, 3, 9, 0, 0);
      final d = DateTime(2026, 3, 8, 1, 0);
      expect(dateSection(d, now: now), 'Yesterday');
      expect(relativeTime(d, now: now), '01:00');
    });

    test('timestamp never contradicts its section header', () {
      final now = DateTime(2026, 9, 26, 12, 0);
      for (var days = 0; days <= 40; days++) {
        for (final hour in [0, 6, 12, 18, 23]) {
          final d = DateTime(2026, 9, 26, hour).subtract(Duration(days: days));
          final section = dateSection(d, now: now);
          final stamp = relativeTime(d, now: now);
          if (section == 'Yesterday') {
            expect(stamp, isNot(contains('ago')), reason: '$d -> $section / $stamp');
            expect(stamp, matches(RegExp(r'^[0-2][0-9]:[0-5][0-9]$')));
          }
          if (section == 'Today') {
            expect(stamp, anyOf('just now', contains('m ago'), contains('h ago')));
            expect(stamp, isNot(contains('d ago')));
          }
          if (section == 'This Week') {
            expect(kWeekdayNamesShort, contains(stamp));
          }
          if (section == 'Older') {
            expect(stamp, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
          }
        }
      }
    });
  });
}