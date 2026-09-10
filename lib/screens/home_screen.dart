import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:home_widget/home_widget.dart';

import '../bloc/sos/sos_bloc.dart';
import '../theme/app_colors.dart';
import '../services/notification_service.dart';
import 'contacts/contacts_list_screen.dart';
import 'onboarding/emergency_contacts_screen.dart';
import 'profile/profile_screens.dart';

/// Brand red for the SOS button and its radial glow.
const Color _kSosRed = Color(0xFFE53935);

/// Dashboard (main screen): a big "Press & Hold" SOS button with a red glow,
/// and a speed-dial FAB for Show Contacts / Add Contact. Matches the design.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _fabOpen = false;
  StreamSubscription<Uri?>? _homeWidgetClickSubscription;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermissions();
    _listenForHomeWidgetLaunches();
  }

  void _listenForHomeWidgetLaunches() {
    // The home-screen shortcut flow is Android-only. On iOS, home_widget needs a
    // WidgetKit extension + App Group before these APIs are used.
    if (defaultTargetPlatform != TargetPlatform.android) return;

    unawaited(
      HomeWidget.initiallyLaunchedFromHomeWidget()
          .then(_maybeFireFromWidget)
          .catchError((_) {}),
    );
    _homeWidgetClickSubscription = HomeWidget.widgetClicked.listen(
      _maybeFireFromWidget,
      onError: (_) {},
    );
  }

  void _maybeFireFromWidget(Uri? uri) {
    if (uri?.host == 'sos' && mounted) {
      context.read<SosBloc>().add(const SosFired());
    }
  }

  @override
  void dispose() {
    _homeWidgetClickSubscription?.cancel();
    super.dispose();
  }

  void _showContacts() {
    setState(() => _fabOpen = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactsListScreen()),
    );
  }

  void _addContact() {
    setState(() => _fabOpen = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
    );
  }

  void _openProfile() {
    setState(() => _fabOpen = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  void _onSosState(BuildContext context, SosState state) {
    if (state.feedback != null && state.feedbackId > 0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(state.feedback!),
          duration: const Duration(seconds: 3),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    final sosSize = (shortest * 0.40).clamp(110.0, 175.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: MultiBlocListener(
        listeners: [
          BlocListener<SosBloc, SosState>(
            listenWhen: (p, c) => p.feedbackId != c.feedbackId,
            listener: _onSosState,
          ),
        ],
        child: SafeArea(
          child: Stack(
            children: [
              // Red radial glow behind the button.
              Center(child: _glow(sosSize)),
              // SOS "Press & Hold" button (center).
              Center(child: _sosButton(sosSize)),
              // Speed-dial FAB (bottom-right).
              Positioned(right: 6, bottom: 6, child: _fab()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glow(double size) {
    // Soft red radial gradient behind the button that fades into the dark bg.
    return IgnorePointer(
      child: Container(
        width: size * 1.9,
        height: size * 1.9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _kSosRed.withValues(alpha: 0.4),
              _kSosRed.withValues(alpha: 0.0),
            ],
            stops: const [0.35, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _sosButton(double size) {
    return BlocBuilder<SosBloc, SosState>(
      buildWhen: (p, c) => p.sending != c.sending,
      builder: (context, state) {
        return GestureDetector(
          onLongPress: () => context.read<SosBloc>().add(const SosFired()),
          child: Container(
            width: size,
            height: size,
            // Outer red ring — smooth top-lit gradient (no seam).
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF5A5A), // light (top-left, where light hits)
                  Color(0xFFE53935), // mid red
                  Color(0xFFB01019), // deep red (bottom-right shadow)
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: Padding(
              // +5 thicker ring → white circle radius reduced by 5.
              padding: EdgeInsets.all(size * 0.07 + 8),
              // Inner white circle.
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Center(
                  child: state.sending
                      ? SizedBox(
                          width: size * 0.3,
                          height: size * 0.3,
                          child: const CircularProgressIndicator(
                              color: AppColors.red, strokeWidth: 3),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/icons/press_hold.png',
                              width: size * 0.32,
                              height: size * 0.32,
                            ),
                            // SizedBox(height: 10//size * 0.05
                            // ),
                            // Outlined "Press & Hold" pill.
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: size * 0.055,
                                vertical: size * 0.022,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.red, width: 1.2),
                                borderRadius: BorderRadius.circular(size),
                              ),
                              child: const Text(
                                'Press & Hold',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.red,
                                  fontSize: 6, //size * 0.065,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          _fabAction('Show Contacts', Icons.people_alt_rounded, _showContacts),
          const SizedBox(height: 8),
          _fabAction(
              'Add Contact', Icons.person_add_alt_1_rounded, _addContact),
          const SizedBox(height: 8),
          _fabAction('Profile', Icons.person_rounded, _openProfile),
          const SizedBox(height: 8),
        ],
        _fabToggle(),
      ],
    );
  }

  Widget _fabToggle() {
    return _circleButton(
      icon: _fabOpen ? Icons.close_rounded : Icons.add,
      size: 35,
      onTap: () => setState(() => _fabOpen = !_fabOpen),
      color: _fabOpen ? AppColors.field : AppColors.accent,
    );
  }

  Widget _fabAction(String label, IconData icon, VoidCallback onTap) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.field,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 10)),
          ),
        ),
        const SizedBox(width: 6),
        _circleButton(
            icon: icon, size: 34, onTap: onTap, color: AppColors.accent),
      ],
    );
  }

  Widget _circleButton(
      {required IconData icon,
      required double size,
      required VoidCallback onTap,
      required color}) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkResponse(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
