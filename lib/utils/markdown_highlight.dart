import 'package:flutter/painting.dart';

/// Colour-only live highlighting for the raw-markdown editor.
///
/// HARD RULE: every span keeps [base]'s metrics (family/size/weight/height)
/// exactly — only color, decoration and background may differ. The rendered
/// layer sits under a transparent-text TextField; any advance-width change
/// would drift the highlight away from the caret.
///
/// Invariant (unit-tested): concatenating every span's text reproduces the
/// input string byte-for-byte.
List<TextSpan> highlightMarkdownSpans(
  String text, {
  required TextStyle base,
  required Color syntax,
  required Color link,
  required Color codeBg,
}) {
  final spans = <TextSpan>[];

  void add(
    String t, {
    Color? color,
    TextDecoration? decoration,
    Color? background,
  }) {
    if (t.isEmpty) return;
    spans.add(
      TextSpan(
        text: t,
        style: base.copyWith(
          color: color ?? base.color,
          decoration: decoration,
          decorationColor: decoration == null ? null : (color ?? base.color),
          background: background == null ? null : (Paint()..color = background),
        ),
      ),
    );
  }

  final inline = RegExp(
    r'(?<code>`[^`]+`)'
    r'|(?<bold>\*\*[^*]+\*\*|__[^_]+__)'
    r'|(?<strike>~~[^~]+~~)'
    r'|(?<italic>\*[^*\n]+\*|(?<![A-Za-z0-9_])_[^_\n]+_(?![A-Za-z0-9_]))'
    r'|(?<wiki>\[\[[^\]\n|]+(?:\|[^\]\n]+)?\]\])'
    r'|(?<img>!\[[^\]\n]*\]\([^)\n]*\))'
    r'|(?<mdlink>\[[^\]\n]*\]\([^)\n]*\))',
  );

  void addInline(String s) {
    var pos = 0;
    for (final m in inline.allMatches(s)) {
      add(s.substring(pos, m.start));
      final g = m.group(0)!;
      if (m.namedGroup('code') != null) {
        add('`', color: syntax);
        add(g.substring(1, g.length - 1), background: codeBg);
        add('`', color: syntax);
      } else if (m.namedGroup('bold') != null) {
        final marker = g.startsWith('**') ? '**' : '__';
        add(marker, color: syntax);
        add(g.substring(2, g.length - 2));
        add(marker, color: syntax);
      } else if (m.namedGroup('strike') != null) {
        add('~~', color: syntax);
        add(
          g.substring(2, g.length - 2),
          decoration: TextDecoration.lineThrough,
        );
        add('~~', color: syntax);
      } else if (m.namedGroup('italic') != null) {
        final marker = g.startsWith('*') ? '*' : '_';
        add(marker, color: syntax);
        add(g.substring(1, g.length - 1));
        add(marker, color: syntax);
      } else if (m.namedGroup('wiki') != null) {
        add('[[', color: syntax);
        final inner = g.substring(2, g.length - 2);
        final pipe = inner.indexOf('|');
        if (pipe >= 0) {
          add(
            inner.substring(0, pipe),
            color: link,
            decoration: TextDecoration.underline,
          );
          add('|', color: syntax);
          add(
            inner.substring(pipe + 1),
            color: link,
            decoration: TextDecoration.underline,
          );
        } else {
          add(inner, color: link, decoration: TextDecoration.underline);
        }
        add(']]', color: syntax);
      } else if (m.namedGroup('img') != null) {
        // Images vanish whole in preview; dim the entire construct.
        add(g, color: syntax);
      } else {
        // [text](url)
        final close = g.indexOf('](');
        add('[', color: syntax);
        add(
          g.substring(1, close),
          color: link,
          decoration: TextDecoration.underline,
        );
        add('](', color: syntax);
        add(g.substring(close + 2, g.length - 1), color: syntax);
        add(')', color: syntax);
      }
      pos = m.end;
    }
    add(s.substring(pos));
  }

  final lines = text.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final eol = i == lines.length - 1 ? '' : '\n';
    if (line.trimLeft().startsWith('```')) {
      add(line + eol, color: syntax);
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      add(line + eol);
      continue;
    }
    if (RegExp(r'^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
      add(line + eol, color: syntax);
      continue;
    }
    final heading = RegExp(r'^(#{1,6} )(.*)$').firstMatch(line);
    if (heading != null) {
      add(heading.group(1)!, color: syntax);
      addInline(heading.group(2)!);
      add(eol);
      continue;
    }
    final quote = RegExp(r'^(> ?)(.*)$').firstMatch(line);
    if (quote != null) {
      add(quote.group(1)!, color: syntax);
      addInline(quote.group(2)!);
      add(eol);
      continue;
    }
    final item =
        RegExp(r'^(\s*(?:[-*+]|\d+\.) )(\[[ xX]\] )?(.*)$').firstMatch(line);
    if (item != null) {
      add(item.group(1)!, color: syntax);
      final box = item.group(2);
      final rest = item.group(3)!;
      if (box != null) {
        add(box, color: syntax);
        if (box.contains('x') || box.contains('X')) {
          add(rest, color: syntax, decoration: TextDecoration.lineThrough);
        } else {
          addInline(rest);
        }
      } else {
        addInline(rest);
      }
      add(eol);
      continue;
    }
    addInline(line);
    add(eol);
  }
  return spans;
}