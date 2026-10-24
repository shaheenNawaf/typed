import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/llm_shaper.dart';
import 'package:typed/voice/speech_cleanup.dart';
import 'package:typed/voice/voice_shaper.dart';
import 'package:typed/voice/when_parser.dart';

void main() {
  group('cleanSpeech', () {
    test('drops greetings, hesitations and tics', () {
      expect(
        cleanSpeech('hey so I like need to buy eggs'),
        'I need to buy eggs',
      );
      expect(
        cleanSpeech(
          'um hello okay so the meeting went well I guess, Hannah '
          'liked it',
        ),
        'the meeting went well, Hannah liked it',
      );
      expect(
        cleanSpeech('hey hey uh can you remind me to call the dentist'),
        'remind me to call the dentist',
      );
      expect(
        cleanSpeech('so yeah I was thinking like maybe dark mode, you know'),
        'I was thinking maybe dark mode',
      );
      expect(
        cleanSpeech('so like I just realized I have to renew my passport'),
        'I have to renew my passport',
      );
    });

    test('keeps words that carry meaning', () {
      expect(
        cleanSpeech('I like the new onboarding flow'),
        'I like the new onboarding flow',
      );
      expect(cleanSpeech('it looks like rain'), 'it looks like rain');
      expect(cleanSpeech('Well done on the launch'), 'Well done on the launch');
      expect(cleanSpeech('So many bugs today'), 'So many bugs today');
      expect(cleanSpeech('I had had enough'), 'I had had enough');
      expect(
        cleanSpeech("I'd like to book a table"),
        "I'd like to book a table",
      );
    });
  });

  group('rules shaper on rambling speech', () {
    final now = DateTime(2026, 10, 24, 12);
    VoiceDraft shape(String s) => shapeVoiceMemo(s, now: now);

    test('no filler reaches titles, tasks or notes', () {
      var d = shape('hey so I like need to buy eggs and then call mom later');
      expect(d.taskLines, ['Buy eggs', 'Call mom later']);
      expect(d.title, startsWith('To-do'));

      d = shape(
        'hey um so basically I have to finish the report by Friday '
        'and like also email Sam',
      );
      expect(d.taskLines, ['Finish the report — Fri, Oct 30', 'Email Sam']);

      d = shape(
        'hey hey uh can you remind me to call the dentist at 3 '
        'tomorrow',
      );
      expect(d.kind, VoiceKind.todo);
      expect(d.taskLines, ['Call the dentist — Sun, Oct 25, 3 PM']);

      d = shape(
        'um hello okay so the meeting went well I guess, Hannah '
        'liked the flow, I should send her the mockups',
      );
      expect(d.title, 'The meeting went well, Hannah liked the flow');
    });

    test('a command at the very start leaves no stray full stop', () {
      final d = shape(
        'hey Typed new task call the bank next task water the '
        'plants',
      );
      expect(d.taskLines, ['Call the bank', 'Water the plants']);
      expect(d.other, isEmpty);
    });
  });

  group('model answers are checked against the rules', () {
    final now = DateTime(2026, 10, 24, 12);
    String json(
      String kind,
      String title,
      List<List<String>> tasks, [
      String note = '',
    ]) => jsonEncode({
      'kind': kind,
      'title': title,
      'tasks': [
        for (final t in tasks) {'text': t[0], 'when': t[1]},
      ],
      'note': note,
    });

    test('a time the model dropped comes back from the rules', () {
      final d = draftFromModelJson(
        json('todo', 'To-do', [
          ['Call the dentist', 'tomorrow'],
        ]),
        'hey hey uh can you remind me to call the dentist at 3 tomorrow',
        now: now,
      )!;
      expect(d.tasks.single.when!.at, DateTime(2026, 10, 25, 15));
    });

    test('a "date" the parser cannot read is not a date', () {
      final d = draftFromModelJson(
        json('todo', 'Things to do', [
          ['Pick up the laundry', ''],
          ['Buy rice', 'five kilos'],
        ]),
        'Hey, so I need to pick up the laundry. And basically also buy '
        'rice, like five kilos.',
        now: now,
      )!;
      expect(d.tasks.map((t) => t.when), [null, null]);
      // A generic title gives way to the dated one.
      expect(d.title, 'To-do — Oct 24');
    });

    test('filler the model lets through is cleaned', () {
      final d = draftFromModelJson(
        json('note', 'Hey so dark mode', [], 'Um so maybe dark mode.'),
        'um so maybe dark mode',
        now: now,
      )!;
      expect(d.title, 'Dark mode');
      expect(d.other, ['Maybe dark mode.']);
    });

    test('spoken commands skip the model', () {
      expect(hasVoiceCommands('new task call the bank'), isTrue);
      expect(hasVoiceCommands('title is groceries, eggs, milk'), isTrue);
      expect(hasVoiceCommands('call the bank and buy milk'), isFalse);
    });
  });

  group('dates', () {
    final now = DateTime(2026, 10, 24, 12);
    test('a day of the month', () {
      expect(
        parseSpokenWhen('Renew it on the 30th', now)!.when.day,
        DateTime(2026, 10, 30),
      );
      // Already past this month: next month's.
      expect(
        parseSpokenWhen('Pay rent on the 2nd', now)!.when.day,
        DateTime(2026, 11, 2),
      );
      expect(parseSpokenWhen('Go to the 2nd floor', now), isNull);
      expect(parseSpokenWhen('Third try, the 3rd time', now), isNull);
    });

    test('"the morning" as a thing is not a time', () {
      final m = parseSpokenWhen('Take the morning off work', now);
      expect(m, isNull);
      expect(
        parseSpokenWhen('Call mom in the morning', now)!.when.partOfDay,
        'morning',
      );
      expect(
        parseSpokenWhen('Water the plants tomorrow morning', now)!.when.day,
        DateTime(2026, 10, 25),
      );
    });

    test('weeks, weekends and times said as events', () {
      // Saturday Oct 24; use a Monday so "before" has days to go.
      final mon = DateTime(2026, 10, 19, 10);
      var w = parseSpokenWhen('Renew the insurance before the weekend', mon)!;
      expect(w.text, 'Renew the insurance');
      expect(w.when.day, DateTime(2026, 10, 23));
      w = parseSpokenWhen('Pay my share of the internet before Friday', mon)!;
      expect(w.text, 'Pay my share of the internet');
      expect(w.when.day, DateTime(2026, 10, 23));
      expect(
        parseSpokenWhen('Book a physio this week', mon)!.when.day,
        DateTime(2026, 10, 23),
      );
      expect(
        parseSpokenWhen('Ping IT after lunch', mon)!.when.at,
        DateTime(2026, 10, 19, 13),
      );
      expect(
        parseSpokenWhen('Call mom after work', mon)!.when.at,
        DateTime(2026, 10, 19, 18),
      );
      expect(
        parseSpokenWhen(
          'Send Bea the slides first thing tomorrow',
          mon,
        )!.when.at,
        DateTime(2026, 10, 20, 9),
      );
      expect(parseSpokenWhen('Go over the weekend plan', mon), isNull);
    });

    test('end of day is today at 5 PM', () {
      final w = parseSpokenWhen('Submit the timesheet before end of day', now)!;
      expect(w.text, 'Submit the timesheet');
      expect(w.when.at, DateTime(2026, 10, 24, 17));
    });
  });
}
