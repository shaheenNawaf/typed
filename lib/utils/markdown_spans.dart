import 'package:flutter/painting.dart';

/// Role of a token range. `syntax` ranges are the markdown punctuation itself
/// (markers like **, #, >, -, `, [[, ]], ()[], fence lines, hr lines).
enum MdRole {
  text,
  syntax, // hidden off-cursor, dimmed on cursor line
  strong, // **bold** content
  emphasis, // *italic* content
  strike, // ~~gone~~ content, or checked task body
  code, // `inline code` content
  codeBlock, // fenced block content lines
  linkLabel, // [[wiki]] label, [md](url) label, image alt text
  heading, // heading text content (level in MdSpan.level)
  quote, // blockquote content (after '> ')
  listMarker, // '- ', '* ', '+ ', '1. ' — VISIBLE always (reads as bullet)
  checkbox, // '[ ]' / '[x]' — VISIBLE always (state must show)
}

class MdSpan {
  final int start; // inclusive, UTF-16 code units (Dart String indices)
  final int end; // exclusive
  final MdRole role;
  final int line; // 0-based line index (split on '\n')
  final int level; // heading level 1-6; 0 for non-headings
  final bool checked; // checkbox state; false for non-checkboxes
  const MdSpan(this.start, this.end, this.role, this.line,
      {this.level = 0, this.checked = false});
}

final RegExp _inline = RegExp(
  r'(?<code>`[^`]+`)'
  r'|(?<bold>\*\*[^*]+\*\*|__[^_]+__)'
  r'|(?<strike>~~[^~]+~~)'
  r'|(?<italic>\*[^*\n]+\*|(?<![A-Za-z0-9_])_[^_\n]+_(?![A-Za-z0-9_]))'
  r'|(?<wiki>\[\[[^\]\n|]+(?:\|[^\]\n]+)?\]\])'
  r'|(?<img>!\[[^\]\n]*\]\([^)\n]*\))'
  r'|(?<mdlink>\[[^\]\n]*\]\([^)\n]*\))',
);

final RegExp _hr = RegExp(r'^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _heading = RegExp(r'^(#{1,6} )(.*)$');
final RegExp _quote = RegExp(r'^(> ?)(.*)$');
final RegExp _item =
    RegExp(r'^(\s*(?:[-*+]|\d+\.) )(\[[ xX]\] )?(.*)$');

/// Tokenizes [text] into sorted, non-overlapping spans that COVER [text]
/// completely: concatenating text.substring(s.start, s.end) for all spans in
/// order reproduces [text] byte-for-byte. This invariant is load-bearing —
/// the caret geometry of the TextField is computed from these spans.
List<MdSpan> tokenizeMarkdownSpans(String text) {
  final spans = <MdSpan>[];

  void addRange(int start, int end, MdRole role, int line,
      {int level = 0, bool checked = false}) {
    if (end <= start) return;
    spans.add(MdSpan(start, end, role, line, level: level, checked: checked));
  }

  void addInline(String s, int absStart, int line,
      {MdRole plainRole = MdRole.text, int level = 0}) {
    var pos = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > pos) {
        addRange(absStart + pos, absStart + m.start, plainRole, line,
            level: level);
      }
      final g = m.group(0)!;
      final ms = absStart + m.start;
      final me = absStart + m.end;
      if (m.namedGroup('code') != null) {
        addRange(ms, ms + 1, MdRole.syntax, line);
        addRange(ms + 1, me - 1, MdRole.code, line);
        addRange(me - 1, me, MdRole.syntax, line);
      } else if (m.namedGroup('bold') != null) {
        addRange(ms, ms + 2, MdRole.syntax, line);
        addRange(ms + 2, me - 2, MdRole.strong, line);
        addRange(me - 2, me, MdRole.syntax, line);
      } else if (m.namedGroup('strike') != null) {
        addRange(ms, ms + 2, MdRole.syntax, line);
        addRange(ms + 2, me - 2, MdRole.strike, line);
        addRange(me - 2, me, MdRole.syntax, line);
      } else if (m.namedGroup('italic') != null) {
        addRange(ms, ms + 1, MdRole.syntax, line);
        addRange(ms + 1, me - 1, MdRole.emphasis, line);
        addRange(me - 1, me, MdRole.syntax, line);
      } else if (m.namedGroup('wiki') != null) {
        addRange(ms, ms + 2, MdRole.syntax, line);
        final pipe = g.substring(2, g.length - 2).indexOf('|');
        if (pipe >= 0) {
          addRange(ms + 2, ms + 2 + pipe, MdRole.linkLabel, line);
          addRange(ms + 2 + pipe, ms + 3 + pipe, MdRole.syntax, line);
          addRange(ms + 3 + pipe, me - 2, MdRole.linkLabel, line);
        } else {
          addRange(ms + 2, me - 2, MdRole.linkLabel, line);
        }
        addRange(me - 2, me, MdRole.syntax, line);
      } else if (m.namedGroup('img') != null) {
        final close = g.indexOf('](');
        addRange(ms, ms + 1, MdRole.syntax, line);
        addRange(ms + 1, ms + 2, MdRole.syntax, line);
        addRange(ms + 2, ms + close, MdRole.linkLabel, line);
        addRange(ms + close, ms + close + 2, MdRole.syntax, line);
        addRange(ms + close + 2, me - 1, MdRole.syntax, line);
        addRange(me - 1, me, MdRole.syntax, line);
      } else {
        final close = g.indexOf('](');
        addRange(ms, ms + 1, MdRole.syntax, line);
        addRange(ms + 1, ms + close, MdRole.linkLabel, line);
        addRange(ms + close, ms + close + 2, MdRole.syntax, line);
        addRange(ms + close + 2, me - 1, MdRole.syntax, line);
        addRange(me - 1, me, MdRole.syntax, line);
      }
      pos = m.end;
    }
    if (pos < s.length) {
      addRange(
          absStart + pos, absStart + s.length, plainRole, line, level: level);
    }
  }

  final lines = text.split('\n');
  var inFence = false;
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final lineStart = offset;
    offset += raw.length + (i == lines.length - 1 ? 0 : 1);

    final hasCr = raw.endsWith('\r');
    final line = hasCr ? raw.substring(0, raw.length - 1) : raw;
    final coreStart = lineStart;
    final coreEnd = lineStart + line.length;
    final crStart = coreEnd;
    final crEnd = hasCr ? coreEnd + 1 : coreEnd;
    final nlStart = crEnd;
    final nlEnd = i == lines.length - 1 ? crEnd : crEnd + 1;

    void endLine(MdRole role) {
      if (hasCr) addRange(crStart, crEnd, MdRole.text, i);
      addRange(nlStart, nlEnd, role, i);
    }

    if (line.trimLeft().startsWith('```')) {
      addRange(coreStart, coreEnd, MdRole.syntax, i);
      endLine(MdRole.syntax);
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      addRange(coreStart, coreEnd, MdRole.codeBlock, i);
      endLine(MdRole.codeBlock);
      continue;
    }
    if (_hr.hasMatch(line)) {
      addRange(coreStart, coreEnd, MdRole.syntax, i);
      endLine(MdRole.syntax);
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final mlen = heading.group(1)!.length;
      addRange(coreStart, coreStart + mlen, MdRole.syntax, i);
      addInline(line.substring(mlen), coreStart + mlen, i,
          plainRole: MdRole.heading, level: heading.group(1)!.trim().length);
      endLine(MdRole.text);
      continue;
    }
    final quote = _quote.firstMatch(line);
    if (quote != null) {
      final mlen = quote.group(1)!.length;
      addRange(coreStart, coreStart + mlen, MdRole.syntax, i);
      addInline(line.substring(mlen), coreStart + mlen, i,
          plainRole: MdRole.quote);
      endLine(MdRole.text);
      continue;
    }
    final item = _item.firstMatch(line);
    if (item != null) {
      final marker = item.group(1)!;
      final box = item.group(2);
      final rest = item.group(3)!;
      var p = coreStart;
      addRange(p, p + marker.length, MdRole.listMarker, i);
      p += marker.length;
      var checked = false;
      if (box != null) {
        checked = box.contains('x') || box.contains('X');
        addRange(p, p + box.length, MdRole.checkbox, i, checked: checked);
        p += box.length;
      }
      addInline(rest, p, i, plainRole: checked ? MdRole.strike : MdRole.text);
      endLine(MdRole.text);
      continue;
    }
    addInline(line, coreStart, i);
    endLine(MdRole.text);
  }
  return spans;
}

class MdSpanStyles {
  final TextStyle base; // the TextField's body style
  final Color syntaxColor; // dimmed syntax on cursor line(s)
  final Color linkColor;
  final Color codeColor;
  final Color codeBackground;
  final Color quoteColor;
  final Color listMarkerColor;
  final Color checkboxColor; // unchecked box + brackets
  final Color checkboxCheckedColor;
  final String monoFontFamily;
  const MdSpanStyles({
    required this.base,
    required this.syntaxColor,
    required this.linkColor,
    required this.codeColor,
    required this.codeBackground,
    required this.quoteColor,
    required this.listMarkerColor,
    required this.checkboxColor,
    required this.checkboxCheckedColor,
    required this.monoFontFamily,
  });
}

double _headingFactor(int level) {
  switch (level) {
    case 1:
      return 1.5;
    case 2:
      return 1.3;
    case 3:
      return 1.15;
    default:
      return 1.05;
  }
}

/// Builds the display TextSpan tree. Concatenated span text MUST equal [text]
/// exactly (same invariant as the tokenizer).
/// [isRawLine] returns true for lines that should show their syntax dimmed
/// (the cursor line / selection-spanned lines / raw mode = all lines).
TextSpan buildMarkdownTextSpan({
  required String text,
  required MdSpanStyles styles,
  required bool Function(int lineIndex) isRawLine,
}) {
  final base = styles.base;
  if (text.isEmpty) {
    return TextSpan(style: base, text: '');
  }
  final fs = base.fontSize ?? 14;

  TextStyle styleFor(MdSpan s) {
    switch (s.role) {
      case MdRole.text:
        return base;
      case MdRole.syntax:
        if (!isRawLine(s.line)) {
          return base.copyWith(
            color: const Color(0x00000000),
            fontSize: 0.1,
            height: 1.0,
            letterSpacing: 0,
            wordSpacing: 0,
            decoration: TextDecoration.none,
            backgroundColor: null,
            shadows: const [],
          );
        }
        return base.copyWith(color: styles.syntaxColor);
      case MdRole.strong:
        return base.copyWith(fontWeight: FontWeight.w700);
      case MdRole.emphasis:
        return base.copyWith(fontStyle: FontStyle.italic);
      case MdRole.strike:
        return base.copyWith(decoration: TextDecoration.lineThrough);
      case MdRole.code:
      case MdRole.codeBlock:
        return base.copyWith(
          fontFamily: styles.monoFontFamily,
          color: styles.codeColor,
          backgroundColor: styles.codeBackground,
        );
      case MdRole.linkLabel:
        return base.copyWith(
          color: styles.linkColor,
          decoration: TextDecoration.underline,
        );
      case MdRole.heading:
        return base.copyWith(
          fontSize: fs * _headingFactor(s.level),
          fontWeight: FontWeight.w700,
          height: 1.25,
        );
      case MdRole.quote:
        return base.copyWith(color: styles.quoteColor);
      case MdRole.listMarker:
        return base.copyWith(color: styles.listMarkerColor);
      case MdRole.checkbox:
        return s.checked
            ? base.copyWith(
                color: styles.checkboxCheckedColor,
                fontWeight: FontWeight.w700,
              )
            : base.copyWith(color: styles.checkboxColor);
    }
  }

  final spans = tokenizeMarkdownSpans(text);
  final merged = <TextSpan>[];
  for (final s in spans) {
    final t = text.substring(s.start, s.end);
    if (t.isEmpty) continue;
    final style = styleFor(s);
    if (merged.isNotEmpty && merged.last.style == style) {
      merged.add(TextSpan(text: merged.removeLast().text! + t, style: style));
    } else {
      merged.add(TextSpan(text: t, style: style));
    }
  }
  return TextSpan(style: base, children: merged);
}