import 'dart:convert';

// The model runs through dart:ffi, which web builds don't have; they get a
// stub that reports the model as unavailable (the feature is hidden there).
import 'llm_native_stub.dart' if (dart.library.ffi) 'llm_native_ffi.dart';
import 'speech_cleanup.dart';
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
    // Money and spoken commands are the rules' job; skip the model's CPU.
    if (hasVoiceCommands(transcript) ||
        shapeVoiceMemo(transcript, now: now).kind == VoiceKind.expense) {
      return null;
    }
    final p = prompt(cleanSpeech(transcript));
    final String raw;
    try {
      raw = await runLlm(modelPath, p, grammar);
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
  // The rules draft is the safety net for what a 0.6B model gets wrong.
  final rules = shapeVoiceMemo(transcript, now: now);
  // The model was not trained on money: an expense memo keeps the rules'.
  if (rules.kind == VoiceKind.expense) return null;

  final kind = json['kind'] == 'todo' ? VoiceKind.todo : VoiceKind.note;
  final tasks = <VoiceTask>[];
  final matched = <VoiceTask>{};
  for (final t in (json['tasks'] as List? ?? const [])) {
    if (t is! Map) continue;
    final text = _tidy(t['text'] as String? ?? '');
    if (text.isEmpty) continue;
    final when = (t['when'] as String? ?? '').trim();
    // Only a phrase the date parser understands is a date: the model has
    // been seen calling "five kilos" and "next" one.
    final parsed = when.isEmpty ? null : parseSpokenWhen('$text $when', now);
    var task = parsed == null
        ? VoiceTask(text)
        : VoiceTask(_capitalize(parsed.text), parsed.when);
    // The same task as the rules heard it: their date wins when the model
    // dropped it, or kept the day but lost the time ("tomorrow at 3").
    final twin = _twin(task.text, rules.tasks, matched);
    if (twin != null) {
      matched.add(twin);
      final mine = task.when;
      final theirs = twin.when;
      if (theirs != null &&
          (mine == null ||
              (mine.hour == null &&
                  theirs.hour != null &&
                  _sameDay(mine.day, theirs.day)))) {
        task = VoiceTask(task.text, theirs);
      }
    }
    tasks.add(task);
  }
  if (kind == VoiceKind.todo && tasks.isEmpty) return null;

  final note = (json['note'] as String? ?? '').trim();
  // Tasks the model left in the note stay there: adding the rules' extra
  // tasks back scored worse on the eval set (more wrong than right).
  final other = note.isEmpty
      ? <String>[]
      : note
            .split(RegExp(r'(?<=[.!?])\s+'))
            .map(_tidy)
            .where((s) => s.isNotEmpty)
            .toList();

  var title = _tidy(json['title'] as String? ?? '');
  // A date-only title ("For tomorrow") becomes an absolute one.
  final dated = parseWhenOnly(title, now);
  if (dated != null) title = 'To-do — ${dated.label}';
  // "To-do", "Errands", "Things to do" say nothing a dated title doesn't.
  if (_generic.hasMatch(title)) title = '';

  return VoiceDraft(
    noteTitle: kind == VoiceKind.note && title.isNotEmpty
        ? title
        : rules.noteTitle,
    listTitle: kind == VoiceKind.todo && title.isNotEmpty
        ? title
        : rules.listTitle,
    kind: kind,
    tasks: tasks,
    other: other,
    spends: rules.spends,
  );
}

final _generic = RegExp(
  r"^(?:my\s+)?(?:to-?\s?dos?|to-?do list|todo list|tasks?|things to do|errands|reminders?|list|notes?|memo|voice memo|untitled|today|tomorrow|this week)$",
  caseSensitive: false,
);

/// Model text through the same clean-up as the rules, as a safety net.
String _tidy(String s) => _capitalize(cleanSpeech(s.trim()));

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Set<String> _words(String s) => RegExp(
  r"[a-z0-9']{3,}",
).allMatches(s.toLowerCase()).map((m) => m[0]!).toSet();

/// Shared words over the shorter text's words, 0 to 1.
double _overlap(String a, String b) {
  final wa = _words(a);
  final wb = _words(b);
  if (wa.isEmpty || wb.isEmpty) return 0;
  final shared = wa.intersection(wb).length;
  return shared / (wa.length < wb.length ? wa.length : wb.length);
}

/// The task in [pool] that says the same thing as [text], if any.
VoiceTask? _twin(String text, List<VoiceTask> pool, Set<VoiceTask> taken) {
  VoiceTask? best;
  var score = 0.5;
  for (final t in pool) {
    if (taken.contains(t)) continue;
    final s = _overlap(text, t.text);
    if (s >= score) {
      best = t;
      score = s;
    }
  }
  return best;
}
