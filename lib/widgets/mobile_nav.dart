import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// Mobile bottom navigation: icon-only dock — Home · Notes · [+ Create] ·
/// Finance · Tasks — everything inside the thumb's arc. Labels are exposed
/// to screen readers via Semantics; sighted users get the icons alone.
class MobileNav extends StatelessWidget {
  final String currentTab;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onCreate;

  const MobileNav({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
    required this.onCreate,
  });

  static const _tabs = [
    ('home', Icons.home_outlined, 'Home', 0),
    ('notes', Icons.article_outlined, 'Notes', 1),
    ('finance', Icons.account_balance_wallet_outlined, 'Finance', 3),
    ('tasks', Icons.check_circle_outline, 'Tasks', 4),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Padding(
        // The safe-area inset can be bogus in embedded/preview contexts
        // (hundreds of px), which would float the dock to the middle of
        // the screen — clamp it like the original bar did.
        padding: EdgeInsets.only(bottom: bottomInset.clamp(0.0, 50.0)),
        child: _buildBar(context),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    // The Scaffold bottomNavigationBar slot is bounded-loose in height, and
    // the alignment-centered button containers below would expand to fill
    // the whole screen — pin the bar to its intended 48px touch height.
    Widget tab(int index) {
      final (filter, icon, label, _) = _tabs[index];
      return _iconBtn(
        context,
        filter: filter,
        icon: icon,
        semanticsLabel: label,
      );
    }

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(child: tab(0)),
          Expanded(child: tab(1)),
          Expanded(child: _capture(context)),
          Expanded(child: tab(2)),
          Expanded(child: tab(3)),
        ],
      ),
    );
  }

  Widget _iconBtn(
    BuildContext context, {
    required String filter,
    required IconData icon,
    required String semanticsLabel,
  }) {
    final active = currentTab == filter;
    return Semantics(
      button: true,
      selected: active,
      label: semanticsLabel,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTabChanged(filter);
        },
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 24,
            color: active ? context.colors.accent : context.colors.muted,
          ),
        ),
      ),
    );
  }

  Widget _capture(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Create',
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onCreate();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
          alignment: Alignment.center,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.colors.accent.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              Icons.add,
              size: 26,
              color: context.colors.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}
