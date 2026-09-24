/// Layout tokens: the 8 px grid (with a 6 px half-step for dense rows),
/// the three radii, and the type scale. Ad-hoc values in widgets map onto
/// these instead of inventing new ones.
class AppSpacing {
  AppSpacing._();
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
}

class AppRadius {
  AppRadius._();
  /// Chips, tags, small controls.
  static const double chip = 6;

  /// Cards, list rows, buttons.
  static const double card = 10;

  /// Sheets, panels, dialogs, the command palette.
  static const double panel = 14;
}

class AppType {
  AppType._();
  static const double t10 = 10;
  static const double t11 = 11;
  static const double t12 = 12;
  static const double t13_5 = 13.5;
  static const double t15 = 15;
  static const double t22 = 22;
  static const double t28 = 28;
}
