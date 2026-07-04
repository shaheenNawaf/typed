import 'package:flutter/material.dart';
import 'app_colors.dart';

// ponytail: sidebar palette is identical across all themes
// (always dark, per design decision).
const _sidebarBg = Color(0xFF2D3035);
const _sidebarFg = Color(0xFFE0E1E3);
const _sidebarMuted = Color(0xFF92979D);
const _sidebarActive = Color(0xFF40454A);
const _sidebarHover = Color(0xFF383D42);

const _mono = 'JetBrains Mono';

class ThemePalette {
  final String id;
  final String name;
  final IconData icon;
  final AppColors light;
  final AppColors dark;

  const ThemePalette({
    required this.id,
    required this.name,
    required this.icon,
    required this.light,
    required this.dark,
  });
}

// -- Cream -------------------------------------------------------------------

const AppColors _creamLight = AppColors(
  bg: Color(0xFFF8F9FA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1A242E),
  muted: Color(0xFF6E7A85),
  border: Color(0xFFE5E8EB),
  accent: Color(0xFFCC4D3C),
  accentDim: Color(0x1FCC4D3C),
  listBg: Color(0xFFF2F3F5),
  tagBg: Color(0x1ACC4D3C),
  tagFg: Color(0xFFA03D2E),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF2D8659),
  destructive: Color(0xFFCC4D3C),
  monoFontFamily: _mono,
);

const AppColors _creamDark = AppColors(
  bg: Color(0xFF15171A),
  surface: Color(0xFF1C1F22),
  fg: Color(0xFFE8EAEC),
  muted: Color(0xFF8A929A),
  border: Color(0xFF2A2D30),
  accent: Color(0xFFE0634F),
  accentDim: Color(0x1FE0634F),
  listBg: Color(0xFF181B1E),
  tagBg: Color(0x1FE0634F),
  tagFg: Color(0xFFE0634F),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF3CA06B),
  destructive: Color(0xFFE0634F),
  monoFontFamily: _mono,
);

// -- Slate -------------------------------------------------------------------

const AppColors _slateLight = AppColors(
  bg: Color(0xFFF4F5F7),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1E2630),
  muted: Color(0xFF6B7682),
  border: Color(0xFFE1E4E8),
  accent: Color(0xFF3D5ACC),
  accentDim: Color(0x1F3D5ACC),
  listBg: Color(0xFFECEEF1),
  tagBg: Color(0x1F3D5ACC),
  tagFg: Color(0xFF2D45A0),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF3D7A5A),
  destructive: Color(0xFFCC4D4D),
  monoFontFamily: _mono,
);

const AppColors _slateDark = AppColors(
  bg: Color(0xFF14171C),
  surface: Color(0xFF1B1F25),
  fg: Color(0xFFE5E7EB),
  muted: Color(0xFF8990A0),
  border: Color(0xFF292D33),
  accent: Color(0xFF6985E0),
  accentDim: Color(0x1F6985E0),
  listBg: Color(0xFF181C22),
  tagBg: Color(0x1F6985E0),
  tagFg: Color(0xFF6985E0),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF4D9A6E),
  destructive: Color(0xFFE06868),
  monoFontFamily: _mono,
);

// -- Forest ------------------------------------------------------------------

const AppColors _forestLight = AppColors(
  bg: Color(0xFFF5F7F4),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1C2A1F),
  muted: Color(0xFF6B7A6F),
  border: Color(0xFFE0E5E0),
  accent: Color(0xFF3C8C5A),
  accentDim: Color(0x1F3C8C5A),
  listBg: Color(0xFFEEF1ED),
  tagBg: Color(0x1F3C8C5A),
  tagFg: Color(0xFF2D6E45),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF3C8C5A),
  destructive: Color(0xFFCC4444),
  monoFontFamily: _mono,
);

const AppColors _forestDark = AppColors(
  bg: Color(0xFF131815),
  surface: Color(0xFF1A1F1C),
  fg: Color(0xFFE5EBE6),
  muted: Color(0xFF88978B),
  border: Color(0xFF282D2A),
  accent: Color(0xFF5DAE7B),
  accentDim: Color(0x1F5DAE7B),
  listBg: Color(0xFF171B19),
  tagBg: Color(0x1F5DAE7B),
  tagFg: Color(0xFF5DAE7B),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF5DAE7B),
  destructive: Color(0xFFE05555),
  monoFontFamily: _mono,
);

// -- Solarized ---------------------------------------------------------------

const AppColors _solarizedLight = AppColors(
  bg: Color(0xFFF5F0E4),
  surface: Color(0xFFFBF5E7),
  fg: Color(0xFF1F2A2B),
  muted: Color(0xFF6B7670),
  border: Color(0xFFE1D9C5),
  accent: Color(0xFFB58900),
  accentDim: Color(0x1FB58900),
  listBg: Color(0xFFEDE7D7),
  tagBg: Color(0x1FB58900),
  tagFg: Color(0xFF8C6D00),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF859900),
  destructive: Color(0xFFDC322F),
  monoFontFamily: _mono,
);

const AppColors _solarizedDark = AppColors(
  bg: Color(0xFF001B26),
  surface: Color(0xFF002B36),
  fg: Color(0xFFDDD6C1),
  muted: Color(0xFF7B7B7B),
  border: Color(0xFF083D4A),
  accent: Color(0xFFB58900),
  accentDim: Color(0x1FB58900),
  listBg: Color(0xFF00212B),
  tagBg: Color(0x1FB58900),
  tagFg: Color(0xFFB58900),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFFB5C900),
  destructive: Color(0xFFDC322F),
  monoFontFamily: _mono,
);

// -- Midnight ----------------------------------------------------------------

const AppColors _midnightLight = AppColors(
  bg: Color(0xFFF4F6FA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1A1F2E),
  muted: Color(0xFF6B7280),
  border: Color(0xFFE2E6F0),
  accent: Color(0xFF4361E2),
  accentDim: Color(0x1F4361E2),
  listBg: Color(0xFFEDF0F5),
  tagBg: Color(0x1F4361E2),
  tagFg: Color(0xFF3451B5),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF2D8659),
  destructive: Color(0xFFE24D4D),
  monoFontFamily: _mono,
);

const AppColors _midnightDark = AppColors(
  bg: Color(0xFF0F111A),
  surface: Color(0xFF161A27),
  fg: Color(0xFFE4E6ED),
  muted: Color(0xFF7C8394),
  border: Color(0xFF252A39),
  accent: Color(0xFF6B83F0),
  accentDim: Color(0x1F6B83F0),
  listBg: Color(0xFF131724),
  tagBg: Color(0x1F6B83F0),
  tagFg: Color(0xFF6B83F0),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF4DAA73),
  destructive: Color(0xFFF05A5A),
  monoFontFamily: _mono,
);

// -- Rose --------------------------------------------------------------------

const AppColors _roseLight = AppColors(
  bg: Color(0xFFFDF8F6),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF2D1F1C),
  muted: Color(0xFF8A7A75),
  border: Color(0xFFEDE0DC),
  accent: Color(0xFFD4536A),
  accentDim: Color(0x1FD4536A),
  listBg: Color(0xFFF7F0EC),
  tagBg: Color(0x1FD4536A),
  tagFg: Color(0xFFB04257),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF2D8659),
  destructive: Color(0xFFD4536A),
  monoFontFamily: _mono,
);

const AppColors _roseDark = AppColors(
  bg: Color(0xFF1C1412),
  surface: Color(0xFF241B18),
  fg: Color(0xFFEDE0DC),
  muted: Color(0xFF9A8A85),
  border: Color(0xFF342824),
  accent: Color(0xFFE87A8F),
  accentDim: Color(0x1FE87A8F),
  listBg: Color(0xFF201714),
  tagBg: Color(0x1FE87A8F),
  tagFg: Color(0xFFE87A8F),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF5CAF7A),
  destructive: Color(0xFFE87A8F),
  monoFontFamily: _mono,
);

// -- Nord --------------------------------------------------------------------

const AppColors _nordLight = AppColors(
  bg: Color(0xFFF5F7FA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF2E3440),
  muted: Color(0xFF7B88A0),
  border: Color(0xFFD8DEE9),
  accent: Color(0xFF5E81AC),
  accentDim: Color(0x1F5E81AC),
  listBg: Color(0xFFECEFF4),
  tagBg: Color(0x1F5E81AC),
  tagFg: Color(0xFF4C6A8C),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF4C9A6E),
  destructive: Color(0xFFBF616A),
  monoFontFamily: _mono,
);

const AppColors _nordDark = AppColors(
  bg: Color(0xFF171C26),
  surface: Color(0xFF1E2533),
  fg: Color(0xFFD8DEE9),
  muted: Color(0xFF7B88A0),
  border: Color(0xFF2E3440),
  accent: Color(0xFF88C0D0),
  accentDim: Color(0x1F88C0D0),
  listBg: Color(0xFF1A212E),
  tagBg: Color(0x1F88C0D0),
  tagFg: Color(0xFF88C0D0),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFFA3BE8C),
  destructive: Color(0xFFBF616A),
  monoFontFamily: _mono,
);

// -- Monochrome --------------------------------------------------------------

const AppColors _monochromeLight = AppColors(
  bg: Color(0xFFFAFAFA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1A1A1A),
  muted: Color(0xFF8A8A8A),
  border: Color(0xFFE5E5E5),
  accent: Color(0xFF404040),
  accentDim: Color(0x1F404040),
  listBg: Color(0xFFF0F0F0),
  tagBg: Color(0x1F404040),
  tagFg: Color(0xFF404040),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF404040),
  destructive: Color(0xFF8A8A8A),
  monoFontFamily: _mono,
);

const AppColors _monochromeDark = AppColors(
  bg: Color(0xFF121212),
  surface: Color(0xFF1A1A1A),
  fg: Color(0xFFE0E0E0),
  muted: Color(0xFF808080),
  border: Color(0xFF2A2A2A),
  accent: Color(0xFFB0B0B0),
  accentDim: Color(0x1FB0B0B0),
  listBg: Color(0xFF161616),
  tagBg: Color(0x1FB0B0B0),
  tagFg: Color(0xFFB0B0B0),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFFB0B0B0),
  destructive: Color(0xFF808080),
  monoFontFamily: _mono,
);

// -- Palette list ------------------------------------------------------------

const List<ThemePalette> kPalettes = [
  ThemePalette(id: 'cream', name: 'Cream', icon: Icons.coffee_outlined, light: _creamLight, dark: _creamDark),
  ThemePalette(id: 'slate', name: 'Slate', icon: Icons.layers_outlined, light: _slateLight, dark: _slateDark),
  ThemePalette(id: 'forest', name: 'Forest', icon: Icons.park_outlined, light: _forestLight, dark: _forestDark),
  ThemePalette(id: 'solarized', name: 'Solarized', icon: Icons.wb_sunny_outlined, light: _solarizedLight, dark: _solarizedDark),
  ThemePalette(id: 'midnight', name: 'Midnight', icon: Icons.nightlight_outlined, light: _midnightLight, dark: _midnightDark),
  ThemePalette(id: 'rose', name: 'Rose', icon: Icons.spa_outlined, light: _roseLight, dark: _roseDark),
  ThemePalette(id: 'nord', name: 'Nord', icon: Icons.ac_unit_outlined, light: _nordLight, dark: _nordDark),
  ThemePalette(id: 'mono', name: 'Monochrome', icon: Icons.tonality_outlined, light: _monochromeLight, dark: _monochromeDark),
];

ThemePalette paletteById(String id) {
  return kPalettes.firstWhere(
    (p) => p.id == id,
    orElse: () => kPalettes.first,
  );
}
