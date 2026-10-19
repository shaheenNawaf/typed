import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/when_parser.dart';

void main() {
  // Monday, Oct 19 2026, 10:00.
  final now = DateTime(2026, 10, 19, 10);

  String? label(String s, [DateTime? at]) {
    final m = parseSpokenWhen(s, at ?? now);
    return m == null ? null : '${m.text} | ${m.when.label}';
  }

  test('relative days', () {
    expect(label('call the dentist tomorrow'),
        'call the dentist | Tue, Oct 20');
    expect(label('pay rent today'), 'pay rent | Mon, Oct 19');
    expect(label('book flights the day after tomorrow'),
        'book flights | Wed, Oct 21');
    expect(label('clean the garage this weekend'),
        'clean the garage | Sat, Oct 24');
    expect(label('renew the passport next week'),
        'renew the passport | Mon, Oct 26');
    expect(label('follow up in 3 days'), 'follow up | Thu, Oct 22');
    expect(label('check back in two weeks'), 'check back | Mon, Nov 2');
  });

  test('weekdays', () {
    expect(label('email Sam on Friday'), 'email Sam | Fri, Oct 23');
    expect(label('email Sam Friday'), 'email Sam | Fri, Oct 23');
    // Said on a Monday: "next Friday" skips the one later this week.
    expect(label('email Sam next Friday'), 'email Sam | Fri, Oct 30');
    // Said on a Sunday: the coming Friday is already next week's.
    final sunday = DateTime(2026, 10, 18, 9);
    expect(label('email Sam next Friday', sunday), 'email Sam | Fri, Oct 23');
    expect(label('water plants this Sunday', sunday),
        'water plants | Sun, Oct 18');
    expect(label('water plants Sunday', sunday), 'water plants | Sun, Oct 25');
  });

  test('dates', () {
    expect(label('dentist on October 30th'), 'dentist | Fri, Oct 30');
    expect(label('dentist on the 3rd of November'), 'dentist | Tue, Nov 3');
    // Already past this year: next year's.
    expect(label('renew the lease March 2'), 'renew the lease | Tue, Mar 2');
  });

  test('times', () {
    expect(label('call the bank tomorrow at 3'),
        'call the bank | Tue, Oct 20, 3 PM');
    expect(label('call the bank tomorrow at 9:30 am'),
        'call the bank | Tue, Oct 20, 9:30 AM');
    expect(label('meet Priya at noon'), 'meet Priya | Mon, Oct 19, 12 PM');
    expect(label('take the bins out tonight'),
        'take the bins out | Mon, Oct 19, tonight');
    expect(label('take the bins out tonight at 9'),
        'take the bins out | Mon, Oct 19, 9 PM');
    expect(label('run tomorrow morning'), 'run | Tue, Oct 20, morning');
    // A time already past today means tomorrow.
    expect(label('call mom at 8 am'), 'call mom | Tue, Oct 20, 8 AM');
    expect(label('call mom at 5'), 'call mom | Mon, Oct 19, 5 PM');
  });

  test('nothing to find', () {
    expect(label('buy eggs and bread'), isNull);
    expect(label('read chapter 3'), isNull);
    expect(label('it may rain'), isNull);
    expect(label('increase savings by 30 percent'), isNull);
    expect(label('meet at 30'), isNull);
  });
}
