import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/llm_shaper.dart';
import 'package:typed/voice/voice_shaper.dart';

void main() {
  // Monday, Oct 19 2026, 10:00.
  final now = DateTime(2026, 10, 19, 10);

  VoiceDraft? map(String json, [String transcript = 'x']) =>
      draftFromModelJson(json, transcript, now: now);

  test('tasks get absolute dates from the spoken when phrase', () {
    final d = map('{"kind": "todo", "title": "Bank and groceries", "tasks": ['
        '{"text": "Call the bank about the card", "when": "tomorrow at 3"}, '
        '{"text": "Buy rice", "when": ""}], "note": ""}')!;
    expect(d.kind, VoiceKind.todo);
    expect(d.title, 'Bank and groceries');
    expect(d.taskLines, [
      'Call the bank about the card — Tue, Oct 20, 3 PM',
      'Buy rice',
    ]);
  });

  test('a date-only title becomes an absolute one', () {
    final d = map('{"kind": "todo", "title": "For tomorrow", "tasks": ['
        '{"text": "Pack the bags", "when": ""}], "note": ""}')!;
    expect(d.title, 'To-do — Tue, Oct 20');
  });

  test('a note keeps its sentences and its title', () {
    final d = map('{"kind": "note", "title": "Sync talk takeaways", '
        '"tasks": [], "note": "Sync is the hard part. Storage is easy."}')!;
    expect(d.kind, VoiceKind.note);
    expect(d.title, 'Sync talk takeaways');
    expect(d.other, ['Sync is the hard part.', 'Storage is easy.']);
  });

  test('unusable output falls back (null)', () {
    expect(map('not json'), isNull);
    expect(map('{"kind": "todo", "title": "X", "tasks": [], "note": ""}'),
        isNull);
  });

  test('the prompt matches the training format', () {
    final p = LlmShaper.prompt('  buy milk ');
    expect(p, startsWith('<|im_start|>user\n${LlmShaper.instruction}'));
    expect(p, endsWith('Transcript: buy milk<|im_end|>\n<|im_start|>assistant\n'));
  });
}
