import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'json.dart';

/// Current user + session. Listen to it to rebuild the root of the app.
class Auth extends ChangeNotifier {
  Auth._();
  static final Auth I = Auth._();

  bool ready = false;
  Json? user;
  List<Json> sites = <Json>[];
  String? today;
  String? lastMessage;

  /// Signed in on this device but the server could not be reached at start (no internet on site):
  /// the sign-in is KEPT; the app shows a "no connection" screen and retries by itself.
  String? offlineMessage;
  bool get offline => offlineMessage != null;
  Timer? _retry;

  bool get signedIn => user != null;
  String get role => user?.str('role') ?? '';
  bool get isAdmin => role == 'Admin';
  bool get isAccountant => role == 'Accountant';
  bool get isSupervisor => role == 'Supervisor';
  bool get canSeeMoney => isAdmin || isAccountant;
  bool get mustChangePassword => user?.flag('must_change_password') ?? false;
  String get name => user?.str('full_name') ?? '';
  int get userId => user?.intv('user_id') ?? 0;

  Future<void> bootstrap() async {
    await Api.I.loadToken();
    if (Api.I.hasToken) await _restore();
    ready = true;
    notifyListeners();
  }

  /// Restores the session. Only a refusal by the server (401) signs the user out; a network problem keeps the
  /// sign-in and retries every 15 seconds.
  Future<void> _restore() async {
    try {
      await refreshMe();
      offlineMessage = null;
      _retry?.cancel();
    } on ApiException catch (e) {
      if (e.isNetwork || (e.status ?? 0) >= 500) {
        offlineMessage = e.message;
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 15), retryConnection);
      } else {
        offlineMessage = null;
        await Api.I.setToken(null);
        user = null;
        if (e.status == 401) lastMessage = 'Please sign in again.';
      }
    } catch (_) {
      offlineMessage = 'Cannot open your account right now. Try again.';
    }
  }

  /// "Try again" on the no-connection screen (also called automatically).
  Future<void> retryConnection() async {
    if (!Api.I.hasToken) return;
    await _restore();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    final d = await Api.I.getObj('/auth/me');
    user = d.obj('user');
    sites = d.list('sites');
    today = d.strOrNull('today');
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final d = asJson(await Api.I.post('/auth/login', {'username': username.trim(), 'password': password}));
    await Api.I.setToken(d.str('token'));
    lastMessage = null;
    await refreshMe();
  }

  Future<void> changePassword(String current, String next) async {
    final d = asJson(await Api.I.post('/auth/change-password', {'current_password': current, 'new_password': next}));
    // the server ends every old session; keep this device signed in with the new token
    final t = d.strOrNull('token');
    if (t != null && t.isNotEmpty) await Api.I.setToken(t);
    await refreshMe();
  }

  Future<void> logout([String? message]) async {
    _retry?.cancel();
    offlineMessage = null;
    await Api.I.setToken(null);
    user = null;
    sites = <Json>[];
    lastMessage = message;
    notifyListeners();
  }

  void forcePasswordChange() {
    if (user != null) {
      user = {...user!, 'must_change_password': true};
      notifyListeners();
    }
  }
}
