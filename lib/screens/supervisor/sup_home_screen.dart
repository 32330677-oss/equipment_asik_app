import 'package:flutter/material.dart';

import '../../auth/change_password_screen.dart';
import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/config.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'day_board_screen.dart';

/// Supervisor home: today's sites (one tap to the day board), rejected rows, paper sheets.
class SupHomeScreen extends StatefulWidget {
  const SupHomeScreen({super.key});
  @override
  State<SupHomeScreen> createState() => _SupHomeScreenState();
}

class _SupHomeScreenState extends State<SupHomeScreen> {
  String _date = Fmt.today();
  final _s = Loadable<List<Json>>();
  int _rejected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/my-sites', query: {'date': _date});
      try {
        _rejected = (await Api.I.getList('/equipment/attendance/rejected')).length;
      } catch (_) {}
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _openBoard(Json s) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => DayBoardScreen(siteId: s.intv('site_id'), shift: s.str('shift_type', 'Day'), date: _date, title: s.str('site_code'))),
    );
    _load();
  }

  Future<void> _go(Widget page) async {
    Navigator.pop(context);
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sites = _s.data ?? <Json>[];
    final isToday = _date == Fmt.today();
    final hour = Fmt.now().hour;
    final greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/images/logo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(child: Text(AppConfig.appName, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      drawer: _drawer(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.navy, AppColors.navyDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$greet, ${Auth.I.name.split(' ').first}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(isToday ? 'Today · ${Fmt.dayLabel(_date)}' : 'Recording ${Fmt.dayLabel(_date)}', style: const TextStyle(color: Color(0xFFD0D5E8))),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _heroButton(Icons.calendar_month_rounded, isToday ? 'Another day' : 'Back to today', () async {
                          if (!isToday) {
                            setState(() => _date = Fmt.today());
                            _load();
                            return;
                          }
                          final d = await pickDate(context, initial: _date, last: Fmt.today());
                          if (d != null) {
                            setState(() => _date = d);
                            _load();
                          }
                        }),
                      ]),
                    ]),
                  ),
                  if (_rejected > 0) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFFDECEA),
                      child: ListTile(
                        leading: const Icon(Icons.undo_rounded, color: AppColors.breakdown),
                        title: Text('$_rejected row(s) sent back by the office', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.breakdown)),
                        subtitle: const Text('Fix them and send them again'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const RejectedRowsScreen()));
                          _load();
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('YOUR SITES', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12)),
                  const SizedBox(height: 8),
                  if (_s.loading && _s.data == null)
                    const LoadingView()
                  else if (_s.error != null)
                    ErrorView(error: _s.error!, onRetry: _load)
                  else if (sites.isEmpty)
                    const Card(
                      child: EmptyView(
                        text: 'You are not assigned to a site on this day.\nAsk the office to add you as supervisor of a site.',
                        icon: Icons.location_off_rounded,
                      ),
                    )
                  else
                    for (final s in sites) _siteCard(s),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroButton(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _siteCard(Json s) {
    final night = s.str('shift_type') == 'Night';
    final n = s.intOrNull('deployed_machines');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openBoard(s),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: (night ? AppColors.navy : AppColors.gold).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(night ? Icons.nightlight_round : Icons.wb_sunny_rounded, color: night ? AppColors.navy : AppColors.gold, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.str('site_code'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(s.str('site_name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 4),
                Text('${night ? 'Night shift' : 'Day shift'}${n == null ? '' : '  ·  $n machine(s)'}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }

  Widget _drawer() {
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.navy,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 26, backgroundColor: AppColors.gold, child: Text(Auth.I.name.isEmpty ? '?' : Auth.I.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
              const SizedBox(height: 10),
              Text(Auth.I.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              Text(Auth.I.role, style: const TextStyle(color: Color(0xFFD0D5E8))),
            ]),
          ),
          ListTile(leading: const Icon(Icons.home_rounded), title: const Text('My sites'), onTap: () => Navigator.pop(context)),
          ListTile(
            leading: const Icon(Icons.undo_rounded),
            title: const Text('Rejected rows'),
            trailing: _rejected == 0 ? null : Pill('$_rejected', color: AppColors.breakdown),
            onTap: () => _go(const RejectedRowsScreen()),
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.lock_reset_rounded), title: const Text('Change password'), onTap: () => _go(const ChangePasswordScreen())),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.breakdown),
            title: const Text('Sign out', style: TextStyle(color: AppColors.breakdown)),
            onTap: () {
              Navigator.pop(context);
              Auth.I.logout();
            },
          ),
          const Spacer(),
          const Padding(padding: EdgeInsets.all(16), child: Text(AppConfig.companyName, style: TextStyle(color: AppColors.muted, fontSize: 12))),
        ]),
      ),
    );
  }
}

/// Rows the office sent back, across all the supervisor's sites.
class RejectedRowsScreen extends StatefulWidget {
  const RejectedRowsScreen({super.key});
  @override
  State<RejectedRowsScreen> createState() => _RejectedRowsScreenState();
}

class _RejectedRowsScreenState extends State<RejectedRowsScreen> {
  final _s = Loadable<List<Json>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/attendance/rejected');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Rejected rows')),
      body: _s.loading && _s.data == null
          ? const LoadingView()
          : _s.error != null
              ? ErrorView(error: _s.error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    if (rows.isEmpty) const Card(child: EmptyView(text: 'Nothing to fix. Well done.', icon: Icons.verified_rounded)),
                    for (final r in rows)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              useSafeArea: true,
                              builder: (_) => RowDetailSheet(att: r, vendorId: r.intOrNull('vendor_id')),
                            );
                            _load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('${r.str('equipment_code')} · ${r.str('site_code')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                                Text(Fmt.dayLabel(r.str('record_date')), style: const TextStyle(color: AppColors.muted)),
                              ]),
                              const SizedBox(height: 6),
                              Text('Office: ${r.str('admin_rejection_notes', '-')}', style: const TextStyle(color: AppColors.breakdown, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text('${r.str('day_status')}  ·  ${r.strOrNull('check_in_time') == null ? '-' : '${Fmt.time(r.str('check_in_time'))} → ${Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))}'}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
    );
  }
}
