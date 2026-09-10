import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/contacts/contacts_bloc.dart';
import '../../services/contacts_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import 'contacts_added_screen.dart';
import 'onboarding_common.dart';

/// Onboarding screen 5a — Choose from Contacts (round smartwatch).
///
/// Reads the device's real contacts, lets the user pick one or more emergency
/// contacts, and saves them.
class ChooseContactsScreen extends StatefulWidget {
  const ChooseContactsScreen({super.key});

  @override
  State<ChooseContactsScreen> createState() => _ChooseContactsScreenState();
}

class _ChooseContactsScreenState extends State<ChooseContactsScreen> {
  bool _loading = true;
  bool _permissionDenied = false;
  bool _saving = false;

  List<Contact> _all = [];
  final Set<String> _selected = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    // Only contacts that actually have a phone number are usable.
    final withPhones = contacts.where((c) => c.phones.isNotEmpty).toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _all = withPhones;
      _loading = false;
    });
  }

  List<Contact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.phones.any((p) => p.number.replaceAll(' ', '').contains(q)))
        .toList();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _next() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);

    for (final c in _all.where((c) => _selected.contains(c.id))) {
      context.read<ContactsBloc>().add(
            ContactAdded(DemoContact(
              name: c.displayName.isEmpty ? 'Unnamed' : c.displayName,
              phone: c.phones.first.number,
            )),
          );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ContactsAddedScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header: back + title.
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
                    child: Text(
                      'Select Contacts',
                      softWrap: true,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title,
                    ),
                  ),
                  const SizedBox(width: 36), // balances the back button
                ],
              ),
            ),
            // Search.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                onChanged: (v) => setState(() => _query = v),
                decoration:
                    onboardFieldDecoration(hint: 'Search contact').copyWith(
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.subtitle, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildBody()),
            _buildNextButton(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_permissionDenied) {
      return _messageWithAction(
        message: 'Contacts permission is needed to pick emergency contacts.',
        actionLabel: 'Open settings',
        onAction: () async {
          await openAppSettings();
        },
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No contacts found' : 'No matches',
          style: AppTextStyles.subtitle,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final c = list[i];
        final selected = _selected.contains(c.id);
        return InkWell(
          onTap: () => _toggle(c.id),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.accent : AppColors.subtitle,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.displayName.isEmpty ? 'Unnamed' : c.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        c.phones.first.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.subtitle, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNextButton() {
    final enabled = _selected.isNotEmpty && !_saving;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppDimens.buttonRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? _next : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _selected.isEmpty ? 'Next' : 'Next (${_selected.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _messageWithAction({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center, style: AppTextStyles.subtitle),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel,
                  style:
                      const TextStyle(color: AppColors.accent, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
