import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/markdown_spans.dart';
import 'package:typed/widgets/markdown_controller.dart';

void main() {
  const base = TextStyle(fontSize: 16, color: Color(0xFF111111));
  MdSpanStyles styles() => const MdSpanStyles(
        base: base,
        syntaxColor: Color(0xFF888888),
        linkColor: Color(0xFFE8590C),
        codeColor: Color(0xFF333333),
        codeBackground: Color(0x11000000),
        quoteColor: Color(0xFF777777),
        listMarkerColor: Color(0xFF999999),
        checkboxColor: Color(0xFF999999),
        checkboxCheckedColor: Color(0xFF2B8A3E),
        monoFontFamily: 'monospace',
      );
  // NOTE: if MdSpanStyles is not const-constructible, drop `const`.

  String flatten(InlineSpan span) {
    final b = StringBuffer();
    span.visitChildren((s) {
      if (s is TextSpan) b.write(s.text ?? '');
      return true;
    });
    return b.toString();
  }

  List<TextSpan> leafSpans(TextSpan root) {
    final out = <TextSpan>[];
    root.visitChildren((s) {
      if (s is TextSpan && (s.children == null || s.children!.isEmpty)) out.add(s);
      return true;
    });
    return out;
  }

  MarkdownEditingController ctrl(String text, {int? cursor, bool raw = false}) {
    final c = MarkdownEditingController(text: text, styles: styles(), rawMode: raw);
    if (cursor != null) c.selection = TextSelection.collapsed(offset: cursor);
    return c;
  }

  test('byte identity through the controller', () {
    const doc = '# Title\n\nSome **bold** and `code`.\n- [ ] task\n';
    final c = ctrl(doc, cursor: 0);
    final span = c.buildTextSpan(style: base, withComposing: false);
    expect(flatten(span), doc);
  });

  test('raw mode returns plain text span', () {
    const doc = '**bold**';
    final c = ctrl(doc, cursor: 0, raw: true);
    final span = c.buildTextSpan(style: base, withComposing: false);
    expect(span.toPlainText(), doc);
    expect((span).children, isNull);
    c.rawMode = false;
    final span2 = c.buildTextSpan(style: base, withComposing: false);
    expect(flatten(span2), doc);
    // off-cursor? cursor is at 0 -> line 0 raw -> syntax dimmed, not hidden
    final syntax = leafSpans(span2).firstWhere((s) => s.text == '**');
    expect(syntax.style?.fontSize, base.fontSize);
  });

  test('cursor line shows syntax dimmed, other lines hide it', () {
    const doc = '# A\n**b**';
    final c = ctrl(doc, cursor: 0); // line 0 raw
    final span = c.buildTextSpan(style: base, withComposing: false);
    final leaves = leafSpans(span);
    final hash = leaves.firstWhere((s) => s.text == '# ');
    expect(hash.style?.color, const Color(0xFF888888)); // syntaxColor, full size
    expect(hash.style?.fontSize, isNot(0.1));
    final stars = leaves.where((s) => s.text == '**').toList();
    expect(stars, isNotEmpty);
    for (final st in stars) {
      expect(st.style?.fontSize, 0.1); // hidden on non-raw line 1
    }
  });

  test('multi-line selection makes every spanned line raw', () {
    const doc = '**a**\n**b**';
    final c = ctrl(doc);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: doc.length);
    final span = c.buildTextSpan(style: base, withComposing: false);
    for (final st in leafSpans(span).where((s) => s.text == '**')) {
      expect(st.style?.fontSize, isNot(0.1));
    }
  });

  test('span cache reuses identical instance until text or lines change', () {
    final c = ctrl('**a**\nplain', cursor: 0);
    final s1 = c.buildTextSpan(style: base, withComposing: false);
    final s2 = c.buildTextSpan(style: base, withComposing: false);
    expect(identical(s1, s2), isTrue);
    c.selection = const TextSelection.collapsed(offset: 6); // line 1
    final s3 = c.buildTextSpan(style: base, withComposing: false);
    expect(identical(s1, s3), isFalse);
    c.text = '**b**\nplain';
    final s4 = c.buildTextSpan(style: base, withComposing: false);
    expect(identical(s3, s4), isFalse);
    expect(flatten(s4), '**b**\nplain');
  });

  testWidgets('TextField smoke: typing and caret work', (tester) async {
    final c = ctrl('# hi\n', cursor: 5);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextField(controller: c, style: base, maxLines: null),
      ),
    ));
    await tester.enterText(find.byType(TextField), '# hi **you**\n');
    await tester.pump();
    expect(c.text, '# hi **you**\n');
    expect(tester.takeException(), isNull);
  });
}