import '../utils/date_format.dart';
import 'spend_parser.dart';
import 'when_parser.dart';

/// What a voice memo becomes when saved.
enum VoiceKind { note, todo, expense }

/// One thing to do, with the date it was said for (if any).
class VoiceTask {
  final String text;
  final SpokenWhen? when;

  const VoiceTask(this.text, [this.when]);

  /// The checklist line: "Call the dentist — Tue, Oct 20, 3 PM".
  String get line => when == null ? text : '$text — ${when!.label}';
}

/// A first draft of a note, list or expense, made from a transcript. Only a
/// suggestion: the review sheet lets the user change any of it.
class VoiceDraft {
  /// Titles for each shape, so the review sheet can switch between them.
  final String noteTitle;
  final String listTitle;
  final VoiceKind kind;

  /// Things to do, in the order they were said.
  final List<VoiceTask> tasks;

  /// Everything that was said that is not a task, as cleaned sentences.
  final List<String> other;

  /// Money that was mentioned ("spent 250 on lunch").
  final List<VoiceSpend> spends;

  const VoiceDraft({
    required this.noteTitle,
    required this.listTitle,
    required this.kind,
    required this.tasks,
    required this.other,
    this.spends = const [],
  });

  String get title => kind == VoiceKind.todo ? listTitle : noteTitle;

  List<String> get taskLines => [for (final t in tasks) t.line];

  /// Note body: what was said, with any tasks as a checklist underneath.
  String get noteBody {
    final prose = other.join(' ');
    final list = taskLines.map((t) => '- [ ] $t').join('\n');
    if (list.isEmpty) return prose;
    if (prose.isEmpty) return '$list\n';
    return '$prose\n\n$list\n';
  }

  /// Checklist content for a to-do list.
  String get listBody =>
      tasks.isEmpty ? '' : '${taskLines.map((t) => '- [ ] $t').join('\n')}\n';
}

/// Turns a raw transcript into a [VoiceDraft] with plain rules — no model.
///
/// It is the always-available first tier of the voice pipeline: instant,
/// on every device, and the fallback whenever a smarter shaper is missing
/// or returns something unusable. It understands:
/// - task cues ("I need to…", "remember to…", "don't forget…") and
///   imperative openers ("call…", "buy…");
/// - spoken joins between tasks ("…and then…", "also…");
/// - corrections ("scratch that", "never mind") that drop what came before;
/// - money ("spent 250 on lunch", "grab 180") as expenses;
/// - spoken commands: "new task …" (whatever follows is a task), "title is
///   …", "make it a list / note / expense".
VoiceDraft shapeVoiceMemo(String transcript, {DateTime? now}) {
  final date = now ?? DateTime.now();
  final command = _commands(transcript);
  final clauses = _clauses(command.text);
  final tasks = <String>[];
  final other = <String>[];
  final spends = <VoiceSpend>[];
  var lastWasTask = false;
  for (var clause in clauses) {
    // "new task …": whatever follows is a task, cue or no cue.
    final forced = clause.startsWith(_taskMark);
    if (forced) clause = clause.substring(_taskMark.length).trim();
    if (clause.isEmpty) continue;
    final task = _asTask(clause) ?? (forced ? _forcedTask(clause) : null);
    // Money, unless it was said as something to do ("remember to pay 500").
    final money = forced || _cue.hasMatch(_strip(clause))
        ? const <VoiceSpend>[]
        : parseSpends(clause);
    final fragment = lastWasTask && !forced ? _fragment(clause) : null;
    if (money.isNotEmpty) {
      spends.addAll(money);
      lastWasTask = false;
    } else if (task != null) {
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
  // would point at the wrong day. The date stays data, so the review sheet
  // can show it as a chip and set a reminder.
  final dated = <VoiceTask>[
    for (final t in tasks)
      if (parseSpokenWhen(t, date) case final w?)
        VoiceTask(_capitalize(w.text), w.when)
      else
        VoiceTask(t),
  ];
  // A list when the memo is mostly things to do; a note when tasks are
  // incidental to what was said; an expense when it is mostly money.
  final kind =
      command.kind ??
      (spends.isNotEmpty && spends.length >= tasks.length
          ? VoiceKind.expense
          : tasks.length >= 2 || (tasks.length == 1 && other.isEmpty)
          ? VoiceKind.todo
          : VoiceKind.note);
  var listTitle = 'To-do — ${monthShort(date.month)} ${date.day}';
  // A short lead-in before the tasks names the list better than today's
  // date: "Groceries, I need…" → "Groceries"; a lead-in that is only a
  // date ("Tomorrow, I need to…") → "To-do — Tue, Oct 20".
  if (kind == VoiceKind.todo &&
      other.isNotEmpty &&
      clauses.isNotEmpty &&
      !clauses.first.startsWith(_taskMark) &&
      _asTask(clauses.first) == null &&
      parseSpends(clauses.first).isEmpty) {
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
  final spoken = command.title;
  return VoiceDraft(
    noteTitle:
        spoken ??
        _noteTitle(
          other.isNotEmpty ? other.first : (tasks.firstOrNull ?? ''),
          date,
        ),
    listTitle: spoken ?? listTitle,
    kind: kind,
    tasks: dated,
    other: other,
    spends: spends,
  );
}

// ── spoken commands ───────────────────────────────────────────────────────

/// Marks a clause that followed "new task".
const _taskMark = '⟦task⟧';

/// "new task", "next task", "another item", "add a to-do", and the usual
/// mishearings ("new tasks", "next to do"). Never bare "next": "next week".
final _taskCommand = RegExp(
  r"[,;.]?\s*\b(?:new|next|another|add(?:\s+a)?|one more)\s+(?:tasks?|items?|to-?dos?|to do)\b[\s:,.;-]*",
  caseSensitive: false,
);

final _titleCommand = RegExp(
  r"(?:^|[,;.]\s*|\s)(?:the\s+)?(?:title(?:\s+is|\s+it|:)?|call\s+it|name\s+it)\s+([^.!?,;]{1,60})[.!?,;]?",
  caseSensitive: false,
);

final _kindCommand = RegExp(
  r"[,;.]?\s*\b(?:make|save|turn)\s+(?:it|this)(?:\s+(?:into|as))?\s+(?:an?\s+)?(list|to-?do(?:\s+list)?|checklist|note|expenses?)\b[.!?]?|[,;.]?\s*\bas\s+an?\s+(list|to-?do\s+list|checklist|note|expense)\b[.!?]?",
  caseSensitive: false,
);

({String text, String? title, VoiceKind? kind}) _commands(String transcript) {
  var text = transcript;
  VoiceKind? kind;
  final k = _kindCommand.firstMatch(text);
  if (k != null) {
    final word = (k.group(1) ?? k.group(2))!.toLowerCase();
    kind = word.startsWith('note')
        ? VoiceKind.note
        : word.startsWith('expense')
        ? VoiceKind.expense
        : VoiceKind.todo;
    text = text.replaceRange(k.start, k.end, '. ');
  }
  String? title;
  final t = _titleCommand.firstMatch(text);
  if (t != null) {
    final words = t.group(1)!.trim().split(RegExp(r'\s+'));
    if (words.length <= 8) {
      title = _capitalize(words.join(' '));
      text = text.replaceRange(t.start, t.end, '. ');
    }
  }
  text = text.replaceAll(_taskCommand, '. $_taskMark ');
  return (text: text, title: title, kind: kind);
}

/// After "new task", anything is a task: "new task the passport photos"
/// → "The passport photos".
String? _forcedTask(String clause) {
  final s = _strip(clause).replaceFirst(RegExp(r'[\s,.;!?]+$'), '').trim();
  return s.length < 2 ? null : _capitalize(s);
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
  'ask',
  'book',
  'bring',
  'buy',
  'call',
  'cancel',
  'check',
  'clean',
  'drop',
  'email',
  'feed',
  'file',
  'find',
  'finish',
  'fix',
  'follow',
  'get',
  'grab',
  'look',
  'mail',
  'make',
  'message',
  'order',
  'organise',
  'organize',
  'pack',
  'pay',
  'pick',
  'plan',
  'prepare',
  'print',
  'read',
  'renew',
  'reply',
  'research',
  'reschedule',
  'return',
  'review',
  'schedule',
  'send',
  'set',
  'sign',
  'sort',
  'start',
  'submit',
  'take',
  'tell',
  'text',
  'update',
  'wash',
  'water',
  'write',
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
      .expand((s) => s.split(RegExp(r'\s*(?=⟦task⟧)')))
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
      s = s.replaceFirst(
        RegExp(r'\s*\binstead\b(?=[.!?]?$)', caseSensitive: false),
        '',
      );
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
    RegExp(
      r',?\s+(?:oh,?\s+)?(?:and\s+)?(?:also|plus)\s+',
      caseSensitive: false,
    ),
    ' and ',
  );
  final cue = _cue.firstMatch(s);
  if (cue != null) {
    s = s.substring(cue.end);
  } else {
    final first = RegExp(
      r"^[a-z']+",
      caseSensitive: false,
    ).firstMatch(s)?.group(0)?.toLowerCase();
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
