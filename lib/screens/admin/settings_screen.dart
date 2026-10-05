import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = Loadable<List<Json>>();

  static const _groups = <String, List<String>>{
    'Paper sheets & payroll': ['eq_payroll_requires_paper_match', 'eq_paper_tolerance_minutes', 'eq_timesheet_blank_rows', 'payroll_finalize_admin_only', 'eq_default_currency'],
    'Attendance checks': ['eq_meter_tolerance_pct', 'eq_long_session_review_hours', 'week_gate_enabled', 'week_start_day', 'eq_shift_continuity_minutes'],
    'General': ['company_name', 'app_time_zone', 'eq_live_refresh_seconds'],
  };
  static const _titles = <String, String>{
    'eq_payroll_requires_paper_match': 'Pay only rows matched with the signed paper',
    'eq_paper_tolerance_minutes': 'Paper tolerance (minutes)',
    'eq_timesheet_blank_rows': 'Blank rows on the printed sheet',
    'payroll_finalize_admin_only': 'Only Admin can finalize / mark paid',
    'eq_default_currency': 'Default contract currency',
    'eq_meter_tolerance_pct': 'Hour-meter tolerance (%)',
    'eq_long_session_review_hours': 'Long session warning (hours)',
    'week_gate_enabled': 'Block submit while last week has drafts',
    'week_start_day': 'Week starts on',
    'company_name': 'Company name on documents',
    'app_time_zone': 'Business time zone',
    'eq_live_refresh_seconds': 'Live board refresh (seconds)',
    'eq_shift_continuity_minutes': 'Continuous shifts: max gap (minutes)',
  };
  static const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/settings');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _save(String key, String value) async {
    try {
      await Api.I.put('/settings/$key', {'value': value});
      if (mounted) showSnack(context, 'Saved.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _editor(Json s) {
    final key = s.str('setting_key');
    final value = s.str('setting_value');
    final type = s.str('type');
    if (type == 'bool') {
      return Switch(value: value == 'true', onChanged: (v) => _save(key, v ? 'true' : 'false'));
    }
    if (key == 'week_start_day') {
      return Dropdown<String>(
        label: '', value: value, width: 160,
        items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: '$i', child: Text(_days[i]))],
        onChanged: (v) { if (v != null) _save(key, v); },
      );
    }
    if (type == 'enum') {
      return Dropdown<String>(
        label: '', value: value, width: 140,
        items: [for (final v in (s['values'] as List? ?? const [])) DropdownMenuItem(value: '$v', child: Text('$v'))],
        onChanged: (v) { if (v != null) _save(key, v); },
      );
    }
    return OutlinedButton(
      onPressed: () async {
        final v = await promptText(context, _titles[key] ?? key, label: type == 'int' ? 'Value (${s.str('min')} - ${s.str('max')})' : 'Value', initial: value, maxLines: 1);
        if (v != null) _save(key, v);
      },
      child: Text(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byKey = {for (final s in _s.data ?? <Json>[]) s.str('setting_key'): s};
    return PageBody(
      onRefresh: _load,
      maxWidth: 900,
      children: [
        const PageHeader(title: 'Settings', subtitle: 'Rules used by attendance, paper sheets and payroll. Every change is audited.'),
        if (_s.loading && _s.data == null) const LoadingView()
        else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
        else
          for (final g in _groups.entries) ...[
            SectionCard(
              title: g.key,
              child: Column(children: [
                for (final k in g.value)
                  if (byKey[k] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_titles[k] ?? k, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(byKey[k]!.str('description'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        _editor(byKey[k]!),
                      ]),
                    ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}
