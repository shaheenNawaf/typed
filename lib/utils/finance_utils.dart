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
  final fixed = value.toStringAsFixed(decimals);
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
  return buffer.toString();
}

String formatAmount(double amount, String? currency) {
  final decimals = currency == 'JPY' ? 0 : 2;
  return '${currencySymbol(currency)}${formatNumber(amount, decimals: decimals)}';
}

// ponytail: strict numeric input — digits plus at most one '.', no other
// characters (no letters, no symbols, no negative sign, no second dot,
// no leading dot). Applied to both the entry amount and the budget limit.
final List<TextInputFormatter> kAmountInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text;
    if (text.split('.').length > 2) return oldValue;
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


