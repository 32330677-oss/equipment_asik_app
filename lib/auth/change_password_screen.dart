import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/theme.dart';
import '../widgets/ui.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});
  final bool forced;
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;

  String? _policy(String? v) {
    final p = v ?? '';
    if (p.length < 10) return 'At least 10 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'Use letters and at least one digit';
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Auth.I.changePassword(_current.text, _next.text);
      if (!mounted) return;
      showSnack(context, 'Password changed.');
      if (!widget.forced) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change password'),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced) TextButton.icon(onPressed: () => Auth.I.logout(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.lock_reset_rounded, size: 44, color: AppColors.navy),
                    const SizedBox(height: 10),
                    Text(widget.forced ? 'Choose your own password' : 'Change your password',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      widget.forced
                          ? 'You signed in with a temporary password. Set a new one to continue.'
                          : 'At least 10 characters, with letters and a digit.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _current,
                      obscureText: true,
                      decoration: InputDecoration(labelText: widget.forced ? 'Temporary password' : 'Current password'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'New password'), validator: _policy),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _again,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Repeat new password'),
                      validator: (v) => v != _next.text ? 'Passwords do not match' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving...' : 'Save password')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
