import 'package:flutter/material.dart';

/// Motion tokens for the whole app: four durations and three easings.
///
/// Every animation should collapse to zero when the OS reduce-motion setting
/// is on — use [duration] instead of the raw tokens at call sites that have
/// a BuildContext.
class AppMotion {
  AppMotion._();

  /// Exits, hover states, pressed feedback.
  static const Duration fast = Duration(milliseconds: 120);

  /// Selection, hover lift, toggles.
  static const Duration base = Duration(milliseconds: 200);

  /// Panel reveal, view switch, sheets.
  static const Duration slow = Duration(milliseconds: 320);

  /// Mobile editor open/close, onboarding paging.
  static const Duration page = Duration(milliseconds: 450);

  /// Fast start, gentle landing — the default for pushes and reveals.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// For things coming in.
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// For things going out.
  static const Curve accelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// [base] (or any duration) collapsed to zero when the OS asks for
  /// reduced motion.
  static Duration duration(BuildContext context, Duration base) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : base;
}
