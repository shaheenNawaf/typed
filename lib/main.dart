import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';
import 'theme/fonts.dart';
import 'theme/theme_controller.dart';
import 'utils/notifications.dart';

/// Typed design type scale:
///   Lora (display)  — note titles, empty state headers, markdown headings
///   DM Sans (UI)    — body, list items, labels, metadata
///   JetBrains Mono  — code, timestamps, word counts

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.create();
  await NotificationService.initialize();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final palette = controller.palette;
        final font = controller.font;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Typed',
          theme: _buildTheme(palette.light, Brightness.light, font),
          darkTheme: _buildTheme(palette.dark, Brightness.dark, font),
          themeMode: controller.mode,
          // Embedded hosts (preview panes, odd webview shells) can report
          // bogus safe-area insets larger than the window itself, which
          // pushes the whole UI off-screen. Sanitize once, app-wide.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            EdgeInsets clampInset(EdgeInsets e) => EdgeInsets.fromLTRB(
                  e.left.clamp(0.0, 60.0),
                  e.top.clamp(0.0, 60.0),
                  e.right.clamp(0.0, 60.0),
                  e.bottom.clamp(0.0, 60.0),
                );
            return MediaQuery(
              data: mq.copyWith(
                padding: clampInset(mq.padding),
                viewPadding: clampInset(mq.viewPadding),
                // Large system font scales blow out fixed-height chrome
                // (finance summary cards, dense rows). Clamp app-wide; 1.3
                // keeps accessibility headroom without breaking layouts.
                textScaler: mq.textScaler.clamp(
                  minScaleFactor: 1.0,
                  maxScaleFactor: 1.3,
                ),
              ),
              child: child!,
            );
          },
          // HomeScreen renders the same brand mark while loading; a
          // separate splash screen only added a fixed 1.5 s delay.
          home: const HomeScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(
    AppColors colors,
    Brightness brightness,
    FontOption font,
  ) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: colors.accent,
      scaffoldBackgroundColor: colors.bg,
    );
    final textTheme = _buildTextTheme(base.textTheme, colors, font);
    return base.copyWith(textTheme: textTheme, extensions: [colors]);
  }

  TextTheme _buildTextTheme(TextTheme base, AppColors colors, FontOption font) {
    if (!font.usesGoogleFonts) {
      return base.copyWith(
        displayLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: colors.fg,
          letterSpacing: -0.02,
        ),
        displayMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: colors.fg,
          letterSpacing: -0.015,
        ),
        displaySmall: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colors.fg,
          letterSpacing: -0.01,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colors.fg,
          height: 1.2,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.fg,
          height: 1.35,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.fg,
          height: 1.0,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: colors.fg,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: colors.fg,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: colors.muted,
          height: 1.3,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.fg,
          height: 1.0,
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.muted,
          letterSpacing: 0.08,
          height: 1.2,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: colors.muted,
          letterSpacing: 0.04,
          fontFamily: font.monoFontFamily,
        ),
      );
    }

    return GoogleFonts.dmSansTextTheme(base).copyWith(
      displayLarge: _gf(
        font.displayFontFamily ?? font.uiFontFamily,
        24,
        FontWeight.w700,
        colors.fg,
        letterSpacing: -0.02,
      ),
      displayMedium: _gf(
        font.uiFontFamily,
        20,
        FontWeight.w500,
        colors.fg,
        letterSpacing: -0.015,
      ),
      displaySmall: _gf(
        font.uiFontFamily,
        17,
        FontWeight.w600,
        colors.fg,
        letterSpacing: -0.01,
      ),
      titleLarge: _gf(
        font.displayFontFamily ?? font.uiFontFamily,
        22,
        FontWeight.w600,
        colors.fg,
        height: 1.2,
      ),
      titleMedium: _gf(
        font.uiFontFamily,
        16,
        FontWeight.w500,
        colors.fg,
        height: 1.35,
      ),
      titleSmall: _gf(
        font.uiFontFamily,
        14,
        FontWeight.w500,
        colors.fg,
        height: 1.0,
      ),
      bodyLarge: _gf(
        font.uiFontFamily,
        15,
        FontWeight.w400,
        colors.fg,
        height: 1.6,
      ),
      bodyMedium: _gf(font.uiFontFamily, 13, FontWeight.w400, colors.fg),
      bodySmall: _gf(
        font.uiFontFamily,
        12,
        FontWeight.w400,
        colors.muted,
        height: 1.3,
      ),
      labelLarge: _gf(
        font.uiFontFamily,
        14,
        FontWeight.w500,
        colors.fg,
        height: 1.0,
      ),
      labelMedium: _gf(
        font.uiFontFamily,
        11,
        FontWeight.w600,
        colors.muted,
        letterSpacing: 0.08,
        height: 1.2,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: colors.muted,
        letterSpacing: 0.04,
      ),
    );
  }

  TextStyle _gf(
    String family,
    double? size,
    FontWeight? weight,
    Color? color, {
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.getFont(
      family,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}
