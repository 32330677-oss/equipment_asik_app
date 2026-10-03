import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _s = Loadable<List<Json>>();
  String? _table;
  int _page = 1;
  int _total = 0;
  static const _pageSize = 50;
  static const _tables = ['users', 'sites', 'site_supervisors', 'settings', 'eq_vendors', 'eq_vendor_contracts', 'eq_equipment', 'eq_operators',
    'eq_rate_cards', 'eq_site_assignments', 'eq_attendance', 'eq_downtime_periods', 'eq_fuel_issues', 'eq_adjustments', 'eq_timesheets',
    'eq_timesheet_scans', 'eq_paper_checks', 'eq_payroll_batches', 'eq_attendance_corrections'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      final r = await Api.I.request('GET', '/audit', query: {'table': _table, 'page': _page, 'page_size': _pageSize});
      _s.data = asJsonList(r['data']);
      _total = asJson(r['meta']).intv('total');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  void _show(Json r) {
    String pretty(dynamic v) => v == null ? '-' : const JsonEncoder.withIndent('  ').convert(v);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.str('action_type')} - ${r.str('table_name')} #${r.str('record_id')}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow('When', r.str('created_at')),
              InfoRow('User', r.str('user_name', '-')),
              if (r.strOrNull('reason') != null) InfoRow('Reason', r.str('reason')),
              const SizedBox(height: 10),
              const Text('Before', style: TextStyle(fontWeight: FontWeight.w700)),
              _code(pretty(r['old_values'])),
              const SizedBox(height: 10),
              const Text('After', style: TextStyle(fontWeight: FontWeight.w700)),
              _code(pretty(r['new_values'])),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _code(String s) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
        child: SelectableText(s, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final pages = (_total / _pageSize).ceil().clamp(1, 100000);
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Audit log', subtitle: '$_total recorded changes', actions: [
          Dropdown<String?>(
            label: 'Table', value: _table, width: 230,
            items: [const DropdownMenuItem(value: null, child: Text('All tables')), for (final t in _tables) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) { _table = v; _page = 1; _load(); },
          ),
        ]),
        if (_s.loading && _s.data == null) const LoadingView()
        else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
        else ...[
          TableCard(
            empty: 'No changes recorded.',
            columns: const [DataColumn(label: Text('When')), DataColumn(label: Text('User')), DataColumn(label: Text('Action')), DataColumn(label: Text('Record')), DataColumn(label: Text('Reason'))],
            rows: [
              for (final r in rows)
                DataRow(onSelectChanged: (_) => _show(r), cells: [
                  DataCell(Text('${Fmt.date(r.str('created_at'))} ${Fmt.time(r.str('created_at'))}')),
                  DataCell(Text(r.str('user_name', 'system'))),
                  DataCell(Pill(r.str('action_type'), color: AppColors.info)),
                  DataCell(Text('${r.str('table_name')} #${r.str('record_id')}')),
                  DataCell(SizedBox(width: 260, child: Text(r.str('reason'), overflow: TextOverflow.ellipsis))),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('Page $_page / $pages'),
            IconButton(onPressed: _page > 1 ? () { _page--; _load(); } : null, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: _page < pages ? () { _page++; _load(); } : null, icon: const Icon(Icons.chevron_right)),
          ]),
        ],
      ],
    );
  }
}
