import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MobileNav extends StatelessWidget {
  final String currentTab;
  final ValueChanged<String> onTabChanged;

  const MobileNav({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  static const _tabs = [
    ('home', Icons.home_outlined, 'Home'),
    ('notes', Icons.article_outlined, 'Notes'),
    ('finance', Icons.account_balance_wallet_outlined, 'Finance'),
    ('tasks', Icons.check_circle_outline, 'Tasks'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      padding: EdgeInsets.fromLTRB(0, 6, 0, (8 + bottomInset).clamp(16.0, 50.0)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _tabs.map((t) {
          return _navBtn(
            context,
            icon: t.$2,
            label: t.$3,
            active: currentTab == t.$1,
            onTap: () => onTabChanged(t.$1),
          );
        }).toList(),
      ),
    );
  }

  Widget _navBtn(
      BuildContext context, {
      required IconData icon,
      required String label,
      required bool active,
      required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24,
                color: active ? context.colors.accent : context.colors.muted),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(
                fontSize: 11, letterSpacing: 0.03,
                color: active ? context.colors.accent : context.colors.muted,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
