import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../responsive.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../services/profile_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'emergency_contacts_screen.dart';
import 'onboarding_common.dart';

/// Onboarding screen 3 — User Details (round smartwatch).
///
/// UI only. When the APIs are ready, the check button will dispatch a
/// "save profile" event to a Bloc instead of navigating directly.
class EnterUserDetailsScreen extends StatefulWidget {
  final String phoneNumber;
  const EnterUserDetailsScreen({super.key, required this.phoneNumber});

  @override
  State<EnterUserDetailsScreen> createState() => _EnterUserDetailsScreenState();
}

class _EnterUserDetailsScreenState extends State<EnterUserDetailsScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();

  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;

  static final _emailRegExp = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _email.text.trim();

    setState(() {
      _firstNameError = first.isEmpty ? 'First name is required' : null;
      _lastNameError = last.isEmpty ? 'Last name is required' : null;
      _emailError = email.isEmpty
          ? 'Email is required'
          : (!_emailRegExp.hasMatch(email) ? 'Enter a valid email' : null);
    });
    if (_firstNameError != null ||
        _lastNameError != null ||
        _emailError != null) {
      return;
    }

    context.read<ProfileBloc>().add(ProfileSaved('$first $last', email));
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);
    final fieldWidth =
        (MediaQuery.sizeOf(context).width * 0.72).clamp(160.0, 340.0);

    return BlocListener<ProfileBloc, ProfileState>(
      listener: (context, state) async {
        if (state is ProfileSuccess) {
          await ProfileStore.instance.save(state.profile);
          if (!context.mounted) return;
          Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => const EmergencyContactsScreen()));
        }
        if (state is ProfileFailure) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: EdgeInsets.all(watch ? 10 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(height: 8),
              const Text('User Details', style: AppTextStyles.title),
              const SizedBox(height: 12),
              _LabeledField(
                width: fieldWidth,
                label: 'First Name',
                controller: _firstName,
                //hint: 'First name',
                textCapitalization: TextCapitalization.words,
                errorText: _firstNameError,
                onChanged: () {
                  if (_firstNameError != null) {
                    setState(() => _firstNameError = null);
                  }
                },
              ),
              _LabeledField(
                width: fieldWidth,
                label: 'Last Name',
                controller: _lastName,
                //hint: 'Last name',
                textCapitalization: TextCapitalization.words,
                errorText: _lastNameError,
                onChanged: () {
                  if (_lastNameError != null) {
                    setState(() => _lastNameError = null);
                  }
                },
              ),
              _LabeledField(
                width: fieldWidth,
                label: 'Email',
                controller: _email,
                //  hint: 'name@mail.com',
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                onChanged: () {
                  if (_emailError != null) setState(() => _emailError = null);
                },
              ),
              const SizedBox(height: 6),
              RoundedActionButton(onTap: _submit, icon: Icons.check),
            ],
          ),
        ),
      ),
    );
  }
}

/// A left-labeled input field used on the User Details screen.
class _LabeledField extends StatelessWidget {
  final double width;
  final String label;
  final TextEditingController controller;
  // final String hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final VoidCallback? onChanged;

  const _LabeledField({
    required this.width,
    required this.label,
    required this.controller,
    // required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.label),
            const SizedBox(height: 3),
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              decoration: onboardFieldDecoration(
                  //hint: hint,
                  errorText: errorText),
              onChanged: (_) => onChanged?.call(),
            ),
          ],
        ),
      ),
    );
  }
}
