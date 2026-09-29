import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/theme/palettes.dart';

double _luminance(Color c) {
  double channel(double s) {
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Composites an alpha-bearing foreground over an opaque background so the
/// measured contrast matches what is actually rendered. `onAccent` is
/// Color(0xDE000000) — 87% opaque black — and measuring it as pure black
/// overstates its contrast.
Color _composite(Color fg, Color bg) {
  final a = fg.a; // 0.0-1.0
  return Color.from(
    alpha: 1.0,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double _hueDistance(Color a, Color b) {
  final ha = HSLColor.fromColor(a).hue;
  final hb = HSLColor.fromColor(b).hue;
  final d = (ha - hb).abs() % 360.0;
  return d > 180 ? 360 - d : d;
}

void main() {
  for (final palette in kPalettes) {
    for (final mode in ['light', 'dark']) {
      final c = mode == 'light' ? palette.light : palette.dark;
      final label = '${palette.id}.$mode';

      test('$label semantic tokens meet WCAG AA on surface', () {
        void aa(String token, Color fg) {
          final ratio = _contrast(fg, c.surface);
          expect(
            ratio >= 4.5,
            isTrue,
            reason: '$label $token vs surface = ${ratio.toStringAsFixed(2)} (< 4.5)',
          );
        }

        aa('accent', c.accent);
        aa('expense', c.expense);
        aa('income', c.income);
        aa('warning', c.warning);
        aa('tagFg', c.tagFg);
        aa('muted', c.muted);

        final onAccentRatio = _contrast(_composite(c.onAccent, c.accent), c.accent);
        expect(
          onAccentRatio >= 4.5,
          isTrue,
          reason: '$label onAccent vs accent = ${onAccentRatio.toStringAsFixed(2)} (< 4.5)',
        );

        expect(c.accent, isNot(c.destructive), reason: '$label accent == destructive');
        expect(c.accent, isNot(c.expense), reason: '$label accent == expense');
        expect(c.accent, isNot(c.income), reason: '$label accent == income');
        expect(c.expense, c.destructive, reason: '$label expense != destructive');

        final expenseSat = HSLColor.fromColor(c.expense).saturation;
        final incomeSat = HSLColor.fromColor(c.income).saturation;
        if (expenseSat >= 0.15 && incomeSat >= 0.15) {
          final hue = _hueDistance(c.expense, c.income);
          expect(
            hue >= 60,
            isTrue,
            reason: '$label expense vs income hue = ${hue.toStringAsFixed(1)} (< 60)',
          );
        } else {
          expect(c.expense, isNot(c.income), reason: '$label expense == income');
        }

        final accentSat = HSLColor.fromColor(c.accent).saturation;
        if (accentSat >= 0.15 && expenseSat >= 0.15) {
          final hue = _hueDistance(c.accent, c.expense);
          expect(
            hue >= 30,
            isTrue,
            reason: '$label accent vs expense hue = ${hue.toStringAsFixed(1)} (< 30)',
          );
        }
      });
    }
  }

  test('default palette accent is not the expense red', () {
    final cream = paletteById('cream');
    for (final c in [cream.light, cream.dark]) {
      expect(c.accent, isNot(c.destructive));
      expect(c.accent, isNot(c.expense));
      expect(c.tagFg, isNot(c.accent));
    }
  });
}