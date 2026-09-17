import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sos_emergency/screens/onboarding/enter_mobile_screen.dart';

import '../bloc/auth/auth_bloc.dart';
import '../bloc/contacts/contacts_bloc.dart';
import '../responsive.dart';
import '../services/profile_store.dart';
import 'home_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_styles.dart';

/// Branded first screen shown while the app starts.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_openHome());
  }

  Future<void> _openHome() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final isLoggedIn = await ProfileStore.instance.isLoggedIn();
    final accessToken = await ProfileStore.instance.accessToken();
    final hasCompletedProfile =
        await ProfileStore.instance.hasCompletedProfile();
    if (!mounted) return;
    if (accessToken != null) {
      final auth = context.read<AuthBloc>();
      auth.api.token = accessToken;
      auth.registerDevice(); // refresh this phone as a ring target
      context.read<ContactsBloc>().add(const ContactsStarted());
    }
    // Replace *this* route specifically, not whatever is on top. When the app
    // is opened by tapping an SOS notification, the alarm screen is pushed over
    // the splash within the first frame; pushReplacement acts on the topmost
    // route, so 3s later it swapped out the alarm screen — leaving the siren
    // ringing with no Stop button. This lands Home beneath the alarm instead.
    final splashRoute = ModalRoute.of(context);
    final next = MaterialPageRoute<void>(
      builder: (_) => isLoggedIn && hasCompletedProfile
          ? const HomeScreen()
          : const EnterMobileScreen(),
    );
    if (splashRoute != null && splashRoute.isActive) {
      Navigator.of(context).replace(oldRoute: splashRoute, newRoute: next);
    } else {
      Navigator.of(context).pushReplacement(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);
    final logoSize = watch ? 72.0 : 112.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      // CenterScroll centers when there's room and scrolls if not — no overflow.
      body: CenterScroll(
        padding: EdgeInsets.all(watch ? 10 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/sos_shield_logo.png',
              width: logoSize,
              height: logoSize,
            ),
            SizedBox(height: watch ? 8 : 10),
            const Text('SOS Emergency', style: AppTextStyles.title),
            const SizedBox(height: 3),
            const Text('Personal Safety', style: AppTextStyles.subtitle),
            SizedBox(height: watch ? 14 : 22),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
