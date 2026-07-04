import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/fonts.dart';
import '../theme/palettes.dart';
import '../theme/theme_controller.dart';

class SettingsSheet extends StatelessWidget {
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final Future<void> Function()? onExportFinance;
  final VoidCallback? onShowOnboarding;

  const SettingsSheet({
    super.key,
    required this.onExport,
    required this.onImport,
    this.onExportFinance,
    this.onShowOnboarding,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onExport,
    required Future<void> Function() onImport,
    Future<void> Function()? onExportFinance,
    VoidCallback? onShowOnboarding,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ListenableBuilder(
        listenable: ThemeController.instance!,
        builder: (ctx, _) => SettingsSheet(
          onExport: onExport,
          onImport: onImport,
          onExportFinance: onExportFinance,
          onShowOnboarding: onShowOnboarding,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.fg,
                      letterSpacing: 0.01,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _Option(
              icon: Icons.ios_share_outlined,
              label: 'Export notes (JSON)',
              onTap: () async {
                Navigator.pop(context);
                await onExport();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Text only — images are not included.',
                style: TextStyle(fontSize: 11, color: context.colors.muted),
              ),
            ),
            _Option(
              icon: Icons.file_download_outlined,
              label: 'Import notes (JSON)',
              onTap: () async {
                Navigator.pop(context);
                await onImport();
              },
            ),
            if (onExportFinance != null) ...[
              const SizedBox(height: 4),
              const Divider(height: 16, indent: 20, endIndent: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  'Finance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.fg,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
              _Option(
                icon: Icons.table_chart_outlined,
                label: 'Export finance (CSV)',
                onTap: () async {
                  Navigator.pop(context);
                  await onExportFinance?.call();
                },
              ),
            ],
            const SizedBox(height: 4),
            const Divider(height: 16, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Theme',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.fg,
                  letterSpacing: 0.04,
                ),
              ),
            ),
            if (controller != null) ...[
              ...kPalettes.map(
                (p) => _ThemeRow(
                  palette: p,
                  selected: controller.palette.id == p.id,
                  onTap: () => controller.setPalette(p.id),
                ),
              ),
              const SizedBox(height: 4),
              const Divider(height: 16, indent: 20, endIndent: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Brightness',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.fg,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
              _BrightnessRow(
                mode: ThemeMode.system,
                icon: Icons.brightness_auto_outlined,
                label: 'System',
                selected: controller.mode == ThemeMode.system,
                onTap: () => controller.setMode(ThemeMode.system),
              ),
              _BrightnessRow(
                mode: ThemeMode.light,
                icon: Icons.light_mode_outlined,
                label: 'Light',
                selected: controller.mode == ThemeMode.light,
                onTap: () => controller.setMode(ThemeMode.light),
              ),
              _BrightnessRow(
                mode: ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                label: 'Dark',
                selected: controller.mode == ThemeMode.dark,
                onTap: () => controller.setMode(ThemeMode.dark),
              ),
              const SizedBox(height: 4),
              const Divider(height: 16, indent: 20, endIndent: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Font',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.fg,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
              ...kFontOptions.map(
                (f) => _FontRow(
                  option: f,
                  selected: controller.fontId == f.id,
                  onTap: () => controller.setFont(f.id),
                ),
              ),
            ],
            if (onShowOnboarding != null) ...[
              const SizedBox(height: 4),
              const Divider(height: 16, indent: 20, endIndent: 20),
              _Option(
                icon: Icons.tips_and_updates_outlined,
                label: 'Show Welcome Note',
                onTap: () {
                  Navigator.pop(context);
                  onShowOnboarding?.call();
                },
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final ThemePalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeRow({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // ponytail: use the effective app brightness, not the OS brightness, so
    // the swatch preview matches what the user actually sees.
    final sample = Theme.of(context).brightness == Brightness.dark
        ? palette.dark
        : palette.light;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              palette.icon,
              size: 20,
              color: selected ? sample.accent : c.fg,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                palette.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: c.fg,
                ),
              ),
            ),
            Row(
              children: [
                _Swatch(color: sample.accent),
                const SizedBox(width: 4),
                _Swatch(color: sample.bg),
                const SizedBox(width: 4),
                _Swatch(color: sample.surface),
              ],
            ),
            const SizedBox(width: 8),
            if (selected)
              Icon(Icons.check, size: 18, color: c.accent)
            else
              const SizedBox(width: 18),
          ],
        ),
      ),
    );
  }
}

class _FontRow extends StatelessWidget {
  final FontOption option;
  final bool selected;
  final VoidCallback onTap;

  const _FontRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.text_fields,
              size: 20,
              color: selected ? c.accent : c.fg,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: c.fg,
                  fontFamily: option.uiFontFamily == 'System'
                      ? null
                      : option.uiFontFamily,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              Icon(Icons.check, size: 18, color: c.accent)
            else
              const SizedBox(width: 18),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  const _Swatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.colors.border),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Option({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.colors.fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: context.colors.fg),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

class _BrightnessRow extends StatelessWidget {
  final ThemeMode mode;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BrightnessRow({
    required this.mode,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? c.accent : c.fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: c.fg,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: c.accent)
            else
              const SizedBox(width: 18),
          ],
        ),
      ),
    );
  }
}
