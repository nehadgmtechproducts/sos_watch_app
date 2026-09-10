import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';

import '../bloc/contacts/contacts_bloc.dart';
import '../services/contacts_store.dart';

/// Simple local list of emergency contacts (demo — no backend, stored on-device).
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  Future<void> _addDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final bloc = context.read<ContactsBloc>();
    String? phoneError;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.all(12),
          title: const Text('Add contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'Mobile number',
                    errorText: phoneError,
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) {
                    if (phoneError != null) {
                      setDialogState(() => phoneError = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!RegExp(r'^\d{10}$').hasMatch(phoneCtrl.text.trim())) {
                  setDialogState(
                    () => phoneError = 'Enter exactly 10 digits',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (added == true && nameCtrl.text.trim().isNotEmpty) {
      bloc.add(
        ContactAdded(
          DemoContact(
              name: nameCtrl.text.trim(),
              phone: '+91 ${phoneCtrl.text.trim()}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: BlocBuilder<ContactsBloc, ContactsState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.contacts.isEmpty) {
            return const Center(child: Text('No contacts yet. Tap “Add”.'));
          }
          return ListView.separated(
            itemCount: state.contacts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = state.contacts[i];
              return ListTile(
                leading: CircleAvatar(child: Text(c.name.characters.first)),
                title: Text(c.name),
                subtitle: c.phone.isEmpty ? null : Text(c.phone),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => context
                      .read<ContactsBloc>()
                      .add(ContactRemoved(state.contacts[i].id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
