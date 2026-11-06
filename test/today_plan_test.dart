import 'package:flutter_test/flutter_test.dart';
import 'package:typed/home/today_plan.dart';
import 'package:typed/models/note.dart';

void main() {
  // Saturday, Nov 7 2026, 9:00.
  final now = DateTime(2026, 11, 7, 9);

  Note list(String id, String content, {int minutesAgo = 0}) => Note(
        id: id,
        title: id,
        content: content,
        tags: const ['todo'],
        type: 'todo',
        updatedAt: now.subtract(Duration(minutes: minutesAgo)),
      );

  test('overdue first, then by time, then undated', () {
    final plan = buildTodayPlan([
      list('errands', '- [ ] Buy eggs\n- [ ] Pay Meralco — Fri, Nov 6\n'),
      list(
        'voice',
        '- [ ] Pick up Mia — Sat, Nov 7, 5:30 PM\n'
            '- [ ] Call the dentist — Sat, Nov 7, 2 PM\n'
            '- [ ] Water plants — Sat, Nov 7\n',
        minutesAgo: 5,
      ),
    ], now);
    expect(plan.focus!.text, 'Pay Meralco');
    expect(plan.focus!.standing, TaskStanding.overdue);
    expect(plan.rest.map((i) => i.text), [
      'Water plants',
      'Buy eggs',
      'Call the dentist',
      'Pick up Mia',
    ]);
    expect(plan.rest.map((i) => i.group), [
      TodayGroup.anyTime,
      TodayGroup.anyTime,
      TodayGroup.afternoon,
      TodayGroup.evening,
    ]);
    expect(plan.forToday, 4);
    expect(plan.isQuiet, isFalse);
  });

  test('timed today comes before untimed today as the focus', () {
    final plan = buildTodayPlan([
      list('l', '- [ ] Untimed — Sat, Nov 7\n- [ ] Timed — Sat, Nov 7, 4 PM\n'),
    ], now);
    expect(plan.focus!.text, 'Timed');
    expect(plan.focus!.timeLabel, '4:00 PM');
  });

  test('group boundaries', () {
    TodayGroup groupAt(String time) => buildTodayPlan([
          list('l', '- [ ] Focus — Fri, Nov 6\n- [ ] T — Sat, Nov 7, $time\n'),
        ], now).rest.single.group;
    expect(groupAt('11:59 AM'), TodayGroup.morning);
    expect(groupAt('12 PM'), TodayGroup.afternoon);
    expect(groupAt('4:59 PM'), TodayGroup.afternoon);
    expect(groupAt('5 PM'), TodayGroup.evening);
    expect(groupAt('morning'), TodayGroup.morning);
    expect(groupAt('afternoon'), TodayGroup.afternoon);
    expect(groupAt('tonight'), TodayGroup.evening);
  });

  test('a quiet day has no focus and keeps undated aside', () {
    final plan = buildTodayPlan([
      list('l', '- [ ] Buy eggs\n- [ ] Return books\n- [ ] Later — Mon, Nov 9\n'),
    ], now);
    expect(plan.isQuiet, isTrue);
    expect(plan.focus, isNull);
    expect(plan.rest, isEmpty);
    expect(plan.undated.map((i) => i.text), ['Buy eggs', 'Return books']);
  });

  test('tomorrow is collected; later days and done lines are left out', () {
    final plan = buildTodayPlan([
      list(
        'l',
        '- [ ] Slides — Sun, Nov 8, 9 AM\n'
            '- [ ] Books — Sun, Nov 8\n'
            '- [ ] Far — Fri, Nov 20\n'
            '- [x] Done — Sat, Nov 7\n',
      ),
    ], now);
    expect(plan.tomorrow.map((i) => i.text), ['Books', 'Slides']);
    // Nothing due now: Today is empty, Tomorrow has two.
    expect(plan.isEmpty, isTrue);
    expect(plan.dueToday, isEmpty);
    expect(plan.overdue, isEmpty);
  });

  test('archived, deleted and guide notes are ignored', () {
    final plan = buildTodayPlan([
      list('a', '- [ ] Hidden — Sat, Nov 7')..isArchived = true,
      list('d', '- [ ] Gone — Sat, Nov 7')..isDeleted = true,
      Note(
        id: 'x_guide',
        title: 'Guide',
        content: '- [ ] Try this — Sat, Nov 7',
        tags: const ['guide'],
      ),
    ], now);
    expect(plan.isEmpty, isTrue);
  });

  test('only three undated tasks join a busy day', () {
    final plan = buildTodayPlan([
      list('l', '- [ ] Due — Sat, Nov 7\n- [ ] a\n- [ ] b\n- [ ] c\n- [ ] d\n'),
    ], now);
    expect(plan.rest.map((i) => i.text), ['a', 'b', 'c']);
    expect(plan.forToday, 4);
  });
}
