import '../utils/date_format.dart';
import 'when_parser.dart';

/// What a voice memo becomes when saved.
enum VoiceKind { note, todo }

/// A first draft of a note or list, made from a transcript. Only a
/// suggestion: the review sheet lets the user change any of it.
class VoiceDraft {
  /// Titles for each shape, so the review sheet can switch between them.
  final String noteTitle;
  final String listTitle;
  final VoiceKind kind;

  /// Things to do, in the order they were said.
  final List<String> tasks;

  /// Everything that was said that is not a task, as cleaned sentences.
  final List<String> other;

  const VoiceDraft({
    required this.noteTitle,
    required this.listTitle,
    required this.kind,
    required this.tasks,
    required this.other,
  });

  String get title => kind == VoiceKind.todo ? listTitle : noteTitle;

  /// Note body: what was said, with any tasks as a checklist underneath.
  String get noteBody {
    final prose = other.join(' ');
    final list = tasks.map((t) => '- [ ] $t').join('\n');
    if (list.isEmpty) return prose;
    if (prose.isEmpty) return '$list\n';
    return '$prose\n\n$list\n';
  }

  /// Checklist content for a to-do list.
  String get listBody => tasks.isEmpty
      ? ''
      : '${tasks.map((t) => '- [ ] $t').join('\n')}\n';
}

/// Turns a raw transcript into a [VoiceDraft] with plain rules — no model.
///
/// It is the always-available first tier of the voice pipeline: instant,
/// on every device, and the fallback whenever a smarter shaper is missing
/// or returns something unusable. It understands:
/// - task cues ("I need to…", "remember to…", "don't forget…") and
///   imperative openers ("call…", "buy…");
/// - spoken joins between tasks ("…and then…", "also…");
/// - corrections ("scratch that", "never mind") that drop what came before.
VoiceDraft shapeVoiceMemo(String transcript, {DateTime? now}) {
  final date = now ?? DateTime.now();
  final clauses = _clauses(transcript);
  final tasks = <String>[];
  final other = <String>[];
  var lastWasTask = false;
  for (final clause in clauses) {
    final task = _asTask(clause);
    final fragment = lastWasTask ? _fragment(clause) : null;
    if (task != null) {
      tasks.add(task);
      lastWasTask = true;
    } else if (fragment != null) {
      // "Buy eggs. Bread too." → "Buy eggs and bread".
      tasks.last = '${tasks.last} and $fragment';
    } else {
      other.add(_sentence(clause));
      lastWasTask = false;
    }
  }
  // Spoken dates become absolute ones: "tomorrow" in a list read next week
  // would point at the wrong day.
  for (var i = 0; i < tasks.length; i++) {
    final when = parseSpokenWhen(tasks[i], date);
    if (when != null) tasks[i] = '${_capitalize(when.text)} — ${when.when.label}';
  }
  // A list when the memo is mostly things to do; a note when tasks are
  // incidental to what was said.
  final kind = tasks.length >= 2 || (tasks.length == 1 && other.isEmpty)
      ? VoiceKind.todo
      : VoiceKind.note;
  var listTitle = 'To-do — ${monthShort(date.month)} ${date.day}';
  // A short lead-in before the tasks names the list better than today's
  // date: "Groceries, I need…" → "Groceries"; a lead-in that is only a
  // date ("Tomorrow, I need to…") → "To-do — Tue, Oct 20".
  if (kind == VoiceKind.todo &&
      clauses.isNotEmpty &&
      _asTask(clauses.first) == null) {
    final lead = other.first.replaceFirst(RegExp(r'[.!?]+$'), '');
    final when = parseWhenOnly(lead, date);
    if (when != null) {
      listTitle = 'To-do — ${when.label}';
      other.removeAt(0);
    } else if (lead.isNotEmpty && lead.split(' ').length <= 6) {
      listTitle = lead;
      other.removeAt(0);
    }
  }
  return VoiceDraft(
    noteTitle: _noteTitle(
      other.isNotEmpty ? other.first : (tasks.firstOrNull ?? ''),
      date,
    ),
    listTitle: listTitle,
    kind: kind,
    tasks: tasks,
    other: other,
  );
}

// ── clauses ───────────────────────────────────────────────────────────────

final _corrections = RegExp(
  r"^(?:scratch that|strike that|never ?mind|forget that|no wait|actually no|wait no|delete that)\b[\s,.!-]*",
  caseSensitive: false,
);

const _taskStarts =
    r"(?:i\s+)?(?:really\s+)?(?:need|have|got|want)\s+to\b|(?:i\s+)?gotta\b|(?:i\s+)?(?:should|must)\b|remember\s+to\b|remind\s+me\s+to\b|don'?t\s+forget\b|do\s+not\s+forget\b|make\s+sure\b|(?:i'?ll|i\s+will|i'?m\s+going\s+to|gonna)\b";

/// Imperative openers that make a clause a task on their own.
const _verbs = {
  'ask', 'book', 'bring', 'buy', 'call', 'cancel', 'check', 'clean', 'drop',
  'email', 'feed', 'file', 'find', 'finish', 'fix', 'follow', 'get', 'grab',
  'look', 'mail', 'make', 'message', 'order', 'organise', 'organize', 'pack',
  'pay', 'pick', 'plan', 'prepare', 'print', 'read', 'renew', 'reply',
  'research', 'reschedule', 'return', 'review', 'schedule', 'send', 'set',
  'sign', 'sort', 'start', 'submit', 'take', 'tell', 'text', 'update',
  'wash', 'water', 'write',
};

final _verbPattern = _verbs.join('|');

/// Where one spoken task ends and the next begins inside a sentence.
final _joins = RegExp(
  '(?:[,;]?\\s+(?:and then|and also|after that|oh and|then|also|plus|and)|[,;])\\s+'
  '(?=(?:$_taskStarts|(?:$_verbPattern)\\b))',
  caseSensitive: false,
);

/// A strong cue mid-sentence starts a task ("for the weekend I need to…").
final _beforeCue = RegExp(
  r"[,;]?\s+(?=(?:i\s+(?:really\s+)?(?:need|have|got)\s+to|remember\s+to|remind\s+me\s+to|don'?t\s+forget|make\s+sure)\b)",
  caseSensitive: false,
);

/// A correction can arrive mid-sentence ("buy milk, scratch that, …").
final _beforeCorrection = RegExp(
  r"[,;.]?\s+(?=(?:scratch that|strike that|never ?mind|forget that|no wait|actually no|wait no|delete that)\b)",
  caseSensitive: false,
);

List<String> _clauses(String transcript) {
  final text = transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return const [];
  final sentences = text
      .split(RegExp(r'(?<=[.!?;])\s+'))
      .expand((s) => s.split(_beforeCorrection))
      .expand((s) => s.split(_beforeCue))
      .expand((s) => s.split(_joins))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final out = <String>[];
  for (var s in sentences) {
    final fix = _corrections.firstMatch(s);
    if (fix != null) {
      if (out.isNotEmpty) out.removeLast();
      s = s.substring(fix.end).trim();
      s = s.replaceFirst(RegExp(r'^instead\b[\s,]*', caseSensitive: false), '');
      s = s.replaceFirst(RegExp(r'\s*\binstead\b(?=[.!?]?$)', caseSensitive: false), '');
    }
    if (_strip(s).isNotEmpty) out.add(s);
  }
  return out;
}

// ── tasks ─────────────────────────────────────────────────────────────────

final _fillers = RegExp(
  r"^(?:um+|uh+|er+|so|okay|ok|right|well|oh|and|also|then|plus|alright|anyway|like|first|firstly|second|secondly|next|finally|lastly)\b[\s,.]*",
  caseSensitive: false,
);

final _cue = RegExp(
  r"^(?:i\s+)?(?:really\s+)?(?:need|have|got|want)\s+to\s+"
  r"|^(?:i\s+)?gotta\s+"
  r"|^(?:i\s+)?(?:should|must)\s+"
  r"|^(?:remember|remind\s+me)\s+to\s+"
  r"|^(?:don'?t|do\s+not)\s+forget\s+(?:to\s+)?"
  r"|^make\s+sure\s+(?:to\s+|i\s+)?"
  r"|^(?:i'?ll|i\s+will|i'?m\s+going\s+to|i\s+am\s+going\s+to|gonna)\s+"
  r"|^(?:to-?do|task)\s*[:,-]?\s+",
  caseSensitive: false,
);

String _strip(String s) {
  var out = s.trim();
  while (true) {
    final m = _fillers.firstMatch(out);
    if (m == null || m.end == 0) break;
    out = out.substring(m.end).trim();
  }
  return out;
}

/// A short follow-on to the previous task: "Bread too.", "Also milk",
/// "And some coffee as well". Null when the clause is anything more.
String? _fragment(String clause) {
  final m = RegExp(
    r"^(?:(?:oh,?\s+)?and|also|plus)?\s*(.+?)(?:\s+(?:too|as well))?[.!?]*$",
    caseSensitive: false,
  ).firstMatch(clause.trim());
  if (m == null) return null;
  final hasMarker = RegExp(
    r"^(?:(?:oh,?\s+)?and|also|plus)\b|\b(?:too|as well)[.!?]*$",
    caseSensitive: false,
  ).hasMatch(clause.trim());
  final body = m.group(1)!.trim();
  if (!hasMarker || body.isEmpty || body.split(' ').length > 4) return null;
  final first = body.split(' ').first.toLowerCase();
  if (_verbs.contains(first) || first == 'i') return null;
  // "Bread too." is capitalised only because it started a sentence.
  final word = body.split(' ').first;
  return word.length > 1 && word.substring(1) == word.substring(1).toLowerCase()
      ? body[0].toLowerCase() + body.substring(1)
      : body;
}

String? _asTask(String clause) {
  var s = _strip(clause);
  // "buy eggs, also milk" / "eggs, oh and bread" read as one list.
  s = s.replaceAll(
    RegExp(r',?\s+(?:oh,?\s+)?(?:and\s+)?(?:also|plus)\s+', caseSensitive: false),
    ' and ',
  );
  final cue = _cue.firstMatch(s);
  if (cue != null) {
    s = s.substring(cue.end);
  } else {
    final first = RegExp(r"^[a-z']+", caseSensitive: false)
        .firstMatch(s)
        ?.group(0)
        ?.toLowerCase();
    if (first == null || !_verbs.contains(first)) return null;
  }
  s = s.replaceFirst(RegExp(r'[\s,.;!?]+$'), '').trim();
  // "…buy oat milk instead" after a correction.
  s = s.replaceFirst(RegExp(r'\s+instead$', caseSensitive: false), '');
  if (s.length < 2) return null;
  return _capitalize(s);
}

// ── text ──────────────────────────────────────────────────────────────────

String _sentence(String clause) {
  final s = _capitalize(_strip(clause).replaceFirst(RegExp(r'[\s,;]+$'), ''));
  if (s.isEmpty) return s;
  return RegExp(r'[.!?]$').hasMatch(s) ? s : '$s.';
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _noteTitle(String first, DateTime date) {
  final s = first.replaceFirst(RegExp(r'[.!?]+$'), '').trim();
  if (s.isEmpty) return 'Voice memo — ${monthShort(date.month)} ${date.day}';
  if (s.length <= 60) return s;
  final cut = s.lastIndexOf(' ', 57);
  return '${s.substring(0, cut > 20 ? cut : 57)}…';
}
