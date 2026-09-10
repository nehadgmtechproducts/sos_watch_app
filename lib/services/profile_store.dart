import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class UserProfile {
  final String name;
  final String email;
  final String mobile;

  const UserProfile({
    required this.name,
    required this.email,
    required this.mobile,
  });

  factory UserProfile.fromApi(Map<String, dynamic> user) => UserProfile(
        name: user['name']?.toString() ?? '',
        email: user['email']?.toString() ?? '',
        mobile: user['phone']?.toString() ?? '',
      );
}

/// Local profile storage used by the profile and logout flow.
class ProfileStore {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  static const _nameKey = 'profile_name';
  static const _emailKey = 'profile_email';
  static const _mobileKey = 'profile_mobile';
  static const _accessTokenKey = 'access_token';
  static const _loggedInKey = 'is_logged_in';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UserProfile(
      name: prefs.getString(_nameKey) ?? '',
      email: prefs.getString(_emailKey) ?? '',
      mobile: prefs.getString(_mobileKey) ?? '',
    );
  }

  /// A saved profile represents an active local session. Logout removes all
  /// three fields, so this remains false until the user completes onboarding.
  Future<bool> hasCompletedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      prefs.getString(_nameKey),
      prefs.getString(_emailKey),
      prefs.getString(_mobileKey),
    ].every((value) => value != null && value.trim().isNotEmpty);
  }

  /// One-time login: the session remains active until explicit logout.
  /// Completed legacy profiles count as logged in because logout clears them.
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? await hasCompletedProfile();
  }

  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Persists the signed-in state until an explicit logout.
  Future<void> markLoggedIn(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setBool(_loggedInKey, true);
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, profile.name);
    await prefs.setString(_emailKey, profile.email);
    await prefs.setString(_mobileKey, profile.mobile);
  }

  /// Fetches the authenticated user's profile and keeps the startup cache in
  /// sync with the server's canonical name, email, and phone values.
  Future<UserProfile> fetchAndCache(ApiService api) async {
    final response = await api.request('GET', '/users/me');
    final profile = UserProfile.fromApi(
      Map<String, dynamic>.from(response['user'] as Map),
    );
    await save(profile);
    return profile;
  }

  /// Updates the editable profile fields. Phone belongs to OTP authentication
  /// and is returned unchanged by the API.
  Future<UserProfile> updateAndCache(
    ApiService api, {
    required String name,
    required String email,
  }) async {
    final response = await api.request(
      'PUT',
      '/users/me',
      body: {'name': name, 'email': email},
    );
    final profile = UserProfile.fromApi(
      Map<String, dynamic>.from(response['user'] as Map),
    );
    await save(profile);
    return profile;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_mobileKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_loggedInKey);
  }
}
