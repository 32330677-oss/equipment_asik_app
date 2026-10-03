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
    if (Api.I.hasToken) {
      try {
        await refreshMe();
      } catch (_) {
        await Api.I.setToken(null);
        user = null;
      }
    }
    ready = true;
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
    await Api.I.post('/auth/change-password', {'current_password': current, 'new_password': next});
    await refreshMe();
  }

  Future<void> logout([String? message]) async {
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
