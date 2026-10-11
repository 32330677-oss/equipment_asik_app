import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/theme.dart';

/// Sign in. Wide screens: brand panel on the left, form card on the right.
/// Phones: brand header on top, the form card overlapping it.
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

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await Auth.I.login(_user.text, _pass.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.surface)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.navy, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.breakdown)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.breakdown, width: 1.6)),
      );

  Widget _banner() {
    final isError = _error != null;
    final color = isError ? AppColors.breakdown : AppColors.standby;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(_error ?? widget.message!, style: const TextStyle(color: AppColors.ink, height: 1.35))),
      ]),
    );
  }

  Widget _formCard({required bool compact}) {
    final h = compact ? 22.0 : 36.0;
    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: EdgeInsets.fromLTRB(h, compact ? 26 : 38, h, compact ? 22 : 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: AppColors.navyDark.withValues(alpha: 0.10), blurRadius: 40, offset: const Offset(0, 18)),
          BoxShadow(color: AppColors.navyDark.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(width: 28, height: 4, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('SECURE SIGN IN', style: TextStyle(color: AppColors.gold, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
            ]),
            const SizedBox(height: 14),
            const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.15)),
            const SizedBox(height: 6),
            const Text('Sign in with the account given by your administrator.', style: TextStyle(color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 26),
            if ((_error ?? widget.message) != null) _banner(),
            TextFormField(
              controller: _user,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _deco('Username', Icons.person_outline_rounded),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pass,
              obscureText: !_show,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onFieldSubmitted: (_) => _submit(),
              decoration: _deco('Password', Icons.lock_outline_rounded,
                  suffix: IconButton(
                    tooltip: _show ? 'Hide password' : 'Show password',
                    icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.muted),
                    onPressed: () => setState(() => _show = !_show),
                  )),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w700),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('Sign in'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 20),
                      ]),
              ),
            ),
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 14),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.help_outline_rounded, size: 18, color: AppColors.muted),
              SizedBox(width: 8),
              Expanded(
                child: Text('Forgot your password? Ask the administrator to reset it.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// The logo (dark on white) sits on a white card.
  Widget _logoCard(double width) => Container(
        padding: EdgeInsets.symmetric(horizontal: width * 0.14, vertical: width * 0.10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width > 80 ? 18 : 12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Image.asset('assets/images/logo.png', width: width),
      );

  Widget _feature(IconData icon, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: const Color(0xFFE2C77F), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(color: Color(0xFFB9C1DF), fontSize: 13, height: 1.35)),
            ]),
          ),
        ]),
      );

  Widget _brandPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.navyDark, AppColors.navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: CustomPaint(
        painter: _BrandPattern(),
        // short windows: the panel scrolls instead of overflowing
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(56, 48, 56, 36),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _logoCard(118),
                    const Spacer(),
                    const SizedBox(height: 32),
                    Text(AppConfig.companyName.toUpperCase(),
                        style: const TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 2.2)),
                    const SizedBox(height: 10),
                    const Text(AppConfig.appName, style: TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(height: 14),
                    Container(width: 72, height: 4, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 18),
                    const Text('Rented machinery on site, from the first check-in to the vendor payment.',
                        style: TextStyle(color: Color(0xFFD5DAEC), fontSize: 17, height: 1.5)),
                    const SizedBox(height: 30),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(children: [
                        _feature(Icons.fact_check_rounded, 'Attendance & live board', 'Check-in, downtime and approvals per site and shift.'),
                        _feature(Icons.receipt_long_rounded, 'Payroll & invoices', 'Finalized batches, vendor and machine invoices, payments.'),
                        _feature(Icons.account_balance_wallet_rounded, 'Statements', 'Statement of account and billing history at any time.'),
                      ]),
                    ),
                    const Spacer(),
                    const SizedBox(height: 16),
                    Text('© ${DateTime.now().year} ${AppConfig.companyName}', style: const TextStyle(color: Color(0xFF8E98BF), fontSize: 12.5)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phone() {
    const radius = BorderRadius.vertical(bottom: Radius.circular(28));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.navyDark, AppColors.navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: radius,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: CustomPaint(
                painter: _BrandPattern(),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    // the bottom space is covered by the form card
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
                    child: Row(children: [
                      _logoCard(64),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(AppConfig.appName, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                          SizedBox(height: 2),
                          Text(AppConfig.companyName, style: TextStyle(color: Color(0xFFB9C1DF), fontSize: 12.5)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -80),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: _formCard(compact: true)),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (!wide) return _phone();
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(children: [
        Expanded(flex: 6, child: _brandPanel()),
        Expanded(
          flex: 5,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: _formCard(compact: false),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Soft blueprint pattern: a fine grid, two large rings and three gold diagonals.
class _BrandPattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.06);
    final r = math.max(size.width, size.height);
    final c = Offset(size.width * 1.02, size.height * 0.08);
    canvas.drawCircle(c, r * 0.42, ring);
    canvas.drawCircle(c, r * 0.30, ring);
    final gold = Paint()
      ..strokeWidth = 2
      ..color = AppColors.gold.withValues(alpha: 0.18);
    for (var i = 0; i < 3; i++) {
      final o = i * 16.0;
      canvas.drawLine(Offset(size.width - 220 + o, size.height), Offset(size.width + o, size.height - 220), gold);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
