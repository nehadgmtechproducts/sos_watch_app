import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/api_service.dart';
import '../../services/profile_store.dart';

sealed class ProfileEvent extends Equatable {
  const ProfileEvent();
  @override
  List<Object?> get props => [];
}

class ProfileCleared extends ProfileEvent {
  const ProfileCleared();
}

class ProfileSaved extends ProfileEvent {
  final String name;
  final String email;
  const ProfileSaved(this.name, this.email);
  @override
  List<Object?> get props => [name, email];
}

sealed class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileSuccess extends ProfileState {
  final UserProfile profile;
  const ProfileSuccess(this.profile);
  @override
  List<Object?> get props => [profile.name, profile.email, profile.mobile];
}

class ProfileFailure extends ProfileState {
  final String message;
  const ProfileFailure(this.message);
  @override
  List<Object?> get props => [message];
}

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc(this.api) : super(const ProfileInitial()) {
    on<ProfileCleared>((event, emit) => emit(const ProfileInitial()));
    on<ProfileSaved>((e, emit) async {
      emit(const ProfileLoading());
      try {
        final response = await api.request('PUT', '/users/me',
            body: {'name': e.name, 'email': e.email});
        emit(ProfileSuccess(UserProfile.fromApi(
          Map<String, dynamic>.from(response['user'] as Map),
        )));
      } on ApiException catch (x) {
        emit(ProfileFailure(x.message));
      }
    });
  }
  final ApiService api;
}
