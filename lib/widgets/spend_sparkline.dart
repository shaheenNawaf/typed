import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../utils/finance_utils.dart';
import 'count_up_amount.dart';

/// Last-14-days spending trend card: title row with the 14-day total, then one
/// bar per day (oldest -> newest, rightmost = today) drawn with a CustomPainter.
/// Flat colors only, per BRANDING.md. Consumers pass minor-unit day buckets.
///
/// [showDayLabels] prints the day of month under each bar and raises the default
/// bar-area height from 56 to 96. [averagePerDay] (minor units) draws a dashed
/// amber average line across the bars with an "avg ₱X" caption at its right end
/// and appends "· ₱X / day" to the header row. Average affordances render only
/// when there is bar data AND [averagePerDay] > 0.
class SpendSparkline extends StatelessWidget {
  /// Expense totals per day in minor units, oldest -> newest, length 14.
  final List<int> dailyTotals;
  final String currency;

  /// Bar-area height. Defaults to 56, or 96 when [showDayLabels] is set.
  final double? height;

  /// Day-of-month labels under each bar (desktop trend card).
  final bool showDayLabels;

  /// Average daily spend in minor units; line + captions only when > 0.
  final int? averagePerDay;

  const SpendSparkline({
    super.key,
    required this.dailyTotals,
    required this.currency,
    this.height,
    this.showDayLabels = false,
    this.averagePerDay,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasData = dailyTotals.length == 14 && dailyTotals.any((v) => v > 0);
    final showAvg = hasData && averagePerDay != null && averagePerDay! > 0;
    final total = hasData ? dailyTotals.fold(0, (a, b) => a + b) : 0;
    final totalStyle = TextStyle(
      fontSize: AppType.t11,
      fontFamily: c.monoFontFamily,
      fontWeight: FontWeight.w600,
      color: c.fg,
    );
    final barAreaHeight = height ?? (showDayLabels ? 96.0 : 56.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                'Last 14 days',
                style: TextStyle(
                  fontSize: AppType.t11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
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
              if (showAvg)
                Text(
                  ' · ${formatMinorAmount(averagePerDay!, currency)} / day',
                  style: TextStyle(
                    fontSize: AppType.t11,
                    fontFamily: c.monoFontFamily,
                    color: c.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: barAreaHeight,
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
                        avgMinor: showAvg ? averagePerDay : null,
                        avgLabel: showAvg
                            ? 'avg ${formatMinorAmount(averagePerDay!, currency)}'
                            : null,
                        avgColor: c.warning,
                        monoFamily: c.monoFontFamily,
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
          if (showDayLabels && hasData) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < dailyTotals.length; i++) ...[
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_labelDay(i).day}',
                        style: TextStyle(
                          fontSize: AppType.t10,
                          fontFamily: c.monoFontFamily,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ),
                  if (i < dailyTotals.length - 1) const SizedBox(width: 3),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The calendar date of bar [i] (0 = 13 days ago, 13 = today).
  DateTime _labelDay(int i) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: 13 - i));
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> totals;
  final Color barColor;
  final Color todayColor;
  final Color zeroColor;
  final double progress;
  final int? avgMinor;
  final String? avgLabel;
  final Color avgColor;
  final String monoFamily;

  _SparklinePainter({
    required this.totals,
    required this.barColor,
    required this.todayColor,
    required this.zeroColor,
    required this.progress,
    this.avgMinor,
    this.avgLabel,
    required this.avgColor,
    required this.monoFamily,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    // Prototype .bar i: bars never exceed 26px and center in their slot.
    const maxBarWidth = 26.0;
    final n = totals.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final slot = (size.width - gap * (n - 1)) / n;
    final barW = slot > maxBarWidth ? maxBarWidth : slot;
    final maxV = totals.fold(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < n; i++) {
      final v = totals[i];
      final left = i * (slot + gap) + (slot - barW) / 2;
      if (v <= 0) {
        // Prototype .bar.zero: a dashed 2px stub — an honest "nothing happened"
        // marker, not a solid block.
        final stubPaint = Paint()
          ..color = zeroColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        final y = size.height - 1;
        var dx = left;
        while (dx < left + barW) {
          final end = (dx + 3) > (left + barW) ? (left + barW) : (dx + 3);
          canvas.drawLine(Offset(dx, y), Offset(end, y), stubPaint);
          dx += 5;
        }
        continue;
      }
      final h =
          ((v / maxV * (size.height - 4)).clamp(2.0, size.height)) * progress;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, size.height - h, barW, h),
        topLeft: const Radius.circular(AppRadius.chip),
        topRight: const Radius.circular(AppRadius.chip),
      );
      final paint = Paint()
        ..color = i == n - 1 ? todayColor : barColor;
      canvas.drawRRect(rect, paint);
    }
    if (avgMinor != null && avgLabel != null && avgMinor! > 0) {
      final avgV = avgMinor!;
      final hAvg = (maxV <= 0 || avgV <= 0)
          ? 2.0
          : (avgV / maxV * (size.height - 4)).clamp(2.0, size.height);
      final y = size.height - hAvg;
      final linePaint = Paint()
        ..color = avgColor.withAlpha(178)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + 4).clamp(0.0, size.width), y),
          linePaint,
        );
        x += 7;
      }
      final caption = TextPainter(
        text: TextSpan(
          text: avgLabel,
          style: TextStyle(
            fontSize: AppType.t10,
            fontFamily: monoFamily,
            color: avgColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cy = (y - caption.height - 2).clamp(0.0, size.height - caption.height);
      caption.paint(canvas, Offset(size.width - caption.width, cy));
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.totals != totals ||
      oldDelegate.barColor != barColor ||
      oldDelegate.todayColor != todayColor ||
      oldDelegate.zeroColor != zeroColor ||
      oldDelegate.avgMinor != avgMinor ||
      oldDelegate.avgLabel != avgLabel ||
      oldDelegate.avgColor != avgColor ||
      oldDelegate.monoFamily != monoFamily;
}