import 'package:flutter/material.dart';

/// Central color palette for the whole app.
///
/// Every screen should reference colors from here (e.g. `AppColors.accent`)
/// instead of hard-coding hex values, so the theme is consistent and can be
/// changed in one place.
class AppColors {
  AppColors._();

  /// Screen background (near-black).
  static const Color background = Color(0xFF050507);

  /// Brand violet — buttons, icons, active states, links.
  static const Color accent = Color(0xFF6024cc);

  /// Input-field fill.
  static const Color field = Color(0xFF17171D);

  /// Input / divider borders.
  static const Color border = Color(0xFF33333D);

  /// Primary text on dark backgrounds.
  static const Color textPrimary = Colors.white;

  /// Secondary / hint text.
  static const Color subtitle = Color(0xFF9A9AA5);

  /// Inactive page-indicator dot.
  static const Color dotInactive = Color(0xFF3A3A44);

  /// Validation / error text.
  static const Color error = Color(0xFFFF5A5F);

  /// red color for logout
  static const Color red = Color(0xFFFF2D2D);
  /// Success (e.g. the "added successfully" check).
  static const Color success = Color(0xFF34C759);
}
