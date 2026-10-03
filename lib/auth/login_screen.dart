import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});
  final String? message;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await Auth.I.login(_user.text, _pass.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!wide) Center(child: Image.asset('assets/images/logo.png', width: 130)),
              if (!wide) const SizedBox(height: 18),
              const Text('Sign in', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 4),
              const Text('Use the account given by your administrator.', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 24),
              if ((_error ?? widget.message) != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_error != null ? AppColors.breakdown : AppColors.standby).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: (_error != null ? AppColors.breakdown : AppColors.standby).withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(_error != null ? Icons.error_outline : Icons.info_outline,
                        color: _error != null ? AppColors.breakdown : AppColors.standby),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error ?? widget.message!)),
                  ]),
                ),
              TextFormField(
                controller: _user,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pass,
                obscureText: !_show,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 18),
              const Text('Forgot your password? Ask the administrator to reset it.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
    if (!wide) return Scaffold(backgroundColor: Colors.white, body: SafeArea(child: form));
    return Scaffold(
      body: Row(children: [
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.navyDark, AppColors.navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(48),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Image.asset('assets/images/logo.png', width: 120),
              ),
              const Spacer(),
              const Text(AppConfig.appName, style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Container(width: 64, height: 4, color: AppColors.gold),
              const SizedBox(height: 16),
              const Text('Rented machinery on site: attendance, signed monthly sheets,\nlive board and vendor payroll - in one place.',
                  style: TextStyle(color: Color(0xFFD5DAEC), fontSize: 16, height: 1.5)),
              const Spacer(),
              const Text(AppConfig.companyName, style: TextStyle(color: Color(0xFF9AA4C8), fontSize: 13)),
            ]),
          ),
        ),
        Expanded(flex: 4, child: Container(color: Colors.white, child: form)),
      ]),
    );
  }
}
