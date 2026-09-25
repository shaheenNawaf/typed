import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../utils/finance_utils.dart';

/// A money amount that counts up from 0 on first build and re-animates
/// whenever [minor] changes (period/currency switches). Renders via
/// [moneySpans]: sign (U+2212 for negatives) before the currency symbol
/// (Outfit lacks the ₱ glyph), digits with [formatMinor] in [style].
/// Collapses to the final value instantly under
/// reduce-motion (AppMotion.duration -> Duration.zero).
class CountUpAmount extends StatelessWidget {
  /// Amount in integer minor units of [currency].
  final int minor;
  final String? currency;

  /// Style for the digits AND the base for the currency symbol span.
  final TextStyle style;

  const CountUpAmount({
    super.key,
    required this.minor,
    required this.currency,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: minor.toDouble()),
      duration: AppMotion.duration(context, AppMotion.page),
      curve: AppMotion.decelerate,
      builder: (context, value, _) => Text.rich(
        TextSpan(
          style: style,
          children: moneySpans(value.round(), currency, style),
        ),
      ),
    );
  }
}