import 'package:flutter/material.dart';
import 'app_colors.dart';

// ponytail: sidebar palette is identical across all themes
// (always dark, per design decision).
const _sidebarBg = Color(0xFF2D3035);
const _sidebarFg = Color(0xFFE0E1E3);
const _sidebarMuted = Color(0xFF92979D);
const _sidebarActive = Color(0xFF40454A);
const _sidebarHover = Color(0xFF383D42);

// ponytail: budget-warning amber is palette-independent — it must read as
// "caution" identically in every theme, and no palette owns that hue.
const _warningLight = Color(0xFF9A5D00);
const _warningDark = Color(0xFFE8B451);

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
  muted: Color(0xFF6C7883),
  border: Color(0xFFE5E8EB),
  accent: Color(0xFF5B5BD6),
  accentDim: Color(0x1F5B5BD6),
  listBg: Color(0xFFF2F3F5),
  tagBg: Color(0x145C666E),
  tagFg: Color(0xFF5C666E),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF2D8659),
  destructive: Color(0xFFCC4C3B),
  expense: Color(0xFFCC4C3B),
  warning: _warningLight,
  monoFontFamily: _mono,
);

const AppColors _creamDark = AppColors(
  bg: Color(0xFF15171A),
  surface: Color(0xFF1C1F22),
  fg: Color(0xFFE8EAEC),
  muted: Color(0xFF8A929A),
  border: Color(0xFF2A2D30),
  accent: Color(0xFF7C7CE8),
  accentDim: Color(0x1F7C7CE8),
  listBg: Color(0xFF181B1E),
  tagBg: Color(0x14A7AEB6),
  tagFg: Color(0xFFA7AEB6),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF3CA06B),
  destructive: Color(0xFFE0634F),
  expense: Color(0xFFE0634F),
  warning: _warningDark,
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
  tagBg: Color(0x1459626D),
  tagFg: Color(0xFF59626D),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF3D7A5A),
  destructive: Color(0xFFCB4B4B),
  expense: Color(0xFFCB4B4B),
  warning: _warningLight,
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
  tagBg: Color(0x14A3AAB8),
  tagFg: Color(0xFFA3AAB8),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF4D9A6E),
  destructive: Color(0xFFE06868),
  expense: Color(0xFFE06868),
  warning: _warningDark,
  monoFontFamily: _mono,
);

// -- Forest ------------------------------------------------------------------

const AppColors _forestLight = AppColors(
  bg: Color(0xFFF5F7F4),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1C2A1F),
  muted: Color(0xFF6B7A6F),
  border: Color(0xFFE0E5E0),
  accent: Color(0xFF2C7A7B),
  accentDim: Color(0x1F2C7A7B),
  listBg: Color(0xFFEEF1ED),
  tagBg: Color(0x145B665E),
  tagFg: Color(0xFF5B665E),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF398555),
  destructive: Color(0xFFCC4444),
  expense: Color(0xFFCC4444),
  warning: _warningLight,
  monoFontFamily: _mono,
);

const AppColors _forestDark = AppColors(
  bg: Color(0xFF131815),
  surface: Color(0xFF1A1F1C),
  fg: Color(0xFFE5EBE6),
  muted: Color(0xFF88978B),
  border: Color(0xFF282D2A),
  accent: Color(0xFF4FA8A0),
  accentDim: Color(0x1F4FA8A0),
  listBg: Color(0xFF171B19),
  tagBg: Color(0x14A5B0A8),
  tagFg: Color(0xFFA5B0A8),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF5DAE7B),
  destructive: Color(0xFFE05757),
  expense: Color(0xFFE05757),
  warning: _warningDark,
  monoFontFamily: _mono,
);

// -- Solarized ---------------------------------------------------------------

const AppColors _solarizedLight = AppColors(
  bg: Color(0xFFF5F0E4),
  surface: Color(0xFFFBF5E7),
  fg: Color(0xFF1F2A2B),
  muted: Color(0xFF69736D),
  border: Color(0xFFE1D9C5),
  accent: Color(0xFF8D6B00),
  accentDim: Color(0x1F8D6B00),
  listBg: Color(0xFFEDE7D7),
  tagBg: Color(0x146B6252),
  tagFg: Color(0xFF6B6252),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF687800),
  destructive: Color(0xFFD92824),
  expense: Color(0xFFD92824),
  warning: _warningLight,
  monoFontFamily: _mono,
);

const AppColors _solarizedDark = AppColors(
  bg: Color(0xFF001B26),
  surface: Color(0xFF002B36),
  fg: Color(0xFFDDD6C1),
  muted: Color(0xFF8D8D8D),
  border: Color(0xFF083D4A),
  accent: Color(0xFFB58900),
  accentDim: Color(0x1FB58900),
  listBg: Color(0xFF00212B),
  tagBg: Color(0x14B3A98F),
  tagFg: Color(0xFFB3A98F),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFFB5C900),
  destructive: Color(0xFFE56562),
  expense: Color(0xFFE56562),
  warning: _warningDark,
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
  tagBg: Color(0x145B6270),
  tagFg: Color(0xFF5B6270),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF2D8659),
  destructive: Color(0xFFDE3535),
  expense: Color(0xFFDE3535),
  warning: _warningLight,
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
  tagBg: Color(0x14A5ABBB),
  tagFg: Color(0xFFA5ABBB),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF4DAA73),
  destructive: Color(0xFFF05A5A),
  expense: Color(0xFFF05A5A),
  warning: _warningDark,
  monoFontFamily: _mono,
);

// -- Rose --------------------------------------------------------------------

const AppColors _roseLight = AppColors(
  bg: Color(0xFFFDF8F6),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF2D1F1C),
  muted: Color(0xFF82736F),
  border: Color(0xFFEDE0DC),
  accent: Color(0xFFC54488),
  accentDim: Color(0x1FC54488),
  listBg: Color(0xFFF7F0EC),
  tagBg: Color(0x146E5C63),
  tagFg: Color(0xFF6E5C63),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF2D8659),
  destructive: Color(0xFFD04343),
  expense: Color(0xFFD04343),
  warning: _warningLight,
  monoFontFamily: _mono,
);

const AppColors _roseDark = AppColors(
  bg: Color(0xFF1C1412),
  surface: Color(0xFF241B18),
  fg: Color(0xFFEDE0DC),
  muted: Color(0xFF9A8A85),
  border: Color(0xFF342824),
  accent: Color(0xFFE07FB0),
  accentDim: Color(0x1FE07FB0),
  listBg: Color(0xFF201714),
  tagBg: Color(0x14B6A2A8),
  tagFg: Color(0xFFB6A2A8),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF5CAF7A),
  destructive: Color(0xFFE87A7A),
  expense: Color(0xFFE87A7A),
  warning: _warningDark,
  monoFontFamily: _mono,
);

// -- Nord --------------------------------------------------------------------

const AppColors _nordLight = AppColors(
  bg: Color(0xFFF5F7FA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF2E3440),
  muted: Color(0xFF697792),
  border: Color(0xFFD8DEE9),
  accent: Color(0xFF5477A3),
  accentDim: Color(0x1F5477A3),
  listBg: Color(0xFFECEFF4),
  tagBg: Color(0x145F6875),
  tagFg: Color(0xFF5F6875),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFF41835E),
  destructive: Color(0xFFBB5761),
  expense: Color(0xFFBB5761),
  warning: _warningLight,
  monoFontFamily: _mono,
);

const AppColors _nordDark = AppColors(
  bg: Color(0xFF171C26),
  surface: Color(0xFF1E2533),
  fg: Color(0xFFD8DEE9),
  muted: Color(0xFF7F8CA3),
  border: Color(0xFF2E3440),
  accent: Color(0xFF88C0D0),
  accentDim: Color(0x1F88C0D0),
  listBg: Color(0xFF1A212E),
  tagBg: Color(0x14A3ADBD),
  tagFg: Color(0xFFA3ADBD),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFFA3BE8C),
  destructive: Color(0xFFC7747C),
  expense: Color(0xFFC7747C),
  warning: _warningDark,
  monoFontFamily: _mono,
);

// -- Monochrome --------------------------------------------------------------

const AppColors _monochromeLight = AppColors(
  bg: Color(0xFFFAFAFA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF1A1A1A),
  muted: Color(0xFF767676),
  border: Color(0xFFE5E5E5),
  accent: Color(0xFF404040),
  accentDim: Color(0x1F404040),
  listBg: Color(0xFFF0F0F0),
  tagBg: Color(0x145A5A5A),
  tagFg: Color(0xFF5A5A5A),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  // income == accent and expense == muted made finance semantics invisible;
  // warm-neutral expense keeps the monochrome mood while staying legible.
  income: Color(0xFF1A1A1A),
  destructive: Color(0xFF8C554C),
  expense: Color(0xFF8C554C),
  warning: _warningLight,
  monoFontFamily: _mono,
);

const AppColors _monochromeDark = AppColors(
  bg: Color(0xFF121212),
  surface: Color(0xFF1A1A1A),
  fg: Color(0xFFE0E0E0),
  muted: Color(0xFF828282),
  border: Color(0xFF2A2A2A),
  accent: Color(0xFFB0B0B0),
  accentDim: Color(0x1FB0B0B0),
  listBg: Color(0xFF161616),
  tagBg: Color(0x14A8A8A8),
  tagFg: Color(0xFFA8A8A8),
  sidebarBg: _sidebarBg,
  sidebarFg: _sidebarFg,
  sidebarMuted: _sidebarMuted,
  sidebarActive: _sidebarActive,
  sidebarHover: _sidebarHover,
  income: Color(0xFFE0E0E0),
  destructive: Color(0xFFC98F82),
  expense: Color(0xFFC98F82),
  warning: _warningDark,
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
