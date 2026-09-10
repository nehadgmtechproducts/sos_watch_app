import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/api_service.dart';
import '../../services/contacts_store.dart';

// ─────────────────────────── Events ───────────────────────────
sealed class ContactsEvent extends Equatable {
  const ContactsEvent();
  @override
  List<Object?> get props => [];
}

/// Load the contacts from storage.
class ContactsCleared extends ContactsEvent {
  const ContactsCleared();
}

class ContactsStarted extends ContactsEvent {
  const ContactsStarted();
}

class ContactAdded extends ContactsEvent {
  final DemoContact contact;
  const ContactAdded(this.contact);
  @override
  List<Object?> get props => [contact];
}

class ContactRemoved extends ContactsEvent {
  final String? id;
  const ContactRemoved(this.id);
  @override
  List<Object?> get props => [id];
}

class ContactUpdated extends ContactsEvent {
  final int index;
  final DemoContact contact;
  const ContactUpdated(this.index, this.contact);
  @override
  List<Object?> get props => [index, contact];
}

// ─────────────────────────── State ───────────────────────────
class ContactsState extends Equatable {
  final bool loading;
  final List<DemoContact> contacts;
  final String? error;
  final int actionId;
  const ContactsState({
    this.loading = true,
    this.contacts = const [],
    this.error,
    this.actionId = 0,
  });

  ContactsState copyWith({
    bool? loading,
    List<DemoContact>? contacts,
    String? error,
    int? actionId,
  }) =>
      ContactsState(
        loading: loading ?? this.loading,
        contacts: contacts ?? this.contacts,
        error: error,
        actionId: actionId ?? this.actionId,
      );

  @override
  List<Object?> get props => [loading, contacts, error, actionId];
}

// ─────────────────────────── Bloc ───────────────────────────
class ContactsBloc extends Bloc<ContactsEvent, ContactsState> {
  final ApiService _api;
  final ContactsStore _store;

  ContactsBloc(this._api, this._store) : super(const ContactsState()) {
    on<ContactsCleared>((event, emit) => emit(const ContactsState(loading: false)));
    on<ContactsStarted>(_onStarted);
    on<ContactAdded>(_onAdded);
    on<ContactRemoved>(_onRemoved);
    on<ContactUpdated>(_onUpdated);
  }

  Future<void> _onStarted(
      ContactsStarted e, Emitter<ContactsState> emit) async {
    emit(state.copyWith(loading: true));
    try {
      final response = await _api.request('GET', '/contacts');
      final contacts = _contactsFrom(response);
      await _store.replaceAll(contacts);
      emit(ContactsState(
        loading: false,
        contacts: contacts,
        actionId: state.actionId + 1,
      ));
    } on ApiException catch (e) {
      emit(ContactsState(
        loading: false,
        contacts: List.of(await _store.all()),
        error: e.message,
        actionId: state.actionId + 1,
      ));
    }
  }

  Future<void> _onAdded(ContactAdded e, Emitter<ContactsState> emit) async {
    emit(state.copyWith(loading: true));
    try {
      final response = await _api.request(
        'POST',
        '/contacts',
        body: {'name': e.contact.name, 'phone': e.contact.phone},
      );
      final contact = DemoContact.fromJson(
          Map<String, dynamic>.from(response['contact'] as Map));
      final contacts = [...state.contacts, contact];
      await _store.replaceAll(contacts);
      emit(ContactsState(
        loading: false,
        contacts: contacts,
        actionId: state.actionId + 1,
      ));
    } on ApiException catch (e) {
      emit(ContactsState(
        loading: false,
        contacts: state.contacts,
        error: e.message,
        actionId: state.actionId + 1,
      ));
    }
  }

  Future<void> _onRemoved(ContactRemoved e, Emitter<ContactsState> emit) async {
    if (state.loading) return;
    if (e.id == null) {
      emit(state.copyWith(
        error:
            'This contact has not synced with the server yet. Refresh and try again.',
        actionId: state.actionId + 1,
      ));
      return;
    }
    emit(state.copyWith(loading: true));
    try {
      await _api.request('DELETE', '/contacts/${Uri.encodeComponent(e.id!)}');
      final contacts = state.contacts.where((c) => c.id != e.id).toList();
      await _store.replaceAll(contacts);
      emit(state.copyWith(
        loading: false,
        contacts: contacts,
        actionId: state.actionId + 1,
      ));
    } on ApiException catch (error) {
      emit(state.copyWith(
        loading: false,
        error: error.message,
        actionId: state.actionId + 1,
      ));
    }
  }

  Future<void> _onUpdated(ContactUpdated e, Emitter<ContactsState> emit) async {
    if (e.index < 0 || e.index >= state.contacts.length) {
      emit(ContactsState(
        loading: false,
        contacts: state.contacts,
        error: 'Contact not found.',
        actionId: state.actionId + 1,
      ));
      return;
    }
    final id = state.contacts[e.index].id;
    if (id == null) {
      emit(ContactsState(
        loading: false,
        contacts: state.contacts,
        error: 'This contact has not synced with the server yet.',
        actionId: state.actionId + 1,
      ));
      return;
    }
    emit(state.copyWith(loading: true));
    try {
      final response = await _api.request(
        'PATCH',
        '/contacts/$id',
        body: {'name': e.contact.name, 'phone': e.contact.phone},
      );
      final updated = response['contact'] is Map
          ? DemoContact.fromJson(
              Map<String, dynamic>.from(response['contact'] as Map))
          : DemoContact(id: id, name: e.contact.name, phone: e.contact.phone);
      final contacts = List<DemoContact>.of(state.contacts)
        ..[e.index] = updated;
      await _store.replaceAll(contacts);
      emit(ContactsState(
        loading: false,
        contacts: contacts,
        actionId: state.actionId + 1,
      ));
    } on ApiException catch (e) {
      emit(ContactsState(
        loading: false,
        contacts: state.contacts,
        error: e.message,
        actionId: state.actionId + 1,
      ));
    }
  }

  List<DemoContact> _contactsFrom(Map<String, dynamic> response) {
    final values = response['contacts'];
    if (values is! List) return [];
    return values
        .whereType<Map>()
        .map((contact) =>
            DemoContact.fromJson(Map<String, dynamic>.from(contact)))
        .toList();
  }
}
