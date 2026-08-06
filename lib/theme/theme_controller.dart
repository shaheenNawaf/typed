import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fonts.dart';
import 'palettes.dart';

class ThemeController extends ChangeNotifier {
  static const _paletteKey = 'theme_palette_v1';
  static const _modeKey = 'theme_mode_v1';
  static const _fontKey = 'theme_font_v1';

  // ponytail: static instance so widgets can access without prop-drilling.
  // Set once in main() before runApp.
  static ThemeController? instance;

  ThemePalette _palette;
  ThemeMode _mode;
  String _fontId;

  ThemeController._({
    required ThemePalette palette,
    required ThemeMode mode,
    required String fontId,
  }) : _palette = palette,
       _mode = mode,
       _fontId = fontId;

  ThemePalette get palette => _palette;
  ThemeMode get mode => _mode;
  String get fontId => _fontId;
  FontOption get font => fontOptionById(_fontId);

  static Future<ThemeController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final paletteId = prefs.getString(_paletteKey);
    final modeStr = prefs.getString(_modeKey);
    final fontId = prefs.getString(_fontKey);
    final c = ThemeController._(
      palette: paletteId != null ? paletteById(paletteId) : kPalettes.first,
      mode: _modeFromString(modeStr),
      fontId: fontId ?? 'dm-sans',
    );
    instance = c;
    return c;
  }

  /// Parses a stored mode string, falling back to [ThemeMode.system] when the
  /// value is missing or not a valid [ThemeMode].
  static ThemeMode _modeFromString(String? raw) {
    if (raw == null) return ThemeMode.system;
    for (final mode in ThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return ThemeMode.system;
  }

  Future<void> setPalette(String id) async {
    if (_palette.id == id) return;
    _palette = paletteById(id);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, id);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  Future<void> setFont(String id) async {
    if (_fontId == id) return;
    _fontId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, id);
  }
}
