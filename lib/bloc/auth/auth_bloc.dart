import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/api_service.dart';
import '../../services/profile_store.dart';
import '../../services/contacts_store.dart';
import '../../services/push_service.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthSessionCleared extends AuthEvent {
  const AuthSessionCleared();
}

class OtpRequested extends AuthEvent {
  final String phone;
  const OtpRequested(this.phone);
  @override
  List<Object?> get props => [phone];
}

class OtpVerified extends AuthEvent {
  final String otp;
  const OtpVerified(this.otp);
  @override
  List<Object?> get props => [otp];
}

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class OtpSent extends AuthState {
  final String requestId;
  const OtpSent(this.requestId);
  @override
  List<Object?> get props => [requestId];
}

class Authenticated extends AuthState {
  final bool isNewUser;
  final String accessToken;
  const Authenticated(this.isNewUser, this.accessToken);
  @override
  List<Object?> get props => [isNewUser, accessToken];
}

class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message);
  @override
  List<Object?> get props => [message];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this.api) : super(const AuthInitial()) {
    on<AuthSessionCleared>((event, emit) {
      _requestId = null;
      emit(const AuthInitial());
    });
    on<OtpRequested>(_request);
    on<OtpVerified>(_verify);
    // When FCM rotates this device's token, re-register it with the backend so
    // "ring my devices" keeps reaching this phone.
    PushService.instance.onTokenRefresh = (_) => registerDevice();
  }
  final ApiService api;
  String? _requestId;

  /// Save this device's FCM token on the backend so the user's other devices
  /// can ring it. Best-effort: a failure just means this device isn't a ring
  /// target yet; it does not block sign-in.
  Future<void> registerDevice() async {
    if (api.token == null) return;
    final fcmToken = await PushService.instance.getToken();
    if (fcmToken == null) return;
    try {
      await api.request('POST', '/devices/register',
          body: {'fcmToken': fcmToken, 'platform': PushService.instance.platform});
    } catch (_) {/* non-fatal */}
  }

  Future<void> logout() async {
    if (api.token != null) {
      // Drop this device from the ring registry first, while the token is still
      // valid — otherwise a logged-out phone keeps receiving SOS rings.
      final fcmToken = await PushService.instance.getToken();
      if (fcmToken != null) {
        try {
          await api.request('POST', '/devices/unregister', body: {'fcmToken': fcmToken});
        } catch (_) {/* non-fatal: continue with logout */}
      }
      try {
        await api.request('POST', '/auth/logout');
      } on ApiException catch (error) {
        // Expired or already revoked sessions still need local cleanup.
        if (error.statusCode != 401) rethrow;
      }
    }
    api.token = null;
    _requestId = null;
    await ProfileStore.instance.clear();
    await ContactsStore.instance.replaceAll([]);
    add(const AuthSessionCleared());
  }


  Future<void> _request(OtpRequested e, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    try {
      final body = <String, dynamic>{'phone': e.phone};
      final fcmToken = await PushService.instance.getToken();
      // The backend uses this token to deliver the OTP via FCM. Omit it only
      // when Firebase cannot create a device token (for example, unsupported
      // simulators); then the backend uses its configured fallback.
      if (fcmToken != null) body['fcmToken'] = fcmToken;
      final r = await api.request('POST', '/auth/otp/request', body: body);
      _requestId = r['requestId'] as String;
      // devOtp is only present in dev mode; the real OTP arrives via FCM push.
      // Read it null-safely so a missing value can't throw and block OtpSent.
      final devOtp = r['devOtp'] as String?;
      if (devOtp != null) print('otp===$devOtp');
      emit(OtpSent(_requestId!));
    } on ApiException catch (e) {
      emit(AuthFailure(e.message));
    }
  }

  Future<void> _verify(OtpVerified e, Emitter<AuthState> emit) async {
    if (_requestId == null) return;
    emit(const AuthLoading());
    try {
      final r = await api.request('POST', '/auth/otp/verify',
          body: {'requestId': _requestId, 'otp': e.otp});
      final accessToken = r['accessToken'] as String;
      api.token = accessToken;
      await registerDevice(); // make this phone a ring target for the account
      emit(Authenticated(r['isNewUser'] as bool, accessToken));
    } on ApiException catch (e) {
      emit(AuthFailure(e.message));
    }
  }
}
