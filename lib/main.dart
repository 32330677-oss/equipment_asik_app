import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/auth_gate.dart';
import 'core/api.dart';
import 'core/auth.dart';
import 'core/config.dart';
import 'core/theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Api.I.onSessionEnded = (message) async {
    if (!Auth.I.signedIn) return;
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    await Auth.I.logout(message);
  };
  Api.I.onPasswordChangeRequired = () {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    Auth.I.forcePasswordChange();
  };
  Auth.I.bootstrap();
  runApp(const EquipmentFlowApp());
}

class EquipmentFlowApp extends StatelessWidget {
  const EquipmentFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light(),
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}
