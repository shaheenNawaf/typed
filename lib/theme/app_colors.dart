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
    required this.monoFontFamily,
  });

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
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
