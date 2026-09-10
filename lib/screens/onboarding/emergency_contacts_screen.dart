import 'package:flutter/material.dart';

import '../../responsive.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'add_contact_screen.dart';
import 'choose_contacts_screen.dart';

/// Onboarding screen 4 — Emergency Contacts (round smartwatch).
///
/// Offers two ways to add contacts: pick from the phone's contacts, or add
/// manually. UI only — the two options currently route to placeholders (the
/// "Choose from Contacts" and "Add Manually" screens come next).
class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  void _chooseFromContacts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChooseContactsScreen()),
    );
  }

  void _addManually(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);
    final tileWidth =
        (MediaQuery.sizeOf(context).width * 0.78).clamp(180.0, 360.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CenterScroll(
        padding: EdgeInsets.all(watch ? 14 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded, color: AppColors.accent, size: 24),
            const SizedBox(height: 8),
            const Text('Emergency Contacts', style: AppTextStyles.title),
            const SizedBox(height: 12),
            _OptionTile(
              width: tileWidth,
              icon: Icons.contacts_rounded,
              label: 'Choose from Contacts',
              onTap: () => _chooseFromContacts(context),
            ),
            const SizedBox(height: 8),
            _OptionTile(
              width: tileWidth,
              icon: Icons.person_add_alt_1_rounded,
              label: 'Add Manually',
              onTap: () => _addManually(context),
            ),
            const SizedBox(height: 12),
            const Text(
              'Minimum 1 contact\nis required',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.accent, fontSize: 10, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable option row (icon · label · chevron).
class _OptionTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: AppColors.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.subtitle, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
