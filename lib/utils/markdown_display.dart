import '../models/note.dart';

/// Display-layer helpers for markdown-backed content.
///
/// Typed keeps markdown as the storage substrate (tasks are `- [ ]` lines in
/// note content). Every surface that SHOWS that content must go through these
/// helpers so previews, task rows, widget payloads, and counts never disagree.
/// Storage is never rewritten by this file.

/// One parsed checkbox line: its raw line index (toggle paths rewrite by
/// index), completion state, and the RAW item text (display sites strip).
typedef ChecklistItem = ({int lineIndex, bool done, String text});

final RegExp _kCheckboxLine = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.*)$');
final RegExp _kHasCheckbox = RegExp(r'^\s*-\s+\[[ xX]\]', multiLine: true);

/// Parses every `- [ ]` / `- [x]` / `- [X]` line. An item with no text after
/// the marker (fresh template line `- [ ] `) still parses, with empty text —
/// callers decide whether to show or skip it.
List<ChecklistItem> parseChecklist(String content) {
  final items = <ChecklistItem>[];
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _kCheckboxLine.firstMatch(lines[i]);
    if (m == null) continue;
    items.add((
      lineIndex: i,
      done: m.group(1)!.toLowerCase() == 'x',
      text: m.group(2)?.trim() ?? '',
    ));
  }
  return items;
}

/// True when content has at least one checkbox line. Line-anchored: prose
/// containing a literal `[ ]` (or a code span teaching the syntax) does NOT
/// qualify — unlike the old `content.contains('[ ]')` membership rule.
bool hasChecklist(String content) => _kHasCheckbox.hasMatch(content);

({int open, int done, int total}) countChecklist(String content) {
  var open = 0;
  var done = 0;
  for (final item in parseChecklist(content)) {
    if (item.done) {
      done++;
    } else {
      open++;
    }
  }
  return (open: open, done: done, total: open + done);
}

/// Display text of the first open item with non-empty text, inline markdown
/// stripped; null when nothing is open. Powers the home "next up" subtitle.
String? firstOpenItem(String content) {
  for (final item in parseChecklist(content)) {
    if (!item.done && item.text.isNotEmpty) {
      return stripInlineMarkdown(item.text);
    }
  }
  return null;
}

/// True for onboarding-seeded reference content: the four workspace guides
/// (ids end `_guide`, tag `guide`) and the welcome note (id ends `_welcome`,
/// onboarding.dart). Seeds are demo material — excluded from task surfaces
/// (counts, Tasks list, widget todo payload, notifications). Id suffixes are
/// deterministic: generateId() ids end in 7 radix-36 chars, never these words.
bool isSeedNote(Note n) =>
    n.tags.contains('guide') ||
    n.id.endsWith('_welcome') ||
    n.id.endsWith('_guide');

/// Unified task-note membership for sidebar counts, the Tasks filter, and the
/// widget payload. Keeps the legacy title fallback; replaces the literal
/// `contains('[ ]')` clause with the line-anchored checklist test; excludes
/// seeds and archived/trashed notes.
bool isTaskNote(Note n) =>
    !n.isArchived &&
    !n.isDeleted &&
    !isSeedNote(n) &&
    (n.type == 'todo' ||
        n.tags.contains('todo') ||
        n.title.toLowerCase().contains('todo') ||
        hasChecklist(n.content));

/// Total OPEN checkbox items across visible non-seed notes — the one number
/// behind "N open tasks" (home meta) and "N tasks left" (evening recap).
int openTaskCount(Iterable<Note> notes) {
  var open = 0;
  for (final n in notes) {
    if (n.isArchived || n.isDeleted || isSeedNote(n)) continue;
    open += countChecklist(n.content).open;
  }
  return open;
}

/// Strips inline markdown from a single line of display text, keeping the
/// words: emphasis, code spans, strike, links, wikilinks; images vanish whole.
/// Lone underscores survive (snake_case); hyphens are never touched.
/// Idempotent — safe to apply to already-stripped text (the widget toggle
/// intent relies on this to compare in stripped space).
String stripInlineMarkdown(String text) {
  String keepGroup(Match m) => m.group(1) ?? '';
  var out = text
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[\[[^|\]\n]+\|([^\]\n]+)\]\]'), keepGroup)
      .replaceAllMapped(RegExp(r'\[\[([^\]\n]+)\]\]'), keepGroup)
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), keepGroup)
      .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), keepGroup)
      .replaceAllMapped(RegExp(r'__([^_]+)__'), keepGroup)
      .replaceAllMapped(RegExp(r'\*([^*\n]+)\*'), keepGroup)
      .replaceAllMapped(RegExp(r'~~([^~]+)~~'), keepGroup)
      .replaceAllMapped(RegExp(r'`([^`]+)`'), keepGroup);
  out = out.replaceAll('*', '').replaceAll('`', '');
  return out.trim();
}

/// One-line plain-text preview of markdown [content]: block syntax removed
/// (checkbox markers INCLUDING the x — no stray-x artifacts), inline markdown
/// stripped (code-span CONTENT kept), leftover brackets dropped, whitespace
/// collapsed, capped at [maxChars] without splitting surrogate pairs.
/// Replaces both legacy strippers (home char-class and note_list chain) so
/// every surface shows the same words.
String contentPreview(String content, {int maxChars = 120}) {
  var text = content
      .replaceAll(RegExp(r'^\s*-\s+\[[ xX]\]\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*---+\s*$', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\|.*$', multiLine: true), '')
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '');
  text = stripInlineMarkdown(text);
  text = text
      .replaceAll(RegExp(r'[\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.length > maxChars) {
    var cut = maxChars;
    final tail = text.codeUnitAt(cut - 1);
    if (tail >= 0xD800 && tail <= 0xDBFF) cut--;
    text = '${text.substring(0, cut)}...';
  }
  return text;
}

/// Preview for the Android recent-notes widget: the first non-empty,
/// non-heading line (fallback: the first line, heading marker stripped),
/// block marker and inline markdown stripped. Same selection rule as the
/// legacy payload builder — dash bullets no longer leak.
String firstPreviewLine(String content) {
  final lines = content.split('\n');
  String? first;
  for (final l in lines) {
    if (l.trim().isNotEmpty && !l.startsWith('#')) {
      first = l;
      break;
    }
  }
  final line = first ?? (lines.isNotEmpty ? lines.first : '');
  var text = line
      .replaceAll(RegExp(r'^\s*-\s+\[[ xX]\]\s*'), '')
      .replaceAll(RegExp(r'^#{1,6}\s+'), '')
      .replaceAll(RegExp(r'^\s*[-+>]\s+'), '');
  text = stripInlineMarkdown(text);
  return text.replaceAll(RegExp(r'[\[\]]'), '').trim();
}