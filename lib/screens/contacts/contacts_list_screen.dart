import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/contacts/contacts_bloc.dart';
import '../../services/contacts_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'contact_detail_screen.dart';
import '../onboarding/add_contact_screen.dart';

/// Screen 8 — Contacts List (Show Contacts).
class ContactsListScreen extends StatelessWidget {
  const ContactsListScreen({super.key});

  Future<void> _deleteContact(BuildContext context, DemoContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.field,
        surfaceTintColor: Colors.transparent,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        icon: const Icon(Icons.delete_outline_rounded,
            color: AppColors.error, size: 28),
        title: const Text('Delete contact?',
            textAlign: TextAlign.center, style: AppTextStyles.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(contact.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(contact.phone,
                textAlign: TextAlign.center, style: AppTextStyles.subtitle),
            const SizedBox(height: 12),
            const Text('Remove this person from your emergency contacts?',
                textAlign: TextAlign.center, style: AppTextStyles.subtitle),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<ContactsBloc>().add(ContactRemoved(contact.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(
                    child: Text('Contacts',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.title),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Add contact',
                    icon: const Icon(Icons.person_add_alt_1_rounded,
                        color: AppColors.accent, size: 20),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AddContactScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocConsumer<ContactsBloc, ContactsState>(
                listenWhen: (previous, current) =>
                    previous.actionId != current.actionId &&
                    current.error != null,
                listener: (context, state) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(state.error!)),
                  );
                },
                builder: (context, state) {
                  if (state.loading) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    );
                  }
                  if (state.error != null && state.contacts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(state.error!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.subtitle),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: () => context
                                  .read<ContactsBloc>()
                                  .add(const ContactsStarted()),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (state.contacts.isEmpty) {
                    return const Center(
                      child: Text('No contacts yet',
                          style: AppTextStyles.subtitle),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                    itemCount: state.contacts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = state.contacts[i];
                      return Material(
                        color: AppColors.field,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ContactDetailScreen(index: i),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.phone,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.subtitle,
                                            fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete ${c.name}',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: AppColors.error, size: 20),
                                  onPressed: () => _deleteContact(context, c),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    color: AppColors.subtitle, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
