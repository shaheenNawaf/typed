import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/spend_parser.dart';
import 'package:typed/voice/voice_shaper.dart';

void main() {
  group('amounts', () {
    test('spent N on X', () {
      final s = parseSpends('spent 250 on lunch at Jollibee');
      expect(s, hasLength(1));
      expect(s.single.amount, '250');
      expect(s.single.note, 'Lunch at Jollibee');
      expect(s.single.category, 'Food');
      expect(s.single.type, 'expense');
    });

    test('currency symbols, words and thousands separators', () {
      expect(parseSpends('₱1,200 for the electric bill').single.amount, '1200');
      expect(parseSpends('paid 99.50 pesos for load').single.amount, '99.50');
      expect(parseSpends('grab 180').single.category, 'Transport');
      expect(parseSpends('netflix 2k').single.amount, '2000');
    });

    test('spoken numbers become digits', () {
      expect(wordsToDigits('two hundred fifty pesos'), '250 pesos');
      expect(wordsToDigits('fifteen hundred'), '1500');
      expect(wordsToDigits('three thousand and five'), '3005');
      expect(wordsToDigits('1.5k'), '1500');
      expect(wordsToDigits('a coffee and a cake'), 'a coffee and a cake');
      expect(
        parseSpends('spent two hundred fifty on coffee').single.amount,
        '250',
      );
    });

    test('income is recognised', () {
      final s = parseSpends('got paid 15000 salary').single;
      expect(s.type, 'income');
      expect(s.category, 'Salary');
      expect(
        parseSpends('sold my old phone for 3000').single.category,
        'Income',
      );
    });
  });

  group('not money', () {
    test('times, dates and counts are ignored', () {
      expect(parseSpends('call the dentist at 3 pm'), isEmpty);
      expect(parseSpends('meeting on the 15th'), isEmpty);
      expect(parseSpends('buy 2 eggs'), isEmpty);
      expect(parseSpends('jog for 30 minutes every morning'), isEmpty);
      expect(
        parseSpends('finish chapter 12 of the book tonight please'),
        isEmpty,
      );
    });

    test('a long clause with a bare number and no verb is not money', () {
      expect(
        parseSpends('there were 40 people at the talk about local first'),
        isEmpty,
      );
    });
  });

  test('longest category keyword wins', () {
    expect(categoryFor('paid the water bill'), 'Tubig');
    expect(categoryFor('paid the bill'), 'Bills');
    expect(categoryFor('random stuff'), 'Other');
  });

  group('shaper', () {
    final now = DateTime(2026, 10, 18, 12);
    VoiceDraft shape(String s) => shapeVoiceMemo(s, now: now);

    test('a money memo becomes an expense draft', () {
      final d = shape('Spent 250 on lunch. Grab home was 180.');
      expect(d.kind, VoiceKind.expense);
      expect(d.spends.map((s) => s.amount), ['250', '180']);
    });

    test('a list with a price in it stays a list', () {
      final d = shape('Buy eggs. Call mom. Remember to pay rent 8000.');
      expect(d.kind, VoiceKind.todo);
    });

    test('"new task" splits and forces tasks', () {
      final d = shape(
        'new task the quarterly report next task water the plants',
      );
      expect(d.kind, VoiceKind.todo);
      expect(d.taskLines, ['The quarterly report', 'Water the plants']);
    });

    test('"title is" names the draft and "make it a note" overrides', () {
      final d = shape(
        'Title is weekend plans. Buy eggs. Call mom. Make it a note.',
      );
      expect(d.title, 'Weekend plans');
      expect(d.kind, VoiceKind.note);
    });

    test('dated tasks keep a reminder time', () {
      final d = shape('Call the dentist tomorrow at 3.');
      final when = d.tasks.single.when!;
      expect(when.at, DateTime(2026, 10, 19, 15));
    });
  });
}
