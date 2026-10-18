import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A quiet single-choice row: plain words, the chosen one in ink on a soft
/// pill. Replaces the boxed segmented controls on the calm surfaces.
class QuietChoice extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, String> options;

  const QuietChoice({
    super.key,
    required this.value,
    required this.onChanged,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final e in options.entries)
          Semantics(
            button: true,
            selected: e.key == value,
            child: InkWell(
              onTap: () => onChanged(e.key),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.base),
                curve: AppMotion.decelerate,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: e.key == value
                      ? c.fg.withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: e.key == value
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: e.key == value ? c.fg : c.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
