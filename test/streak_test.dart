import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/streak.dart';

Note note(
  String id,
  DateTime updatedAt, {
  bool archived = false,
  bool deleted = false,
}) => Note(
  id: id,
  title: id,
  content: '',
  tags: const [],
  updatedAt: updatedAt,
  isArchived: archived,
  isDeleted: deleted,
);

void main() {
  final now = DateTime(2026, 8, 8, 12);

  test('counts consecutive writing days through today', () {
    final result = computeWritingStreak([
      note('today', now),
      note('yesterday', now.subtract(const Duration(days: 1))),
      note('two-days', now.subtract(const Duration(days: 2))),
    ], now: now);

    expect(result.days, 3);
    expect(result.writtenToday, isTrue);
    expect(result.activeDays, 3);
  });

  test('keeps yesterday streak alive when today is empty', () {
    final result = computeWritingStreak([
      note('yesterday', now.subtract(const Duration(days: 1))),
      note('two-days', now.subtract(const Duration(days: 2))),
    ], now: now);

    expect(result.days, 2);
    expect(result.writtenToday, isFalse);
  });

  test('gaps break the streak and inactive notes do not count', () {
    final result = computeWritingStreak([
      note('today', now),
      note('gap', now.subtract(const Duration(days: 2))),
      note('archived', now.subtract(const Duration(days: 1)), archived: true),
      note('deleted', now.subtract(const Duration(days: 3)), deleted: true),
    ], now: now);

    expect(result.days, 1);
    expect(result.activeDays, 2);
  });
}
