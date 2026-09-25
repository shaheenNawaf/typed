import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/markdown_highlight.dart';

void main() {
  const base = TextStyle(color: Color(0xFF00000F), fontSize: 15, height: 1.6);
  const syntax = Color(0xFF000001);
  const link = Color(0xFF000002);
  const codeBg = Color(0xFF000003);

  List<TextSpan> hl(String t) => highlightMarkdownSpans(
        t,
        base: base,
        syntax: syntax,
        link: link,
        codeBg: codeBg,
      );

  String flat(List<TextSpan> s) => s.map((e) => e.text ?? '').join();

  const corpus = <String>[
    '',
    'plain text',
    '# Heading',
    '## H2 **bold**',
    '- [ ] open item',
    '- [x] done item',
    '- [X] done upper',
    '1. numbered',
    '> quoted',
    '```\nfenced\n```',
    'text `code` text',
    '**bold** and *italic* and ~~strike~~',
    '[[Wiki]] tail',
    '[[id|Alias]]',
    '[link](http://x)',
    '![img](p.png)',
    '---',
    'snake_case_word',
    'mixed - [ ] a **b** `c` [[d]]',
    'multi\nline\n---\ntext',
    'unpaired ** and ` and [[',
  ];

  group('highlightMarkdownSpans', () {
    test('invariant: span text concatenates back to the input', () {
      for (final input in corpus) {
        expect(flat(hl(input)), input);
      }
    });

    test('bold markers dim, content keeps base color', () {
      final spans = hl('**bold**');
      expect(spans.map((e) => e.text).toList(), ['**', 'bold', '**']);
      expect(spans[0].style!.color, syntax);
      expect(spans[1].style!.color, base.color);
      expect(spans[2].style!.color, syntax);
    });

    test('done item strikes through', () {
      final span =
          hl('- [x] done').firstWhere((s) => (s.text ?? '').contains('done'));
      expect(span.style!.decoration, TextDecoration.lineThrough);
    });

    test('code span background', () {
      final span = hl('a `x` b').firstWhere((s) => s.text == 'x');
      expect(span.style!.background, isNotNull);
    });

    test('wikilink tint + underline', () {
      final spans = hl('[[Note]]');
      final note = spans.firstWhere((s) => s.text == 'Note');
      expect(note.style!.color, link);
      expect(note.style!.decoration, TextDecoration.underline);
      expect(spans.firstWhere((s) => s.text == '[[').style!.color, syntax);
      expect(spans.firstWhere((s) => s.text == ']]').style!.color, syntax);
    });

    test('alias wikilink keeps raw text and tints the alias', () {
      expect(flat(hl('[[id|Alias]]')), '[[id|Alias]]');
      final alias = hl('[[id|Alias]]').firstWhere((s) => s.text == 'Alias');
      expect(alias.style!.color, link);
    });

    test('fence dims the fence, code line keeps base color', () {
      final spans = hl('```\ncode\n```');
      expect(spans.first.text!.startsWith('```'), isTrue);
      expect(spans.first.style!.color, syntax);
      final code = spans.firstWhere((s) => (s.text ?? '').contains('code'));
      expect(code.style!.color, base.color);
    });

    test('snake_case untouched', () {
      expect(hl('a_b_c').length, 1);
    });

    test('empty input produces no spans', () {
      expect(hl(''), isEmpty);
    });

    test('heading marker', () {
      final spans = hl('# T');
      expect(spans.map((e) => e.text).toList(), ['# ', 'T']);
      expect(spans.first.style!.color, syntax);
    });

    test('metrics rule: no span alters family/size/weight/height', () {
      for (final input in corpus) {
        for (final span in hl(input)) {
          final style = span.style!;
          expect(style.fontSize, base.fontSize);
          expect(style.fontWeight, base.fontWeight);
          expect(style.fontFamily, base.fontFamily);
          expect(style.height, base.height);
        }
      }
    });
  });
}