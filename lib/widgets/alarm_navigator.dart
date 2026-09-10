import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/alarm/alarm_bloc.dart';
import '../main.dart' show appNavigatorKey;
import '../screens/alarm_screen.dart';
import '../services/push_service.dart';

/// Watches [AlarmBloc] and pushes/pops the full-screen alarm route as the
/// ringing state changes. Keeps navigation out of the Bloc itself.
class AlarmNavigator extends StatefulWidget {
  final Widget child;
  const AlarmNavigator({super.key, required this.child});

  @override
  State<AlarmNavigator> createState() => _AlarmNavigatorState();
}

class _AlarmNavigatorState extends State<AlarmNavigator> {
  bool _routeOpen = false;

  @override
  void initState() {
    super.initState();
    // A ring may have been recorded while the app was terminated (background
    // isolate). Now that AlarmBloc is subscribed, deliver it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.deliverPendingRing();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AlarmBloc, AlarmState>(
      listenWhen: (prev, curr) => prev.ringing != curr.ringing,
      listener: (context, state) {
        final nav = appNavigatorKey.currentState;
        if (nav == null) return;
        if (state.ringing && !_routeOpen) {
          _routeOpen = true;
          nav
              .pushNamed(AlarmScreen.routeName)
              .then((_) => _routeOpen = false);
        } else if (!state.ringing && _routeOpen) {
          _routeOpen = false;
          nav.popUntil((r) => r.isFirst);
        }
      },
      child: widget.child,
    );
  }
}
