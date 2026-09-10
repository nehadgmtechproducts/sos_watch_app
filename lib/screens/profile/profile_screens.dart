import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/contacts/contacts_bloc.dart';
import '../../responsive.dart';
import '../../services/api_service.dart';
import '../../services/profile_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_styles.dart';
import '../onboarding/enter_mobile_screen.dart';
import '../onboarding/onboarding_common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<UserProfile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<UserProfile> _loadProfile() async {
    try {
      return await ProfileStore.instance.fetchAndCache(
        context.read<ProfileBloc>().api,
      );
    } on ApiException {
      // Cached details still allow the profile UI to work while offline.
      return ProfileStore.instance.load();
    }
  }

  void _refresh() {
    setState(() {
      _profile = _loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<UserProfile>(
        future: _profile,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final profile = snapshot.data!;
          return CenterScroll(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BackTitle(title: 'Profile'),
                const SizedBox(height: 8),
                const _Avatar(size: 46),
                const SizedBox(height: 5),
                Text(profile.name, style: AppTextStyles.title),
                Text(profile.email, style: AppTextStyles.subtitle),
                const SizedBox(height: 8),
                _MenuTile(
                  label: 'View Profile',
                  icon: Icons.person_outline_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ViewProfileScreen(profile: profile),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                _MenuTile(
                  label: 'Edit Profile',
                  icon: Icons.edit_outlined,
                  onTap: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(profile: profile),
                      ),
                    );
                    if (updated == true) _refresh();
                  },
                ),
                const SizedBox(height: 5),
                _MenuTile(
                  label: 'Logout',
                  icon: Icons.logout_rounded,
                  color: AppColors.red,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LogoutScreen()),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ViewProfileScreen extends StatelessWidget {
  final UserProfile profile;
  const ViewProfileScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BackTitle(title: 'My Profile'),
              const SizedBox(height: 8),
              const Center(child: _Avatar(size: 48)),
              const SizedBox(height: 10),
              _ProfileDetail(label: 'Name', value: profile.name),
              _ProfileDetail(label: 'Email', value: profile.email),
              _ProfileDetail(label: 'Mobile', value: profile.mobile),
            ],
          ),
        ),
      );
}

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _email = TextEditingController(text: widget.profile.email);
  late final _mobile =
      TextEditingController(text: _national(widget.profile.mobile));
  String? _nameError;
  String? _emailError;
  String? _mobileError;
  bool _saving = false;
  static final _emailPattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  String _national(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final mobile = _mobile.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _emailError = email.isEmpty
          ? 'Email is required'
          : (!_emailPattern.hasMatch(email) ? 'Enter a valid email' : null);
      _mobileError = !RegExp(r'^\d{10}$').hasMatch(mobile)
          ? 'Enter exactly 10 digits'
          : null;
    });
    if (_nameError != null || _emailError != null || _mobileError != null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileStore.instance.updateAndCache(
        context.read<ProfileBloc>().api,
        name: name,
        email: email,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * .72).clamp(160.0, 340.0);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CenterScroll(
        padding: EdgeInsets.all(isWatch(context) ? 8 : 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BackTitle(title: 'Edit Profile'),
            const SizedBox(height: 8),
            _ProfileField(
              width: width,
              label: 'Name',
              controller: _name,
              errorText: _nameError,
              capitalization: TextCapitalization.words,
              onChanged: () => setState(() => _nameError = null),
            ),
            _ProfileField(
              width: width,
              label: 'Email',
              controller: _email,
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
              onChanged: () => setState(() => _emailError = null),
            ),
            _ProfileField(
              width: width,
              label: 'Mobile Number',
              controller: _mobile,
              errorText: _mobileError,
              keyboardType: TextInputType.number,
              maxLength: 10,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onChanged: () => setState(() => _mobileError = null),
            ),
            const SizedBox(height: 8),
            _saving
                ? const CircularProgressIndicator(color: AppColors.accent)
                : RoundedActionButton(onTap: _save, icon: Icons.check),
          ],
        ),
      ),
    );
  }
}

class LogoutScreen extends StatefulWidget {
  const LogoutScreen({super.key});

  @override
  State<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends State<LogoutScreen> {
  bool _loggingOut = false;

  Future<void> _logout(BuildContext context) async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await context.read<AuthBloc>().logout();
      if (!context.mounted) return;
      context.read<ContactsBloc>().add(const ContactsCleared());
      context.read<ProfileBloc>().add(const ProfileCleared());
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoggedOutScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!context.mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is ApiException
            ? error.message
            : 'Could not finish logout. Please try again.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BackTitle(title: 'Logout'),
              const SizedBox(height: 7),
              const Icon(Icons.logout_rounded, color: AppColors.red, size: 38),
              const SizedBox(height: 7),
              const Text('Are you sure you\nwant to logout?',
                  textAlign: TextAlign.center, style: AppTextStyles.subtitle),
              const SizedBox(height: 7),
              SizedBox(
                width: 100,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    minimumSize: const Size(100, 30),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _loggingOut ? null : () => _logout(context),
                  child: _loggingOut
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                      : const Text('Logout'),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -5),
                child: SizedBox(
                  width: 100,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      minimumSize: const Size(100, 30),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    onPressed: _loggingOut ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class LoggedOutScreen extends StatelessWidget {
  const LoggedOutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: CenterScroll(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout_rounded,
                  color: AppColors.accent, size: 44),
              const SizedBox(height: 10),
              const Text('Logged Out\nSuccessfully',
                  textAlign: TextAlign.center, style: AppTextStyles.title),
              const SizedBox(height: 12),
              SizedBox(
                width: 110,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const EnterMobileScreen()),
                    (_) => false,
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _BackTitle extends StatelessWidget {
  final String title;
  const _BackTitle({required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center, style: AppTextStyles.title),
          ),
          const SizedBox(width: 40),
        ],
      );
}

class _Avatar extends StatelessWidget {
  final double size;
  const _Avatar({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accent),
        ),
        child: Icon(Icons.person_rounded,
            size: size * .62, color: AppColors.accent),
      );
}

class _MenuTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  const _MenuTile(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Material(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                Icon(icon, color: color ?? AppColors.textPrimary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: color ?? AppColors.textPrimary,
                            fontSize: 12))),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textPrimary, size: 18),
              ]),
            ),
          ),
        ),
      );
}

class _ProfileDetail extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: 3),
          Text(value, style: AppTextStyles.subtitle),
        ]),
      );
}

class _ProfileField extends StatelessWidget {
  final double width;
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final int? maxLength;
  final List<TextInputFormatter>? formatters;
  final VoidCallback onChanged;
  const _ProfileField({
    required this.width,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.errorText,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.maxLength,
    this.formatters,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTextStyles.label),
            const SizedBox(height: 3),
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              textCapitalization: capitalization,
              inputFormatters: formatters,
              maxLength: maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: onboardFieldDecoration(errorText: errorText)
                  .copyWith(counterText: ''),
              onChanged: (_) => onChanged(),
            ),
          ]),
        ),
      );
}
