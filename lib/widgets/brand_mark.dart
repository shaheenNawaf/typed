import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The Typed brand mark — a lowercase 't' with a red period beside it.
/// The crossbar and the period are in the accent color; the rest in fg.
class BrandMark extends StatelessWidget {
  final double size;
  final Color? fg;
  final Color? accent;

  const BrandMark({
    super.key,
    this.size = 18,
    this.fg,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fgc = fg ?? c.fg;
    final accc = accent ?? c.accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandMarkPainter(color: fgc, accentColor: accc),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  final Color color;
  final Color accentColor;

  _BrandMarkPainter({required this.color, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()..color = color;
    final accent = Paint()..color = accentColor;

    final crossbar = Rect.fromLTWH(
      w * 0.188, h * 0.344, w * 0.625, h * 0.109);
    final stem = Rect.fromLTWH(
      w * 0.422, h * 0.219, w * 0.156, h * 0.656);
    final foot = Rect.fromLTWH(
      w * 0.297, h * 0.766, w * 0.406, h * 0.109);
    final period = Rect.fromLTWH(
      w * 0.781, h * 0.750, w * 0.125, h * 0.125);

    canvas.drawRect(crossbar, accent);
    canvas.drawRect(stem, paint);
    canvas.drawRect(foot, paint);
    canvas.drawRect(period, accent);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) =>
      old.color != color || old.accentColor != accentColor;
}
