import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bloc/alarm/alarm_bloc.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/profile/profile_bloc.dart';
import 'bloc/contacts/contacts_bloc.dart';
import 'bloc/sos/sos_bloc.dart';
import 'services/alarm_service.dart';
import 'services/api_service.dart';
import 'services/contacts_store.dart';
import 'services/emergency_call_service.dart';
import 'services/emergency_sms_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'screens/alarm_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/alarm_navigator.dart';

/// Global navigator key so the AlarmNavigator and notification taps can route
/// without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase + fetch the FCM token. Wrapped so the app still runs on
  // a platform whose Firebase config isn't set up yet (e.g. iOS without a
  // GoogleService-Info.plist); Android reads config from google-services.json.
  try {
    await Firebase.initializeApp();
    await PushService.instance.init();
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  await NotificationService.instance.init();
  runApp(const SosApp());
}

class SosApp extends StatelessWidget {
  const SosApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Base dark theme, with every text style switched to Inter. Because the
    // ambient default text style becomes Inter, custom styles that don't set a
    // fontFamily (AppTextStyles, inline field styles) inherit Inter too.
    final base = ThemeData(
      colorSchemeSeed: Colors.red,
      useMaterial3: true,
      brightness: Brightness.dark,
    );
    final theme = base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AuthBloc(ApiService())),
        BlocProvider(
            create: (context) => ProfileBloc(context.read<AuthBloc>().api)),
        BlocProvider(
          create: (context) => ContactsBloc(
            context.read<AuthBloc>().api,
            ContactsStore.instance,
          ),
        ),
        BlocProvider(
          create: (context) => SosBloc(
            api: context.read<AuthBloc>().api,
            contacts: ContactsStore.instance,
            calls: EmergencyCallService.instance,
            sms: EmergencySmsService.instance,
          )..add(const SosDndChecked()),
        ),
        BlocProvider(
          // Eager: the ring subscription must be live before any push arrives,
          // otherwise a foreground ring is emitted before anyone is listening.
          lazy: false,
          create: (_) => AlarmBloc(
            alarm: AlarmService.instance,
            notifications: NotificationService.instance,
            // Ring commands now arrive via FCM (backend push), not the LAN.
            incoming: PushService.instance.incoming,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'SOS Emergency (Demo)',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: theme,
        // AlarmNavigator sits above every route so it can show the alarm from
        // anywhere when an SOS arrives.
        builder: (context, child) =>
            AlarmNavigator(child: child ?? const SizedBox.shrink()),
        home: const SplashScreen(),
        routes: {
          AlarmScreen.routeName: (_) => const AlarmScreen(),
        },
      ),
    );
  }
}
