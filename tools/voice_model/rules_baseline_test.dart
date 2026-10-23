// Exports the rules shaper's output on the hand-written test memos so the
// model comparison (eval.py --rules) scores both the same way.
//   flutter test tools/voice_model/rules_baseline_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/llm_shaper.dart';
import 'package:typed/voice/voice_shaper.dart';

void main() {
  test('export rules predictions', () {
    final lines = File('tools/voice_model/eval_memos.jsonl').readAsLinesSync();
    final out = StringBuffer();
    for (final line in lines.where((l) => l.trim().isNotEmpty)) {
      final memo = jsonDecode(line) as Map<String, dynamic>;
      final d = shapeVoiceMemo(memo['transcript'] as String,
          now: DateTime(2026, 10, 19, 10));
      out.writeln(jsonEncode({
        'kind': d.kind.name,
        'title': d.title,
        // The rules fold the date into the text ("… — Tue, Oct 20").
        'tasks': [
          for (final t in d.taskLines)
            {'text': t.split(' — ').first, 'when': t.contains(' — ') ? '*' : ''}
        ],
        'note': d.other.join(' '),
      }));
    }
    File('tools/voice_model/data/rules_preds.jsonl')
        .writeAsStringSync(out.toString());
  });

  // What the app actually shows with the model installed: the model's raw
  // answers (data/model_preds.jsonl, from a llama-server run) through
  // draftFromModelJson's checks against the rules.
  test('export app predictions', () {
    final preds = File('tools/voice_model/data/model_preds.jsonl');
    if (!preds.existsSync()) return;
    final raw = preds.readAsLinesSync();
    final memos = File('tools/voice_model/eval_memos.jsonl')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final out = StringBuffer();
    for (var i = 0; i < memos.length && i < raw.length; i++) {
      final transcript =
          (jsonDecode(memos[i]) as Map<String, dynamic>)['transcript'] as String;
      final now = DateTime(2026, 10, 19, 10);
      final d = hasVoiceCommands(transcript)
          ? null
          : draftFromModelJson(raw[i], transcript, now: now);
      final shown = d ?? shapeVoiceMemo(transcript, now: now);
      out.writeln(jsonEncode({
        'kind': shown.kind.name,
        'title': shown.title,
        'tasks': [
          for (final t in shown.tasks)
            {'text': t.text, 'when': t.when == null ? '' : '*'}
        ],
        'note': shown.other.join(' '),
      }));
    }
    File('tools/voice_model/data/app_preds.jsonl')
        .writeAsStringSync(out.toString());
  });
}
