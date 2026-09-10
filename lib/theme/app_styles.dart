import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared text styles used across every screen (title & subtitle fonts).
/// Change once here to restyle the whole app.
class AppTextStyles {
  AppTextStyles._();

  /// Screen title (e.g. "Mobile Number", "Enter OTP").
  static const TextStyle title = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Secondary / helper text under a title.
  static const TextStyle subtitle = TextStyle(
    color: AppColors.subtitle,
    fontSize: 10,
    height: 1.3,
  );

  /// Field label shown above an input (e.g. "First Name").
  static const TextStyle label = TextStyle(
    color: AppColors.subtitle,
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );
}

/// Shared dimensions used across every screen (button sizing, etc.).
class AppDimens {
  AppDimens._();

  static const double buttonWidth = 72;
  static const double buttonHeight = 27;
  static const double buttonRadius = 14;
}
