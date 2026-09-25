import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/markdown_spans.dart';

void main() {
  const styles = MdSpanStyles(
    base: TextStyle(color: Color(0xFF111111), fontSize: 15, height: 1.5),
    syntaxColor: Color(0xFF222222),
    linkColor: Color(0xFF333333),
    codeColor: Color(0xFF444444),
    codeBackground: Color(0xFF555555),
    quoteColor: Color(0xFF666666),
    listMarkerColor: Color(0xFF777777),
    checkboxColor: Color(0xFF888888),
    checkboxCheckedColor: Color(0xFF999999),
    monoFontFamily: 'monospace',
  );
  final base = styles.base;

  List<TextSpan> leaves(TextSpan root) {
    final out = <TextSpan>[];
    void walk(TextSpan s) {
      final kids = s.children;
      if (kids == null || kids.isEmpty) {
        if (s.text != null) out.add(s);
        return;
      }
      for (final k in kids) {
        if (k is TextSpan) walk(k);
      }
    }

    walk(root);
    return out;
  }

  String flatten(TextSpan root) => leaves(root).map((s) => s.text ?? '').join();

  TextSpan build(String text, bool Function(int line) raw) =>
      buildMarkdownTextSpan(text: text, styles: styles, isRawLine: raw);

  const corpus = <String>[
    '# Title\n\nSome **bold** and *ital* and ~~x~~ and `code`.\n',
    '- [ ] task\n- [x] done\n- plain\n',
    '> quote line\n',
    '```\ncode block **not bold**\n```\n',
    '[[Wiki Link]] and [md](https://x.dev) and ![alt](img.png)\n',
    '---\n',
    'emoji 😀 **bold** after surrogate pair',
    '',
    'no markdown at all',
    'trailing newline\n',
    '#hashtag-not-heading',
  ];

  group('tokenizeMarkdownSpans', () {
    test('byte identity: sorted, contiguous, full coverage', () {
      for (final doc in corpus) {
        final spans = tokenizeMarkdownSpans(doc);
        final rebuilt = spans.map((s) => doc.substring(s.start, s.end)).join();
        expect(rebuilt, doc, reason: 'rebuilt text for ${doc.runes}');
        var cursor = 0;
        for (final s in spans) {
          expect(s.start, cursor, reason: 'gap/overlap in ${doc.runes}');
          expect(s.end, greaterThan(s.start));
          expect(s.end, lessThanOrEqualTo(doc.length));
          cursor = s.end;
        }
        expect(cursor, doc.length, reason: 'trailing gap in ${doc.runes}');
      }
    });

    test('empty text produces no spans', () {
      expect(tokenizeMarkdownSpans(''), isEmpty);
    });

    test('heading marker and level', () {
      final spans = tokenizeMarkdownSpans('# Title');
      expect(spans.first.role, MdRole.syntax);
      final heading = spans.firstWhere((s) => s.role == MdRole.heading);
      expect(heading.level, 1);
      expect(spans.firstWhere((s) => s.role == MdRole.heading).start, 2);
    });

    test('fence lines are syntax, inner lines are codeBlock', () {
      const doc = '```\ncode block **not bold**\n```\n';
      final spans = tokenizeMarkdownSpans(doc);
      expect(spans.any((s) => s.role == MdRole.strong), isFalse);
      final fences = spans
          .where((s) => doc.substring(s.start, s.end).contains('```'));
      for (final f in fences) {
        expect(f.role, MdRole.syntax);
      }
      final inside =
          spans.firstWhere((s) => s.role == MdRole.codeBlock && s.end - s.start > 1);
      expect(doc.substring(inside.start, inside.end).contains('**not bold**'),
          isTrue);
    });

    test('lone asterisk is text, not syntax or emphasis', () {
      final spans = tokenizeMarkdownSpans('a * b');
      expect(spans.length, 1);
      expect(spans.first.role, MdRole.text);
      expect(spans.any((s) => s.role == MdRole.syntax), isFalse);
      expect(spans.any((s) => s.role == MdRole.emphasis), isFalse);
    });

    test('checkbox carries checked state', () {
      final spans = tokenizeMarkdownSpans('- [x] done\n- [ ] open');
      final box = spans.firstWhere((s) => s.role == MdRole.checkbox);
      expect(box.checked, isTrue);
      expect(spans.where((s) => s.role == MdRole.checkbox).length, 2);
    });

    test('image alt text and md-link label are linkLabel', () {
      final spans =
          tokenizeMarkdownSpans('![alt](img.png) [md](https://x.dev)');
      final labels =
          spans.where((s) => s.role == MdRole.linkLabel).toList();
      expect(labels.map((s) => s.role), everyElement(MdRole.linkLabel));
      final texts = <String>[];
      final doc = '![alt](img.png) [md](https://x.dev)';
      for (final l in labels) {
        texts.add(doc.substring(l.start, l.end));
      }
      expect(texts, containsAll(<String>['alt', 'md']));
    });

    test('checked task body renders struck through, unchecked does not', () {
      final spans = tokenizeMarkdownSpans('- [x] done\n- [ ] open\n');
      String roleOf(String needle) {
        for (final s in spans) {
          final t = '- [x] done\n- [ ] open\n'.substring(s.start, s.end);
          if (t.contains(needle)) return s.role.name;
        }
        return 'missing';
      }

      expect(roleOf('done'), 'strike');
      expect(roleOf('open'), 'text');
    });
  });

  group('buildMarkdownTextSpan', () {
    test('byte identity, raw and non-raw', () {
      for (final doc in corpus) {
        expect(flatten(build(doc, (_) => true)), doc,
            reason: 'raw flatten for ${doc.runes}');
        expect(flatten(build(doc, (_) => false)), doc,
            reason: 'hidden flatten for ${doc.runes}');
      }
    });

    test('empty text returns an empty root', () {
      final root = build('', (_) => true);
      expect(root.text, '');
      expect(flatten(root), '');
    });

    test('adjacent identical styles are merged', () {
      final root = build('plain text', (_) => false);
      expect(leaves(root).length, 1);
    });

    test('hidden syntax off-cursor is invisible', () {
      final root = build('**bold**', (_) => false);
      final markers = leaves(root).where((s) => s.text == '**').toList();
      expect(markers.length, 2);
      for (final m in markers) {
        expect(m.style!.fontSize, 0.1);
        expect(m.style!.color, const Color(0x00000000));
      }
      final bold = leaves(root).firstWhere((s) => s.text == 'bold');
      expect(bold.style!.fontWeight, FontWeight.w700);
    });

    test('raw line shows syntax dimmed at body size', () {
      final root = build('**bold**', (_) => true);
      final markers = leaves(root).where((s) => s.text == '**').toList();
      expect(markers.length, 2);
      for (final m in markers) {
        expect(m.style!.color, styles.syntaxColor);
        expect(m.style!.fontSize, base.fontSize);
      }
    });

    test('per-line rawness', () {
      final root = build('# A\nplain', (line) => line == 1);
      final all = leaves(root);
      final marker = all.firstWhere((s) => s.text == '# ');
      expect(marker.style!.fontSize, 0.1);
      final a = all.firstWhere((s) => s.text == 'A');
      expect(a.style!.fontSize, base.fontSize! * 1.5);
      expect(a.style!.fontWeight, FontWeight.w700);
      expect(a.style!.height, 1.25);
      final plain =
          all.firstWhere((s) => (s.text ?? '').contains('plain'));
      expect(plain.style!.fontSize, base.fontSize);
      expect(plain.style!.color, base.color);
    });

    test('checkbox and list marker stay visible off-cursor', () {
      final root = build('- [x] done', (_) => false);
      final all = leaves(root);
      final box = all.firstWhere((s) => (s.text ?? '').contains('[x]'));
      expect(box.style!.fontSize, isNot(0.1));
      expect(box.style!.color, styles.checkboxCheckedColor);
      expect(box.style!.fontWeight, FontWeight.w700);
      final marker = all.firstWhere((s) => s.text == '- ');
      expect(marker.style!.fontSize, isNot(0.1));
      expect(marker.style!.color, styles.listMarkerColor);
    });

    test('unchecked box uses checkboxColor', () {
      final root = build('- [ ] task', (_) => false);
      final box = leaves(root).firstWhere((s) => (s.text ?? '').contains('[ ]'));
      expect(box.style!.fontSize, isNot(0.1));
      expect(box.style!.color, styles.checkboxColor);
    });

    test('inline code uses mono family and background', () {
      final root = build('a `x` b', (_) => false);
      final code = leaves(root).firstWhere((s) => s.text == 'x');
      expect(code.style!.fontFamily, styles.monoFontFamily);
      expect(code.style!.color, styles.codeColor);
      expect(code.style!.backgroundColor, styles.codeBackground);
    });

    test('heading levels scale', () {
      final root = build('## Two', (_) => true);
      final two = leaves(root).firstWhere((s) => s.text == 'Two');
      expect(two.style!.fontSize, base.fontSize! * 1.3);
      expect(two.style!.fontWeight, FontWeight.w700);
    });

    test('fence content is codeBlock, never strong', () {
      final root = build('```\ncode **not bold**\n```\n', (_) => true);
      final all = leaves(root);
      expect(all.any((s) => s.style!.fontWeight == FontWeight.w700), isFalse);
      final mono =
          all.where((s) => s.style!.fontFamily == styles.monoFontFamily);
      expect(mono.map((s) => s.text ?? '').join(), contains('**not bold**'));
    });
  });
}