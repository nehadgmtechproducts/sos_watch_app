import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/contacts/contacts_bloc.dart';
import '../../responsive.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'edit_contact_screen.dart';

/// Screen 9 — Contact Detail.
class ContactDetailScreen extends StatelessWidget {
  final int index;
  const ContactDetailScreen({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final watch = isWatch(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocBuilder<ContactsBloc, ContactsState>(
          builder: (context, state) {
            // Contact may have been removed; guard the index.
            if (index < 0 || index >= state.contacts.length) {
              return const Center(
                child: Text('Contact not found', style: AppTextStyles.subtitle),
              );
            }
            final c = state.contacts[index];

            return Stack(
              children: [
                // Scrollable + centered so it fits any screen (vertical).
                CenterScroll(
                  padding: EdgeInsets.symmetric(
                      horizontal: watch ? 22 : 28, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Contact Detail', style: AppTextStyles.title),
                      const SizedBox(height: 12),
                      CircleAvatar(
                        radius: watch ? 24 : 30,
                        backgroundColor: AppColors.field,
                        child: Icon(Icons.person_rounded,
                            color: AppColors.accent, size: watch ? 26 : 32),
                      ),
                      const SizedBox(height: 10),
                      // Constrained + wrapping so long names/numbers don't overflow.
                      Text(
                        c.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.phone,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.subtitle,
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.accent),
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 13),
                        label: const Text('Edit Contact',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                EditContactScreen(index: index, contact: c),
                          ),
                        ),
                      ),
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
            );
          },
        ),
      ),
    );
  }
}
