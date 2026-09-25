import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String currencySymbol(String? code) {
  switch (code) {
    case 'PHP':
      return '₱';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'JPY':
      return '¥';
    case 'INR':
      return '₹';
    case null:
      return '₱';
    default:
      return code;
  }
}

String formatNumber(double value, {int decimals = 2}) {
  // The old code grouped the '-' sign as if it were a digit, producing
  // "-,250.00" for negative balances.
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  // Sign follows the *rounded* value so -0.001 shows as "0.00", not "-0.00".
  final showSign = negative && double.parse(fixed) != 0;
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  if (parts.length > 1) {
    buffer.write('.');
    buffer.write(parts[1]);
  }
  return showSign ? '-${buffer.toString()}' : buffer.toString();
}

/// Fractional digits per currency (JPY has no minor unit).
int currencyDecimals(String? code) => code == 'JPY' ? 0 : 2;

int _pow10(int n) {
  var result = 1;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

/// Parses user input in a currency to integer minor units. Accepts both
/// `.` and `,` decimal separators (Android's numeric pad emits `,` in
/// comma-decimal locales) and caps fractional digits at the currency's
/// exponent, so double values cannot be entered or stored.
int? parseAmountToMinor(String input, String? currency) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final decimals = currencyDecimals(currency);
  final pattern = decimals == 0
      ? r'^([0-9]+)$'
      : '^([0-9]+)(?:\\.([0-9]{1,$decimals}))?\$';
  final match = RegExp(pattern).firstMatch(normalized);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = match.groupCount > 1 ? match.group(2) : null;
  final scale = _pow10(decimals);
  final fracValue = fraction == null
      ? 0
      : int.parse(fraction.padRight(decimals, '0'));
  return whole * scale + fracValue;
}

/// Integer minor units -> major units as a double, for display helpers.
double minorToMajor(int minor, String? currency) =>
    minor / _pow10(currencyDecimals(currency));

/// Decodes a persisted amount that may be legacy majors ([double], pre
/// minor-units builds) or modern minor units ([int]).
int decodeMinorAmount(Object? value, String? currency) {
  if (value is int) return value;
  if (value is num) {
    return (value.toDouble() * _pow10(currencyDecimals(currency))).round();
  }
  return 0;
}

/// Formats minor units with grouping and the right number of decimals.
String formatMinor(int minor, String? currency) {
  final decimals = currencyDecimals(currency);
  return formatNumber(minorToMajor(minor, currency), decimals: decimals);
}

/// Formats an integer minor-unit amount for display.
String formatMinorAmount(int minor, String? currency) {
  return '${currencySymbol(currency)}${formatMinor(minor, currency)}';
}

// ponytail: strict numeric input — digits plus at most one '.' or ',' and at
// most the currency's fractional digits. Negative signs and letters never
// get through, and both decimal separators work regardless of locale.
final List<TextInputFormatter> kAmountInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text;
    final separators = RegExp(r'[.,]').allMatches(text).length;
    if (separators > 1) return oldValue;
    final dot = text.lastIndexOf('.');
    final comma = text.lastIndexOf(',');
    final sep = dot > comma ? dot : comma;
    if (sep >= 0 && text.length - sep - 1 > 2) return oldValue;
    return newValue;
  }),
];

// ponytail: Outfit/JetBrainsMono have no glyph for ₱ (U+20B1), so render
// the currency symbol with the platform default font (Roboto on Android,
// San Francisco on iOS) which has full currency coverage. The digits stay
// in the styled font.
TextSpan currencySpan(String? code, TextStyle? style) {
  return TextSpan(
    text: currencySymbol(code),
    style: (style ?? const TextStyle()).copyWith(
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Noto Sans', 'sans-serif'],
    ),
  );
}

/// Renders a minor-unit amount as inline spans with the sign BEFORE the
/// currency symbol: -50000 PHP -> "−" "₱" "500.00". Zero and positive
/// amounts get no sign span. Digits are formatted from the absolute value
/// so [formatNumber]'s own '-' never appears after the symbol.
List<TextSpan> moneySpans(int minor, String? currency, TextStyle? style) {
  final negative = minor < 0;
  final symbolStyle = (style ?? const TextStyle()).copyWith(
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['Noto Sans', 'sans-serif'],
  );
  return [
    if (negative) TextSpan(text: '\u2212', style: symbolStyle),
    currencySpan(currency, style),
    TextSpan(
      text: formatMinor(negative ? -minor : minor, currency),
      style: style,
    ),
  ];
}


