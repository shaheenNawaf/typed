import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/recurrence.dart';

void main() {
  group('occurrenceFor', () {
    test('yearly advances exactly one year (was biennial)', () {
      expect(occurrenceFor(DateTime(2026, 5, 15), 'yearly', 1),
          DateTime(2027, 5, 15));
      expect(occurrenceFor(DateTime(2026, 5, 15), 'yearly', 3),
          DateTime(2029, 5, 15));
    });

    test('leap-day yearly anchors clamp to the 28th and recover', () {
      expect(occurrenceFor(DateTime(2028, 2, 29), 'yearly', 1),
          DateTime(2029, 2, 28));
      expect(occurrenceFor(DateTime(2028, 2, 29), 'yearly', 4),
          DateTime(2032, 2, 29));
    });

    test('monthly clamps to month end but snaps back, never drifts', () {
      final anchor = DateTime(2026, 1, 31);
      expect(occurrenceFor(anchor, 'monthly', 1), DateTime(2026, 2, 28));
      expect(occurrenceFor(anchor, 'monthly', 2), DateTime(2026, 3, 31));
      expect(occurrenceFor(anchor, 'monthly', 3), DateTime(2026, 4, 30));
      expect(occurrenceFor(anchor, 'monthly', 4), DateTime(2026, 5, 31));
    });

    test('daily and weekly normalize across month boundaries', () {
      expect(
          occurrenceFor(DateTime(2026, 1, 30), 'daily', 2), DateTime(2026, 2, 1));
      expect(occurrenceFor(DateTime(2026, 1, 30), 'weekly', 1),
          DateTime(2026, 2, 6));
    });

    test('unknown intervals behave like daily', () {
      expect(occurrenceFor(DateTime(2026, 1, 1), 'fortnightly', 1),
          DateTime(2026, 1, 2));
    });

    test('indexes below 1 clamp to the first occurrence', () {
      expect(occurrenceFor(DateTime(2026, 1, 1), 'monthly', 0),
          DateTime(2026, 2, 1));
    });
  });

  group('plannedOccurrences', () {
    test('generates strictly after lastGenerated up to today', () {
      final dates = plannedOccurrences(
        anchor: DateTime(2026, 1, 1),
        interval: 'monthly',
        lastGenerated: DateTime(2026, 1, 1),
        today: DateTime(2026, 4, 15),
      );
      expect(dates, [
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
      ]);
    });

    test('respects the end bound', () {
      final dates = plannedOccurrences(
        anchor: DateTime(2026, 1, 1),
        interval: 'daily',
        lastGenerated: DateTime(2026, 1, 1),
        today: DateTime(2026, 1, 10),
        end: DateTime(2026, 1, 3),
      );
      expect(dates, [DateTime(2026, 1, 2), DateTime(2026, 1, 3)]);
    });

    test('catch-up backfill is hard-capped', () {
      final dates = plannedOccurrences(
        anchor: DateTime(2000, 1, 1),
        interval: 'daily',
        lastGenerated: DateTime(2000, 1, 1),
        today: DateTime(2026, 1, 1),
        maxCount: 10,
      );
      expect(dates, hasLength(10));
    });

    test('already-caught-up masters yield nothing', () {
      final dates = plannedOccurrences(
        anchor: DateTime(2026, 1, 1),
        interval: 'monthly',
        lastGenerated: DateTime(2026, 4, 1),
        today: DateTime(2026, 4, 15),
      );
      expect(dates, isEmpty);
    });

    test('future anchors yield nothing until the first date passes', () {
      final dates = plannedOccurrences(
        anchor: DateTime(2027, 6, 1),
        interval: 'yearly',
        lastGenerated: DateTime(2027, 6, 1),
        today: DateTime(2026, 4, 15),
      );
      expect(dates, isEmpty);
    });

    test('drifted legacy series self-heals to the anchor day', () {
      // Old generator drifted Jan 31 -> Feb 28 -> Mar 28; recovery starts
      // from the anchor, so the next occurrence after Mar 28 is Apr 30,
      // and May returns to the 31st.
      final dates = plannedOccurrences(
        anchor: DateTime(2026, 1, 31),
        interval: 'monthly',
        lastGenerated: DateTime(2026, 3, 28),
        today: DateTime(2026, 5, 31),
      );
      expect(dates, [DateTime(2026, 4, 30), DateTime(2026, 5, 31)]);
    });
  });
}
