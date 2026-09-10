import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/alarm_service.dart';
import '../../services/notification_service.dart';

// ─────────────────────────── Events ───────────────────────────
sealed class AlarmEvent extends Equatable {
  const AlarmEvent();
  @override
  List<Object?> get props => [];
}

/// An SOS arrived (from the LAN stream or the "Simulate" button) — start ringing.
class AlarmTriggered extends AlarmEvent {
  final String fromName;
  const AlarmTriggered(this.fromName);
  @override
  List<Object?> get props => [fromName];
}

/// The user acknowledged — stop ringing.
class AlarmDismissed extends AlarmEvent {
  const AlarmDismissed();
}

// ─────────────────────────── State ───────────────────────────
class AlarmState extends Equatable {
  final bool ringing;
  final String fromName;
  const AlarmState({this.ringing = false, this.fromName = 'A contact'});

  @override
  List<Object?> get props => [ringing, fromName];
}

// ─────────────────────────── Bloc ───────────────────────────
class AlarmBloc extends Bloc<AlarmEvent, AlarmState> {
  final AlarmService _alarm;
  final NotificationService _notifications;
  StreamSubscription<String>? _incomingSub;

  AlarmBloc({
    required AlarmService alarm,
    required NotificationService notifications,
    required Stream<String> incoming,
  })  : _alarm = alarm,
        _notifications = notifications,
        super(const AlarmState()) {
    on<AlarmTriggered>(_onTriggered);
    on<AlarmDismissed>(_onDismissed);
    // A received LAN broadcast becomes an AlarmTriggered event.
    _incomingSub = incoming.listen((name) => add(AlarmTriggered(name)));
  }

  Future<void> _onTriggered(AlarmTriggered e, Emitter<AlarmState> emit) async {
    if (state.ringing) return;
    await _notifications.showSosFullScreen({'fromName': e.fromName});
    await _alarm.start({'fromName': e.fromName});
    emit(AlarmState(ringing: true, fromName: e.fromName));
  }

  Future<void> _onDismissed(AlarmDismissed e, Emitter<AlarmState> emit) async {
    await _alarm.stop();
    await _notifications.cancelSos();
    emit(const AlarmState(ringing: false));
  }

  @override
  Future<void> close() {
    _incomingSub?.cancel();
    return super.close();
  }
}
