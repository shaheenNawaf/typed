import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/date_format.dart';

void main() {
  final now = DateTime(2026, 9, 26, 14, 30);

  group('periodName', () {
    test('week reads This week regardless of the anchor date', () {
      expect(periodName('week', now: now), 'This week');
    });

    test('month reads the long month name and year', () {
      expect(periodName('month', now: now), 'September 2026');
    });

    test('month rolls over correctly in January', () {
      expect(periodName('month', now: DateTime(2027, 1, 1)), 'January 2027');
    });

    test('year reads the four-digit year', () {
      expect(periodName('year', now: now), '2026');
    });

    test('all reads All time', () {
      expect(periodName('all', now: now), 'All time');
    });

    test('an unknown period falls back to All time', () {
      expect(periodName('fortnight', now: now), 'All time');
    });
  });
}