import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single emergency contact, cached locally for SOS delivery.
class DemoContact extends Equatable {
  final String? id;
  final String name;
  final String phone;
  const DemoContact({this.id, required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};
  factory DemoContact.fromJson(Map<String, dynamic> j) => DemoContact(
        id: j['id']?.toString(),
        name: j['name'] as String,
        phone: j['phone'] as String? ?? '',
      );

  @override
  List<Object?> get props => [id, name, phone];
}

/// In-memory + shared_preferences backed list of mock contacts. No backend.
class ContactsStore {
  ContactsStore._();
  static final ContactsStore instance = ContactsStore._();

  static const _key = 'demo_contacts';
  List<DemoContact> _contacts = [];
  bool _loaded = false;

  Future<List<DemoContact>> all() async {
    if (_loaded) return _contacts;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _contacts = [];
    } else {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _contacts = list.map(DemoContact.fromJson).toList();
    }
    _loaded = true;
    return _contacts;
  }

  Future<void> add(DemoContact c) async {
    await all();
    _contacts.add(c);
    await _persist();
  }

  Future<void> removeAt(int index) async {
    await all();
    _contacts.removeAt(index);
    await _persist();
  }

  Future<void> updateAt(int index, DemoContact c) async {
    await all();
    if (index < 0 || index >= _contacts.length) return;
    _contacts[index] = c;
    await _persist();
  }

  Future<void> replaceAll(List<DemoContact> contacts) async {
    _contacts = List.of(contacts);
    _loaded = true;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_contacts.map((c) => c.toJson()).toList()),
    );
  }
}
