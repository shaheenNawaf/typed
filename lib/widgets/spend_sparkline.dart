import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import 'count_up_amount.dart';

/// Last-14-days spending trend card: title row with the 14-day total, then one
/// bar per day (oldest -> newest, rightmost = today) drawn with a CustomPainter.
/// Flat colors only, per BRANDING.md. Consumers pass minor-unit day buckets.
class SpendSparkline extends StatelessWidget {
  /// Expense totals per day in minor units, oldest -> newest, length 14.
  final List<int> dailyTotals;
  final String currency;
  final double height;

  const SpendSparkline({
    super.key,
    required this.dailyTotals,
    required this.currency,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasData = dailyTotals.length == 14 && dailyTotals.any((v) => v > 0);
    final total = hasData ? dailyTotals.fold(0, (a, b) => a + b) : 0;
    final totalStyle = TextStyle(
      fontSize: AppType.t11,
      fontFamily: c.monoFontFamily,
      fontWeight: FontWeight.w600,
      color: c.fg,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'LAST 14 DAYS',
                style: TextStyle(
                  fontSize: AppType.t10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.06,
                  color: c.muted,
                ),
              ),
              const Spacer(),
              if (hasData)
                CountUpAmount(
                  minor: total,
                  currency: currency,
                  style: totalStyle,
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: height,
            width: double.infinity,
            child: hasData
                ? TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: AppMotion.duration(context, AppMotion.slow),
                    curve: AppMotion.decelerate,
                    builder: (context, progress, _) => CustomPaint(
                      painter: _SparklinePainter(
                        totals: dailyTotals,
                        barColor: c.accent.withAlpha(110),
                        todayColor: c.accent,
                        zeroColor: c.border,
                        progress: progress,
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      'No spending in the last 14 days',
                      style: TextStyle(fontSize: AppType.t11, color: c.muted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> totals;
  final Color barColor;
  final Color todayColor;
  final Color zeroColor;
  final double progress;

  _SparklinePainter({
    required this.totals,
    required this.barColor,
    required this.todayColor,
    required this.zeroColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final n = totals.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final barW = (size.width - gap * (n - 1)) / n;
    final maxV = totals.fold(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < n; i++) {
      final v = totals[i];
      final h = ((maxV <= 0 || v <= 0)
              ? 2.0
              : (v / maxV * (size.height - 4)).clamp(2.0, size.height)) *
          progress;
      final left = i * (barW + gap);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, size.height - h, barW, h),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      final paint = Paint()
        ..color = v <= 0 ? zeroColor : (i == n - 1 ? todayColor : barColor);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.totals != totals ||
      oldDelegate.barColor != barColor ||
      oldDelegate.todayColor != todayColor ||
      oldDelegate.zeroColor != zeroColor;
}