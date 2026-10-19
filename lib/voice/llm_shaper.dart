import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'voice_shaper.dart';
import 'when_parser.dart';

/// The model-backed tier of the voice pipeline: a small model fine-tuned for
/// exactly this job (tools/voice_model), run by llama.cpp on the phone's CPU.
///
/// It only reads the transcript and returns structure; dates stay with the
/// Dart parser, and anything malformed falls back to the rules draft.
class LlmShaper {
  LlmShaper._();

  /// Must match INSTRUCTION in tools/voice_model/common.py — the model was
  /// trained on this exact wording.
  static const instruction =
      'Turn this voice memo transcript into JSON with keys kind (todo or '
      'note), title, tasks (list of {text, when}) and note. Tasks are short '
      'imperative actions; when is the date or time phrase exactly as '
      "spoken, or empty. Apply corrections like 'scratch that'. Drop filler "
      'words.';

  static String prompt(String transcript) =>
      '<|im_start|>user\n$instruction\n\nTranscript: ${transcript.trim()}'
      '<|im_end|>\n<|im_start|>assistant\n';

  /// Constrains decoding to the trained JSON shape (json.dumps spacing), so
  /// even a tiny model cannot return something unparseable.
  static const grammar = r'''
root   ::= "{" "\"kind\": " kind ", \"title\": " str ", \"tasks\": " tasks ", \"note\": " str "}"
kind   ::= "\"todo\"" | "\"note\""
tasks  ::= "[]" | "[" task (", " task)* "]"
task   ::= "{\"text\": " str ", \"when\": " str "}"
str    ::= "\"" char* "\""
char   ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
''';

  /// Shapes [transcript] with the model at [modelPath], or null when the
  /// model or native library is unavailable or the output is unusable.
  static Future<VoiceDraft?> shape(
    String transcript,
    String modelPath, {
    DateTime? now,
  }) async {
    if (transcript.trim().isEmpty) return null;
    final p = prompt(transcript);
    final String raw;
    try {
      raw = await Isolate.run(() => _runNative(modelPath, p, grammar));
    } catch (_) {
      return null;
    }
    if (raw.startsWith('ERR:')) return null;
    return draftFromModelJson(raw, transcript, now: now ?? DateTime.now());
  }
}

/// Maps the model's JSON to a [VoiceDraft]; the rules draft fills the title
/// of the shape the model did not pick, so switching Note ⇄ To-do in review
/// still has a sensible title.
VoiceDraft? draftFromModelJson(
  String raw,
  String transcript, {
  required DateTime now,
}) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final kind = json['kind'] == 'todo' ? VoiceKind.todo : VoiceKind.note;
  final tasks = <String>[];
  for (final t in (json['tasks'] as List? ?? const [])) {
    if (t is! Map) continue;
    final text = (t['text'] as String? ?? '').trim();
    if (text.isEmpty) continue;
    final when = (t['when'] as String? ?? '').trim();
    final parsed = when.isEmpty ? null : parseSpokenWhen('$text $when', now);
    tasks.add(parsed == null
        ? text
        : '${parsed.text[0].toUpperCase()}${parsed.text.substring(1)} — '
            '${parsed.when.label}');
  }
  if (kind == VoiceKind.todo && tasks.isEmpty) return null;

  var title = (json['title'] as String? ?? '').trim();
  // A date-only title ("For tomorrow") becomes an absolute one.
  final dated = parseWhenOnly(title, now);
  if (dated != null) title = 'To-do — ${dated.label}';

  final note = (json['note'] as String? ?? '').trim();
  final other = note.isEmpty
      ? <String>[]
      : note
          .split(RegExp(r'(?<=[.!?])\s+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  final rules = shapeVoiceMemo(transcript, now: now);
  return VoiceDraft(
    noteTitle: kind == VoiceKind.note && title.isNotEmpty ? title : rules.noteTitle,
    listTitle: kind == VoiceKind.todo && title.isNotEmpty ? title : rules.listTitle,
    kind: kind,
    tasks: tasks,
    other: other,
  );
}

// ── native ────────────────────────────────────────────────────────────────

typedef _RunC = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32, Int32);
typedef _RunDart = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int, int);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// Runs on a background isolate: one load → generate → free.
String _runNative(String modelPath, String prompt, String grammar) {
  final lib = DynamicLibrary.open('libtyped_llm.so');
  final run = lib.lookupFunction<_RunC, _RunDart>('typed_llm_run');
  final free = lib.lookupFunction<_FreeC, _FreeDart>('typed_llm_free');
  final m = modelPath.toNativeUtf8();
  final p = prompt.toNativeUtf8();
  final g = grammar.toNativeUtf8();
  try {
    // Big cores only: more threads than performance cores slows llama.cpp.
    final threads = (Platform.numberOfProcessors / 2).clamp(2, 4).toInt();
    // 20 s: past that the rules draft is the answer.
    final out = run(m, p, g, 400, threads, 20000);
    final text = out.toDartString();
    free(out);
    return text;
  } finally {
    malloc.free(m);
    malloc.free(p);
    malloc.free(g);
  }
}
