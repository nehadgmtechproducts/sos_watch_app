import 'package:flutter/material.dart';

import '../../responsive.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import '../home_screen.dart';

/// Screen 6 — Contacts Added Successfully.
class ContactsAddedScreen extends StatelessWidget {
  const ContactsAddedScreen({super.key});

  void _done(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PopScope(
        canPop: false, // finish via Done, don't go back to the add form
        child: CenterScroll(
          padding: EdgeInsets.all(watch ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Green success check.
              Container(
                width: watch ? 40 : 52,
                height: watch ? 40 : 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                ),
                child: Icon(Icons.check_rounded,
                    color: Colors.white, size: watch ? 26 : 32),
              ),
              const SizedBox(height: 12),
              const Text(
                'Contacts Added\nSuccessfully',
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: 6),
              const Text(
                'You can add / edit\ncontacts anytime',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 14),
              // Done button.
              Material(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppDimens.buttonRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _done(context),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    child: Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
