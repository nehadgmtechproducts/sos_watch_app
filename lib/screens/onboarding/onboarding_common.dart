import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';

/// Shared widgets/styling for the round-smartwatch onboarding flow.
/// Colors come from [AppColors] (see lib/theme/app_colors.dart).
/// (UI only — state management with BLoC is wired in once the APIs are ready.)

/// Violet rounded-rectangle action button (the check at the bottom of a
/// screen), matching the design mockup.
class RoundedActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final double width;
  final double height;
  final double radius;
  const RoundedActionButton({
    super.key,
    required this.onTap,
    this.icon = Icons.check,
    this.width = AppDimens.buttonWidth,
    this.height = AppDimens.buttonHeight,
    this.radius = AppDimens.buttonRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: AppColors.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkResponse(
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: AppColors.textPrimary, size: height * 0.55),
          ),
        ),
      ),
    );
  }
}

/// The page-position dots shown near the bottom of each onboarding screen.
class PageDots extends StatelessWidget {
  final int count;
  final int index;
  const PageDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: active ? 7 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.dotInactive,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

/// A rounded dark input field styled for the watch onboarding screens.
InputDecoration onboardFieldDecoration({
  String? hint,
  String? prefixText,
  String? errorText,
}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.subtitle, fontSize: 13),
      prefixText: prefixText,
      prefixStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      errorText: errorText,
      errorStyle: const TextStyle(color: AppColors.error, fontSize: 9),
      errorMaxLines: 2,
      isDense: true,
      filled: true,
      fillColor: AppColors.field,
      // vertical 7.5 (was 10) → ~5dp shorter field.
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
