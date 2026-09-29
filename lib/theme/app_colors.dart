import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color surface;
  final Color fg;
  final Color muted;
  final Color border;
  final Color accent;
  final Color accentDim;
  final Color listBg;
  final Color tagBg;
  final Color tagFg;
  final Color sidebarBg;
  final Color sidebarFg;
  final Color sidebarMuted;
  final Color sidebarActive;
  final Color sidebarHover;
  final Color income;
  final Color destructive;
  /// Money going out, negative values, and over-budget status. Distinct from
  /// [destructive] (which is for destructive ACTIONS like delete) so a widget
  /// can never accidentally paint a brand surface in expense red.
  final Color expense;

  /// Budget at 80-100% of its limit. Amber, never red or green.
  final Color warning;
  final String monoFontFamily;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.fg,
    required this.muted,
    required this.border,
    required this.accent,
    required this.accentDim,
    required this.listBg,
    required this.tagBg,
    required this.tagFg,
    required this.sidebarBg,
    required this.sidebarFg,
    required this.sidebarMuted,
    required this.sidebarActive,
    required this.sidebarHover,
    required this.income,
    required this.destructive,
    required this.expense,
    required this.warning,
    required this.monoFontFamily,
  });

  /// Readable foreground for text/icons painted on [background].
  ///
  /// 0.1791 is the WCAG crossover where white and black text have equal
  /// contrast against a background: (L + 0.05)^2 == 1.05 * 0.05. The previous
  /// 0.30 threshold kept white text on backgrounds already too light for it,
  /// so light-accent palettes (nord, monochrome-dark, solarized) rendered
  /// CTAs below AA.
  static Color readableOn(Color background) =>
      background.computeLuminance() > 0.1791
      ? const Color(0xDE000000)
      : Colors.white;

  Color get onAccent => readableOn(accent);
  Color get onIncome => readableOn(income);
  Color get onDestructive => readableOn(destructive);

  Color get onExpense => readableOn(expense);
  Color get onWarning => readableOn(warning);

  /// Zero amounts, "no data", and non-money stat cards. Neutral by design:
  /// a zero balance is a fact, not an alarm.
  Color get neutral => muted;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? fg,
    Color? muted,
    Color? border,
    Color? accent,
    Color? accentDim,
    Color? listBg,
    Color? tagBg,
    Color? tagFg,
    Color? sidebarBg,
    Color? sidebarFg,
    Color? sidebarMuted,
    Color? sidebarActive,
    Color? sidebarHover,
    Color? income,
    Color? destructive,
    Color? expense,
    Color? warning,
    String? monoFontFamily,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      fg: fg ?? this.fg,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentDim: accentDim ?? this.accentDim,
      listBg: listBg ?? this.listBg,
      tagBg: tagBg ?? this.tagBg,
      tagFg: tagFg ?? this.tagFg,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      sidebarFg: sidebarFg ?? this.sidebarFg,
      sidebarMuted: sidebarMuted ?? this.sidebarMuted,
      sidebarActive: sidebarActive ?? this.sidebarActive,
      sidebarHover: sidebarHover ?? this.sidebarHover,
      income: income ?? this.income,
      destructive: destructive ?? this.destructive,
      expense: expense ?? this.expense,
      warning: warning ?? this.warning,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      listBg: Color.lerp(listBg, other.listBg, t)!,
      tagBg: Color.lerp(tagBg, other.tagBg, t)!,
      tagFg: Color.lerp(tagFg, other.tagFg, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      sidebarFg: Color.lerp(sidebarFg, other.sidebarFg, t)!,
      sidebarMuted: Color.lerp(sidebarMuted, other.sidebarMuted, t)!,
      sidebarActive: Color.lerp(sidebarActive, other.sidebarActive, t)!,
      sidebarHover: Color.lerp(sidebarHover, other.sidebarHover, t)!,
      income: Color.lerp(income, other.income, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
