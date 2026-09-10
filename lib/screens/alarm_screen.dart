import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/alarm/alarm_bloc.dart';
import '../responsive.dart';
import '../theme/app_colors.dart';
import '../theme/app_styles.dart';

/// Received SOS alert with a prominent control to silence the alarm.
class AlarmScreen extends StatelessWidget {
  static const routeName = '/alarm';
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);
    final shortest = MediaQuery.of(context).size.shortestSide;
    final iconSize = (shortest * 0.22).clamp(40.0, 88.0);

    return PopScope(
      canPop: false, // Stop alarm dismisses the route via AlarmNavigator.
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: EdgeInsets.all(watch ? 16 : 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(watch ? 12 : 24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.red.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.15),
                        blurRadius: watch ? 24 : 48,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    size: iconSize,
                    color: AppColors.red,
                  ),
                ),
                SizedBox(height: watch ? 12 : 24),
                Text(
                  'Emergency alert',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title.copyWith(
                    fontSize: watch ? 18 : 28,
                  ),
                ),
                SizedBox(height: watch ? 6 : 12),
                BlocBuilder<AlarmBloc, AlarmState>(
                  buildWhen: (p, c) => p.fromName != c.fromName,
                  builder: (context, state) => Text(
                    '${state.fromName} needs help.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle.copyWith(
                      fontSize: watch ? 12 : 16,
                    ),
                  ),
                ),
                SizedBox(height: watch ? 18 : 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.symmetric(
                        horizontal: watch ? 12 : 24,
                        vertical: watch ? 12 : 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimens.buttonRadius,
                        ),
                      ),
                    ),
                    onPressed: () =>
                        context.read<AlarmBloc>().add(const AlarmDismissed()),
                    icon: const Icon(Icons.volume_off_rounded, size: 22),
                    label: Text(
                      'Stop alarm',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: watch ? 14 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: watch ? 8 : 12),
                Text(
                  'Silences the sound and vibration on this device.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.subtitle.copyWith(
                    fontSize: watch ? 10 : 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
