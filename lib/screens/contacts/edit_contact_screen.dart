import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/contacts/contacts_bloc.dart';
import '../../responsive.dart';
import '../../services/contacts_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import '../onboarding/onboarding_common.dart';

/// Screen 10 — Edit Contact.
class EditContactScreen extends StatefulWidget {
  final int index;
  final DemoContact contact;
  const EditContactScreen({
    super.key,
    required this.index,
    required this.contact,
  });

  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.contact.name);
  late final TextEditingController _mobile =
      TextEditingController(text: _nationalNumber(widget.contact.phone));

  String? _nameError;
  String? _mobileError;
  bool _saving = false;

  String _nationalNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
          ContactUpdated(
            widget.index,
            DemoContact(name: name, phone: mobile),
          ),
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
        Navigator.of(context).maybePop();
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
                    const Text('Edit Contact', style: AppTextStyles.title),
                    const SizedBox(height: 12),
                    _field(
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
                    _field(
                      width: fieldWidth,
                      label: 'Mobile Number',
                      controller: _mobile,
                      keyboardType: TextInputType.number,
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
                        : RoundedActionButton(onTap: _save, icon: Icons.check),
                  ],
                ),
              ),
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

  Widget _field({
    required double width,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? errorText,
    VoidCallback? onChanged,
  }) {
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
              inputFormatters: inputFormatters,
              maxLength: maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textCapitalization: textCapitalization,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: onboardFieldDecoration(
                errorText: errorText,
              ).copyWith(counterText: ''),
              onChanged: (_) => onChanged?.call(),
            ),
          ],
        ),
      ),
    );
  }
}
