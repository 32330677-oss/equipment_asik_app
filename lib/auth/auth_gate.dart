import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../screens/supervisor/sup_home_screen.dart';
import '../shell/app_shell.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

/// Root: splash -> login -> forced password change -> home by role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Auth.I,
      builder: (context, _) {
        final a = Auth.I;
        if (!a.ready) return const _Splash();
        if (!a.signedIn) return LoginScreen(message: a.lastMessage);
        if (a.mustChangePassword) return const ChangePasswordScreen(forced: true);
        if (a.isSupervisor) return const SupHomeScreen();
        if (a.isAdmin || a.isAccountant) return const AppShell();
        return const LoginScreen(message: 'This role is not supported by the app.');
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/images/logo.png', width: 140),
          const SizedBox(height: 24),
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
        ]),
      ),
    );
  }
}
