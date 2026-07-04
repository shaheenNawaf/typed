import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LongPressAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool destructive;

  const LongPressAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.destructive = false,
  });
}

class LongPressMenu {
  static Future<void> show(
    BuildContext context, {
    required List<LongPressAction> actions,
    Offset? tapPosition,
  }) async {
    final c = context.colors;
    final isMobile = MediaQuery.of(context).size.width < 1024;
    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        backgroundColor: context.colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ...actions.map((a) => InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  a.onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Icon(a.icon,
                          size: 20,
                          color: a.destructive
                              ? c.destructive
                              : (a.color ?? context.colors.fg)),
                      const SizedBox(width: 14),
                      Text(a.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: a.destructive
                                ? c.destructive
                                : (a.color ?? context.colors.fg),
                          )),
                    ],
                  ),
                ),
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    } else {
      final pos = tapPosition ?? const Offset(100, 100);
      final screenSize = MediaQuery.of(context).size;
      final clampedX = pos.dx.clamp(0.0, screenSize.width - 200);
      final clampedY = pos.dy.clamp(0.0, screenSize.height - 300);
      await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(clampedX, clampedY, clampedX + 1, clampedY + 1),
        items: actions
            .map((a) => PopupMenuItem(
                  onTap: () {
                    Future.microtask(() => a.onTap());
                  },
                  child: Row(
                    children: [
                      Icon(a.icon,
                          size: 18,
                          color: a.destructive
                              ? c.destructive
                              : (a.color ?? context.colors.fg)),
                      const SizedBox(width: 10),
                      Text(a.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: a.destructive
                                ? c.destructive
                              : (a.color ?? context.colors.fg),
                          )),
                    ],
                  ),
                ))
            .toList(),
      );
    }
  }
}
