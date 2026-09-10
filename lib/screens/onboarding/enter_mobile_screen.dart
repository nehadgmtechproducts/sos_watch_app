import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';

import '../../responsive.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'enter_otp_screen.dart';
import 'onboarding_common.dart';

/// Onboarding screen 1 — Enter Mobile Number (round smartwatch).
///
/// UI only. When the APIs are ready, the check button will dispatch a
/// "send OTP" event to an AuthBloc instead of navigating directly.
class EnterMobileScreen extends StatefulWidget {
  const EnterMobileScreen({super.key});

  @override
  State<EnterMobileScreen> createState() => _EnterMobileScreenState();
}

class _EnterMobileScreenState extends State<EnterMobileScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Open the keyboard exactly once, after the page transition settles.
    // (autofocus fired mid-transition, which opened the keyboard twice.)
    // Future.delayed(const Duration(milliseconds: 350), () {
    //   if (mounted) _focusNode.requestFocus();
    // });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Close the keyboard so it doesn't immediately reopen after "Done".
    _focusNode.unfocus();
    final national = _controller.text.trim();
    // Validate independently of the field limiter, so navigation cannot occur
    // with an invalid number even if the controller is set programmatically.
    if (national.isEmpty) {
      setState(() => _error = 'Please enter your mobile number');
      return;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(national)) {
      setState(() => _error = 'Enter exactly 10 digits');
      return;
    }
    setState(() => _error = null);

    context.read<AuthBloc>().add(OtpRequested('+91 $national'));
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);
    // Responsive field width: scales with the screen instead of a fixed value.
    final fieldWidth =
        (MediaQuery.sizeOf(context).width * 0.55).clamp(150.0, 320.0);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is OtpSent)
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EnterOtpScreen(
                  phoneNumber: '+91 ${_controller.text.trim()}')));
        if (state is AuthFailure) setState(() => _error = state.message);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: EdgeInsets.all(watch ? 14 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(height: 8),
              const Text('Mobile Number', style: AppTextStyles.title),
              const SizedBox(height: 3),
              const Text(
                'Enter your mobile number',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  //textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10), // max 10 digits
                  ],
                  decoration: onboardFieldDecoration(
                    //hint: '98765 43210',
                    //prefixText: '+91 ',
                    errorText: _error,
                  ).copyWith(counterText: ''),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 10),
              RoundedActionButton(onTap: _submit, icon: Icons.check),
            ],
          ),
        ),
      ),
    );
  }
}
