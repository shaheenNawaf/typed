import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/voice_shaper.dart';

void main() {
  final now = DateTime(2026, 10, 18, 12);
  VoiceDraft shape(String s) => shapeVoiceMemo(s, now: now);

  group('tasks', () {
    test('task cues become a list', () {
      final d = shape(
        'Okay so for the weekend I need to buy eggs. '
        'Remember to call mom. Also email Sam about the venue.',
      );
      expect(d.kind, VoiceKind.todo);
      expect(d.tasks, ['Buy eggs', 'Call mom', 'Email Sam about the venue']);
      // The short lead-in names the list and is not left over as prose.
      expect(d.title, 'For the weekend');
      expect(d.other, isEmpty);
    });

    test('a list with no lead-in is titled by date', () {
      final d = shape('Buy eggs. Call mom.');
      expect(d.title, 'To-do — Oct 18');
    });

    test('unpunctuated speech splits on spoken joins', () {
      final d = shape(
        'i have to pick up the dry cleaning and then call the bank '
        'and also water the plants',
      );
      expect(d.tasks, [
        'Pick up the dry cleaning',
        'Call the bank',
        'Water the plants',
      ]);
    });

    test('commas between tasks split them', () {
      final d = shape('buy milk, call mom, email Sam');
      expect(d.tasks, ['Buy milk', 'Call mom', 'Email Sam']);
    });

    test('"and" inside one task does not split it', () {
      final d = shape('I need to buy eggs and milk and bread');
      expect(d.tasks, ['Buy eggs and milk and bread']);
    });

    test("don't forget and I'll are cues too", () {
      final d = shape("Don't forget the passport. I'll book the taxi.");
      expect(d.tasks, ['The passport', 'Book the taxi']);
    });
  });

  group('corrections', () {
    test('scratch that drops what came before', () {
      final d = shape('Buy milk, scratch that, buy oat milk instead.');
      expect(d.tasks, ['Buy oat milk']);
    });

    test('never mind on its own removes the previous task', () {
      final d = shape('Call Sam. Never mind. Email Priya. Book flights.');
      expect(d.tasks, ['Email Priya', 'Book flights']);
    });
  });

  group('notes', () {
    test('prose with no tasks is a note titled by its first sentence', () {
      final d = shape(
        'The talk today was about local-first software. '
        'Sync is the hard part, not storage.',
      );
      expect(d.kind, VoiceKind.note);
      expect(d.tasks, isEmpty);
      expect(d.title, 'The talk today was about local-first software');
      expect(
        d.noteBody,
        'The talk today was about local-first software. '
        'Sync is the hard part, not storage.',
      );
    });

    test('a note keeps an incidental task as a checklist line', () {
      final d = shape(
        'Great idea for the app: a weekly recap on Sundays. '
        'I should sketch it.',
      );
      expect(d.kind, VoiceKind.note);
      expect(d.noteBody, contains('- [ ] Sketch it'));
      expect(d.noteBody, startsWith('Great idea for the app'));
    });

    test('long first sentences are trimmed for the title', () {
      final d = shape(
        'This is a very long first sentence that goes on and on about '
        'nothing in particular for quite a while longer than a title.',
      );
      expect(d.title.length, lessThanOrEqualTo(61));
      expect(d.title, endsWith('…'));
    });

    test('an empty transcript gives a dated empty note', () {
      final d = shape('   ');
      expect(d.kind, VoiceKind.note);
      expect(d.title, 'Voice memo — Oct 18');
      expect(d.noteBody, '');
    });
  });

  test('a single task on its own is a list of one', () {
    final d = shape('Remember to renew the passport');
    expect(d.kind, VoiceKind.todo);
    expect(d.listBody, '- [ ] Renew the passport\n');
  });
}
