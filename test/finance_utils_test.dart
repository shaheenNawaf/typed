import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/finance_utils.dart';

void main() {
  const style = TextStyle(fontSize: 22);

  List<String> texts(List<TextSpan> spans) =>
      spans.map((s) => s.text ?? '').toList();

  test('negative amount puts U+2212 before the symbol', () {
    expect(texts(moneySpans(-50000, 'PHP', style)),
        ['\u2212', '₱', '500.00']);
  });

  test('positive amount has no sign span', () {
    expect(texts(moneySpans(50000, 'PHP', style)), ['₱', '500.00']);
  });

  test('zero has no sign span', () {
    expect(texts(moneySpans(0, 'PHP', style)), ['₱', '0.00']);
  });

  test('large negative keeps grouping', () {
    expect(texts(moneySpans(-123456789, 'PHP', style)),
        ['\u2212', '₱', '1,234,567.89']);
  });

  test('JPY has no decimals', () {
    expect(texts(moneySpans(-500, 'JPY', style)), ['\u2212', '¥', '500']);
  });

  test('sign span uses the symbol-safe font stack', () {
    final spans = moneySpans(-1, 'PHP', style);
    expect(spans.first.style?.fontFamily, 'Roboto');
    expect(spans.first.style?.fontFamilyFallback,
        contains('Noto Sans'));
  });
}