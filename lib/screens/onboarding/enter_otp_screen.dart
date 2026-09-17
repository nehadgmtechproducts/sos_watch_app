import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/contacts/contacts_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../services/api_service.dart';
import '../../services/profile_store.dart';

import '../../responsive.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'enter_user_details_screen.dart';
import '../home_screen.dart';

/// Onboarding screen 2 — Enter OTP (round smartwatch).
///
/// UI only. When the APIs are ready, entering 6 digits will dispatch a
/// "verify OTP" event to an AuthBloc; the auto-navigate below is a placeholder.
class EnterOtpScreen extends StatefulWidget {
  final String phoneNumber;
  const EnterOtpScreen({super.key, required this.phoneNumber});

  @override
  State<EnterOtpScreen> createState() => _EnterOtpScreenState();
}

class _EnterOtpScreenState extends State<EnterOtpScreen> {
  static const int _otpLength = 6;
  static const int _resendSeconds = 25;

  // A single input field drives all six boxes — avoids Wear OS's full-screen
  // IME dropping keystrokes when focus hops between separate fields.
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _timer;
  int _secondsLeft = _resendSeconds;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _focus.addListener(() => setState(() {})); // refresh active-box highlight
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _onChanged(String value) {
    setState(() {}); // repaint the boxes
    if (value.length == _otpLength) _onCompleted();
  }

  void _onCompleted() {
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(OtpVerified(_controller.text));
  }

  void _onResend() {
    if (_secondsLeft > 0) return;
    context.read<AuthBloc>().add(OtpRequested(widget.phoneNumber));
    _controller.clear();
    _focus.requestFocus();
    setState(() {});
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) async {
        if (state is Authenticated) {
          await ProfileStore.instance.markLoggedIn(state.accessToken);
          if (!context.mounted) return;
          var hasCompletedProfile =
              await ProfileStore.instance.hasCompletedProfile();
          if (!context.mounted) return;
          if (!state.isNewUser && !hasCompletedProfile) {
            try {
              await ProfileStore.instance.fetchAndCache(
                context.read<ProfileBloc>().api,
              );
              if (!context.mounted) return;
              hasCompletedProfile =
                  await ProfileStore.instance.hasCompletedProfile();
            } on ApiException {
              // Existing users can still reach Home for this authenticated
              // session; their profile will be refreshed on the next load.
            }
          }
          if (!context.mounted) return;
          context.read<ContactsBloc>().add(const ContactsStarted());
          // The API identifies returning users, while the local check also
          // handles a completed profile saved during this app session.
          final goHome = !state.isNewUser || hasCompletedProfile;
          if (goHome) {
            // Clear the stack, so the login screens aren't left underneath
            // Home — otherwise Back from Home, or anything that unwinds the
            // stack, lands a signed-in user on the login screen.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (_) => false,
            );
          } else {
            Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) =>
                  EnterUserDetailsScreen(phoneNumber: widget.phoneNumber),
            ));
          }
        }
        if (state is AuthFailure) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: EdgeInsets.all(watch ? 12 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: AppColors.accent, size: 26),
              const SizedBox(height: 8),
              const Text('Enter OTP', style: AppTextStyles.title),
              const SizedBox(height: 3),
              Text(
                'We have sent 6 digit OTP\nto ${widget.phoneNumber}',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 14),
              _OtpBoxes(
                length: _otpLength,
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _onResend,
                child: Text(
                  _secondsLeft > 0
                      ? 'Resend OTP in ${_secondsLeft}s'
                      : 'Resend OTP',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight:
                        _secondsLeft > 0 ? FontWeight.w400 : FontWeight.w600,
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

/// Six OTP boxes rendered from a single hidden input field. Tapping the boxes
/// focuses that field; typed digits fill the boxes left-to-right.
class _OtpBoxes extends StatelessWidget {
  final int length;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBoxes({
    required this.length,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const gap = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit all boxes within ~92% of available width and scale to match.
        final rowWidth = constraints.maxWidth * 0.92;
        final box =
            ((rowWidth - gap * (length - 1)) / length).clamp(18.0, 40.0);
        final height = box * 1.28;
        final font = box * 0.55;
        final totalWidth = box * length + gap * (length - 1);
        final text = controller.text;

        return SizedBox(
          width: totalWidth,
          height: height,
          child: Stack(
            children: [
              // Visible boxes.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < length; i++) ...[
                    if (i != 0) const SizedBox(width: gap),
                    _box(
                      char: i < text.length ? text[i] : '',
                      active: focusNode.hasFocus && i == text.length,
                      width: box,
                      height: height,
                      font: font,
                    ),
                  ],
                ],
              ),
              // Transparent field on top captures the keyboard for all boxes.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    showCursor: false,
                    maxLength: length,
                    style: const TextStyle(
                        height: 0.01, color: Colors.transparent),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(length),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _box({
    required String char,
    required bool active,
    required double width,
    required double height,
    required double font,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: active ? AppColors.accent : AppColors.border,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Text(
        char,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: font,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
