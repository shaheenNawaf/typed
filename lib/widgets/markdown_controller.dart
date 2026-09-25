import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../utils/markdown_spans.dart';

/// A [TextEditingController] that renders markdown WYSIWYG: syntax characters
/// are visually hidden off the cursor line(s) and shown dimmed on them. The
/// stored [text] is always pure markdown — only the display is styled.
///
/// [styles].base MUST equal the TextField's effective `style` so caret metrics
/// and painted glyphs agree.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController(
      {super.text, required this.styles, bool rawMode = false})
      : _rawMode = rawMode;

  MdSpanStyles styles;

  bool _rawMode;
  bool get rawMode => _rawMode;
  set rawMode(bool value) {
    if (_rawMode == value) return;
    _rawMode = value;
    _invalidateSpanCache();
    notifyListeners();
  }

  String? _cachedForText;
  bool? _cachedForRawMode;
  Set<int>? _cachedForLines;
  TextStyle? _cachedForStyle;
  TextSpan? _cachedSpan;

  void _invalidateSpanCache() {
    _cachedSpan = null;
    _cachedForText = null;
    _cachedForLines = null;
    _cachedForStyle = null;
    _cachedForRawMode = null;
  }

  /// Line indices touched by the current selection (collapsed cursor -> one
  /// line; extended selection -> every line it spans). Invalid selection ->
  /// empty set (everything hidden-syntax, which is safe: no caret is shown
  /// without a valid selection anyway).
  Set<int> computeRawLines() {
    if (_rawMode) return const <int>{};
    final s = selection;
    if (!s.isValid || !s.isNormalized) return const <int>{};
    final t = text;
    int lineOf(int offset) {
      var line = 0;
      final end = offset.clamp(0, t.length);
      for (var i = 0; i < end; i++) {
        if (t.codeUnitAt(i) == 0x0A) line++;
      }
      return line;
    }
    final first = lineOf(s.start);
    final last = s.isCollapsed ? first : lineOf(s.end);
    return {for (var l = first; l <= last; l++) l};
  }

  @override
  TextSpan buildTextSpan({
    BuildContext? context,
    TextStyle? style,
    bool? withComposing,
  }) {
    // withComposing is intentionally ignored: IME composing text sits on the
    // cursor line, which renders raw anyway.
    if (_rawMode) {
      return TextSpan(style: style, text: text);
    }
    final rawLines = computeRawLines();
    final cached = _cachedSpan;
    if (cached != null &&
        _cachedForText == text &&
        _cachedForRawMode == false &&
        _cachedForStyle == style &&
        _cachedForLines != null &&
        setEquals(_cachedForLines!, rawLines)) {
      return cached;
    }
    final effectiveBase = style ?? styles.base;
    final effective = styles.base == effectiveBase
        ? styles
        : MdSpanStyles(
            base: effectiveBase,
            syntaxColor: styles.syntaxColor,
            linkColor: styles.linkColor,
            codeColor: styles.codeColor,
            codeBackground: styles.codeBackground,
            quoteColor: styles.quoteColor,
            listMarkerColor: styles.listMarkerColor,
            checkboxColor: styles.checkboxColor,
            checkboxCheckedColor: styles.checkboxCheckedColor,
            monoFontFamily: styles.monoFontFamily,
          );
    final span = buildMarkdownTextSpan(
      text: text,
      styles: effective,
      isRawLine: rawLines.contains,
    );
    _cachedSpan = span;
    _cachedForText = text;
    _cachedForRawMode = false;
    _cachedForStyle = style;
    _cachedForLines = rawLines;
    return span;
  }

  /// Setting [text]/[value] must bust the memo.
  @override
  set text(String newText) {
    _invalidateSpanCache();
    super.text = newText;
  }

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text != text) _invalidateSpanCache();
    super.value = newValue;
  }
}