import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/theme.dart';
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
        if (!a.signedIn && a.offline) return _Offline(message: a.offlineMessage!);
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

/// Signed in, but the server cannot be reached (no internet on site). The sign-in is kept; the app retries by itself.
class _Offline extends StatefulWidget {
  const _Offline({required this.message});
  final String message;
  @override
  State<_Offline> createState() => _OfflineState();
}

class _OfflineState extends State<_Offline> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await Auth.I.retryConnection();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/images/logo.png', width: 120),
                const SizedBox(height: 28),
                const Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.standby),
                const SizedBox(height: 12),
                const Text('No connection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(widget.message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 6),
                const Text('You are still signed in. The app tries again by itself every 15 seconds.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _retry,
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Auth.I.logout(), child: const Text('Sign out')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
