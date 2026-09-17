import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/contacts/contacts_bloc.dart';
import '../../responsive.dart';
import '../../services/contacts_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'contacts_added_screen.dart';
import 'onboarding_common.dart';

/// Onboarding screen 5b — Add Manually (round smartwatch).
///
/// A small form to add a single emergency contact by name + mobile number.
class AddContactScreen extends StatefulWidget {
  /// True during sign-up: a successful save continues to the "Contacts Added"
  /// screen, which then resets the app to Home. False when opened from the
  /// contacts list: the save simply pops back (with `true`) so the user lands on
  /// their list again instead of being thrown out to Home.
  final bool onboarding;

  const AddContactScreen({super.key, this.onboarding = true});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();

  String? _nameError;
  String? _mobileError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    final mobile = _mobile.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _mobileError = mobile.isEmpty
          ? 'Mobile number is required'
          : (!RegExp(r'^\d{10}$').hasMatch(mobile)
              ? 'Enter exactly 10 digits'
              : null);
    });
    if (_nameError != null || _mobileError != null) return;

    setState(() => _saving = true);
    context.read<ContactsBloc>().add(
          ContactAdded(DemoContact(name: name, phone: mobile)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);
    final fieldWidth =
        (MediaQuery.sizeOf(context).width * 0.72).clamp(160.0, 340.0);

    return BlocListener<ContactsBloc, ContactsState>(
      listenWhen: (previous, current) =>
          _saving && previous.actionId != current.actionId,
      listener: (context, state) {
        if (state.error != null) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!)));
          return;
        }
        if (!widget.onboarding) {
          Navigator.of(context).pop(true);
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ContactsAddedScreen()),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Stack(
            children: [
              CenterScroll(
                padding: EdgeInsets.all(watch ? 10 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add_alt_1_rounded,
                        color: AppColors.accent, size: 20),
                    const SizedBox(height: 6),
                    const Text('Add Contact', style: AppTextStyles.title),
                    const SizedBox(height: 12),
                    _LabeledField(
                      width: fieldWidth,
                      label: 'Name',
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      errorText: _nameError,
                      onChanged: () {
                        if (_nameError != null)
                          setState(() => _nameError = null);
                      },
                    ),
                    _LabeledField(
                      width: fieldWidth,
                      label: 'Mobile Number',
                      controller: _mobile,
                      keyboardType: TextInputType.number,
                      //prefixText: '+91 ',
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      maxLength: 10,
                      errorText: _mobileError,
                      onChanged: () {
                        if (_mobileError != null) {
                          setState(() => _mobileError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: AppColors.accent, strokeWidth: 2),
                          )
                        : RoundedActionButton(
                            onTap: _submit, icon: Icons.check),
                  ],
                ),
              ),
              // Back button (top-left).
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A left-labeled input field (with optional prefix) used on this screen.
class _LabeledField extends StatelessWidget {
  final double width;
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final String? errorText;
  final VoidCallback? onChanged;

  const _LabeledField({
    required this.width,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLength,
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
              inputFormatters: inputFormatters,
              maxLength: maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              decoration: onboardFieldDecoration(errorText: errorText)
                  .copyWith(counterText: ''),
              onChanged: (_) => onChanged?.call(),
            ),
          ],
        ),
      ),
    );
  }
}
