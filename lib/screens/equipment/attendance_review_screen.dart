import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Admin review of machine attendance: approve / reject in bulk, anomalies, edits, corrections.
class AttendanceReviewScreen extends StatefulWidget {
  const AttendanceReviewScreen({super.key});
  @override
  State<AttendanceReviewScreen> createState() => _AttendanceReviewScreenState();
}

class _AttendanceReviewScreenState extends State<AttendanceReviewScreen> {
  final _s = Loadable<List<Json>>();
  Json _counts = {};
  String? _status = 'Submitted';
  String? _anomaly;
  String? _paper;
  String _from = Fmt.dateOf(DateTime.now().subtract(const Duration(days: 30)));
  String _to = Fmt.today();
  final Set<int> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      final r = await Api.I.request('GET', '/equipment/admin/attendance', query: {
        'status': _status, 'anomaly': _anomaly, 'paper_status': _paper, 'from': _from, 'to': _to, 'page_size': 200,
      });
      _s.data = asJsonList(r['data']);
      _counts = asJson(r['meta']).obj('counts');
      _selected.removeWhere((id) => !_s.data!.any((x) => x.intv('eq_attendance_id') == id));
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      final r = asJson(await Api.I.post('/equipment/admin/attendance/approve', {'ids': _selected.toList()}));
      final skipped = r.list('skipped');
      if (!mounted) return;
      showSnack(context, '${(r['approved'] as List?)?.length ?? 0} approved'
          '${skipped.isEmpty ? '' : ', ${skipped.length} skipped (${skipped.map((s) => s.str('reason')).toSet().join(', ')})'}.',
          error: skipped.isNotEmpty);
      _selected.clear();
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final notes = await promptText(context, 'Reject ${_selected.length} row(s)', label: 'What must the supervisor fix?', confirm: 'Reject');
    if (notes == null) return;
    try {
      await Api.I.post('/equipment/admin/attendance/reject', {'ids': _selected.toList(), 'notes': notes});
      _selected.clear();
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final admin = Auth.I.isAdmin;
    final submittedRows = rows.where((r) => r.str('status') == 'Submitted').toList();
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Attendance review', subtitle: 'Approve the days submitted by the site supervisors', actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final f = await pickDate(context, initial: _from);
              if (f == null || !context.mounted) return;
              final t = await pickDate(context, initial: _to);
              if (t == null) return;
              _from = f; _to = t; _load();
            },
            icon: const Icon(Icons.date_range_rounded),
            label: Text('${Fmt.date(_from)} - ${Fmt.date(_to)}'),
          ),
          Dropdown<String?>(label: 'Status', value: _status, width: 150, items: const [
            DropdownMenuItem(value: null, child: Text('All')),
            DropdownMenuItem(value: 'Submitted', child: Text('Submitted')),
            DropdownMenuItem(value: 'Draft', child: Text('Draft')),
            DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
            DropdownMenuItem(value: 'Approved', child: Text('Approved')),
          ], onChanged: (v) { _status = v; _load(); }),
          Dropdown<String?>(label: 'Anomalies', value: _anomaly, width: 170, items: const [
            DropdownMenuItem(value: null, child: Text('Any')),
            DropdownMenuItem(value: 'unacknowledged', child: Text('To acknowledge')),
            DropdownMenuItem(value: 'only', child: Text('With anomaly')),
            DropdownMenuItem(value: 'none', child: Text('Without')),
          ], onChanged: (v) { _anomaly = v; _load(); }),
          Dropdown<String?>(label: 'Paper', value: _paper, width: 150, items: const [
            DropdownMenuItem(value: null, child: Text('Any')),
            DropdownMenuItem(value: 'Pending', child: Text('Pending')),
            DropdownMenuItem(value: 'Matched', child: Text('Matched')),
            DropdownMenuItem(value: 'Mismatch', child: Text('Mismatch')),
            DropdownMenuItem(value: 'Missing', child: Text('Missing')),
          ], onChanged: (v) { _paper = v; _load(); }),
        ]),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'Waiting approval', value: '${_counts.intv('submitted')}', color: AppColors.info, icon: Icons.inbox_rounded),
          KpiTile(label: 'Anomalies to check', value: '${_counts.intv('unacknowledged_anomalies')}', color: AppColors.standby, icon: Icons.report_rounded),
          KpiTile(label: 'Drafts (not submitted)', value: '${_counts.intv('draft')}', color: AppColors.muted, icon: Icons.edit_note_rounded),
          KpiTile(label: 'Rejected', value: '${_counts.intv('rejected')}', color: AppColors.breakdown, icon: Icons.undo_rounded),
        ]),
        const SizedBox(height: 14),
        if (admin && _selected.isNotEmpty)
          Card(
            color: const Color(0xFFEEF2FF),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Text('${_selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                OutlinedButton.icon(onPressed: _busy ? null : _reject, icon: const Icon(Icons.undo_rounded), label: const Text('Reject')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: _busy ? null : _approve, icon: const Icon(Icons.check_rounded), label: const Text('Approve')),
              ]),
            ),
          ),
        if (admin && _selected.isNotEmpty) const SizedBox(height: 10),
        if (_s.loading && _s.data == null) const LoadingView()
        else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
        else TableCard(
          showCheckbox: admin,
          empty: _status == 'Submitted' ? 'Nothing waiting for approval.' : 'No rows for these filters.',
          columns: const [
            DataColumn(label: Text('Date')), DataColumn(label: Text('Site')), DataColumn(label: Text('Machine')),
            DataColumn(label: Text('Status')), DataColumn(label: Text('Day')), DataColumn(label: Text('In - Out')),
            DataColumn(label: Text('Work h'), numeric: true), DataColumn(label: Text('Breakdown h'), numeric: true),
            DataColumn(label: Text('Standby h'), numeric: true), DataColumn(label: Text('Operator')),
            DataColumn(label: Text('Checks')), DataColumn(label: Text('Sheet')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                selected: _selected.contains(r.intv('eq_attendance_id')),
                onSelectChanged: admin && r.str('status') == 'Submitted'
                    ? (v) => setState(() => v == true ? _selected.add(r.intv('eq_attendance_id')) : _selected.remove(r.intv('eq_attendance_id')))
                    : null,
                cells: [
                  DataCell(Text(Fmt.dayLabel(r.str('record_date'))), onTap: () => _open(r)),
                  DataCell(Text('${r.str('site_code')} ${r.str('shift_type') == 'Night' ? '(N)' : ''}'), onTap: () => _open(r)),
                  DataCell(Text('${r.str('equipment_code')}  ${r.str('type_name')}', style: const TextStyle(fontWeight: FontWeight.w700)), onTap: () => _open(r)),
                  DataCell(WorkflowPill(r.str('status')), onTap: () => _open(r)),
                  DataCell(StatePill(r.str('day_status') == 'Working' ? 'Working' : r.str('day_status')), onTap: () => _open(r)),
                  DataCell(Text(r.strOrNull('check_in_time') == null ? '-' : '${Fmt.time(r.str('check_in_time'))} - ${Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))}'), onTap: () => _open(r)),
                  DataCell(Text(Fmt.hoursFromMinutes(r.intOrNull('working_minutes'))), onTap: () => _open(r)),
                  DataCell(Text(r.intv('breakdown_minutes') == 0 ? '' : Fmt.hoursFromMinutes(r.intv('breakdown_minutes'))), onTap: () => _open(r)),
                  DataCell(Text(r.intv('standby_minutes') == 0 ? '' : Fmt.hoursFromMinutes(r.intv('standby_minutes'))), onTap: () => _open(r)),
                  DataCell(Text(r.str('operator_name', '-')), onTap: () => _open(r)),
                  DataCell(r.strOrNull('anomaly_code') == null
                      ? const Text('')
                      : Pill(r.str('anomaly_code').replaceAll('_', ' '), color: r.strOrNull('anomaly_ack_at') == null ? AppColors.standby : AppColors.neutral, icon: Icons.report_rounded),
                      onTap: () => _open(r)),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [Text('#${r.str('sheet_row_no')} '), PaperPill(r.str('paper_status'))]), onTap: () => _open(r)),
                ],
              ),
          ],
        ),
        if (admin && submittedRows.isNotEmpty && _selected.isEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _selected.addAll(submittedRows.map((r) => r.intv('eq_attendance_id')))),
              icon: const Icon(Icons.select_all_rounded),
              label: Text('Select all ${submittedRows.length} submitted'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _open(Json r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AttendanceDetailSheet(id: r.intv('eq_attendance_id')),
    );
    _load();
  }
}

/// Details of one row with Admin actions (acknowledge anomaly, edit, correction).
class AttendanceDetailSheet extends StatefulWidget {
  const AttendanceDetailSheet({super.key, required this.id});
  final int id;
  @override
  State<AttendanceDetailSheet> createState() => _AttendanceDetailSheetState();
}

class _AttendanceDetailSheetState extends State<AttendanceDetailSheet> {
  Json? _r;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.getObj('/equipment/admin/attendance/${widget.id}');
      if (mounted) setState(() { _r = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _do(Future<void> Function() fn, String ok) async {
    try {
      await fn();
      if (mounted) showSnack(context, ok);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit({required bool correction}) async {
    final r = _r!;
    String? inT = r.strOrNull('check_in_time');
    String? outT = r.strOrNull('check_out_time');
    final changes = <String, dynamic>{};
    final what = await pickFromList(context, correction ? 'Correct (finalized period)' : 'Edit row', [
      if (r.str('day_status') == 'Working' || inT != null) PickOption('in', 'Check-in time', Fmt.time(inT)),
      if (r.str('day_status') == 'Working' || outT != null) PickOption('out', 'Check-out time', Fmt.timeOn(outT, r.str('record_date'))),
      PickOption('remarks', 'Remarks', r.str('remarks', '-')),
    ]);
    if (what == null || !mounted) return;
    if (what.value == 'in') {
      final v = await pickDateTime(context, initial: inT ?? '${r.str('record_date')} 07:00');
      if (v == null) return;
      changes['check_in_time'] = v;
    } else if (what.value == 'out') {
      final v = await pickDateTime(context, initial: outT ?? '${r.str('record_date')} 17:00');
      if (v == null) return;
      changes['check_out_time'] = v;
    } else {
      final v = await promptText(context, 'Remarks', label: 'Remarks', initial: r.str('remarks'), required: false);
      if (v == null) return;
      changes['remarks'] = v;
    }
    if (!mounted) return;
    if (correction) {
      final reason = await promptText(context, 'Reason of the correction', label: 'Reason (kept in the correction log)');
      if (reason == null) return;
      await _do(() => Api.I.post('/equipment/admin/attendance/${widget.id}/correction', {'reason': reason, 'changes': changes}),
          'Corrected. The finalized payroll was not changed; settle it with an adjustment.');
    } else {
      await _do(() => Api.I.patch('/equipment/admin/attendance/${widget.id}', changes), 'Saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final admin = Auth.I.isAdmin;
    return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : r == null
                  ? const LoadingView()
                  : ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
                      Row(children: [
                        Expanded(child: Text('${r.str('equipment_code')} - ${Fmt.dayLabel(r.str('record_date'))}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                        WorkflowPill(r.str('status')),
                        const SizedBox(width: 6),
                        PaperPill(r.str('paper_status')),
                      ]),
                      const SizedBox(height: 12),
                      if (r.strOrNull('anomaly_code') != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.standby.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.standby.withValues(alpha: 0.3))),
                          child: Row(children: [
                            const Icon(Icons.report_rounded, color: AppColors.standby),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${r.str('anomaly_code').replaceAll('_', ' ')}: ${r.str('anomaly_detail')}${r.flag('anomaly_acknowledged') ? '  (acknowledged)' : ''}')),
                            if (admin && !r.flag('anomaly_acknowledged'))
                              TextButton(
                                onPressed: () async {
                                  final note = await promptText(context, 'Acknowledge anomaly', label: 'What did you check?');
                                  if (note != null) _do(() => Api.I.post('/equipment/admin/attendance/${widget.id}/ack-anomaly', {'note': note}), 'Acknowledged.');
                                },
                                child: const Text('Acknowledge'),
                              ),
                          ]),
                        ),
                      SectionCard(child: Column(children: [
                        InfoRow('Day status', r.str('day_status')),
                        InfoRow('Operator', r.str('operator_name', '-')),
                        InfoRow('Check-in', r.strOrNull('check_in_time') == null ? '-' : Fmt.time(r.str('check_in_time'))),
                        InfoRow('Check-out', Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))),
                        InfoRow('Gross / work', '${Fmt.duration(r.intOrNull('gross_minutes'))}  /  ${Fmt.duration(r.intOrNull('working_minutes'))}'),
                        InfoRow('Breaks / breakdown / standby', '${Fmt.duration(r.intv('break_minutes'))}  /  ${Fmt.duration(r.intv('breakdown_minutes'))}  /  ${Fmt.duration(r.intv('standby_minutes'))}'),
                        InfoRow('Meter', '${r.str('meter_start', '-')}  ->  ${r.str('meter_end', '-')}'),
                        InfoRow('Work done', r.str('work_description')),
                        InfoRow('Remarks', r.str('remarks')),
                        InfoRow('Paper sheet', '${r.obj('sheet').str('sheet_code')}  row #${r.obj('sheet').str('sheet_row_no')}'),
                        if (r.strOrNull('admin_rejection_notes') != null) InfoRow('Rejection note', r.str('admin_rejection_notes')),
                      ])),
                      const SizedBox(height: 12),
                      if (r.list('downtime').isNotEmpty)
                        SectionCard(title: 'Downtime', child: Column(children: [
                          for (final p in r.list('downtime'))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: StatePill(p.str('downtime_type') == 'Break' || p.str('downtime_type') == 'Refuel' ? 'OnBreak' : p.str('downtime_type')),
                              title: Text('${Fmt.time(p.strOrNull('start_time'))} - ${p.strOrNull('end_time') == null ? 'open' : Fmt.time(p.strOrNull('end_time'))}  (${p.str('downtime_type')})'),
                              subtitle: p.strOrNull('reason') == null ? null : Text(p.str('reason')),
                            ),
                        ])),
                      if (r.list('downtime').isNotEmpty) const SizedBox(height: 12),
                      if (admin)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(onPressed: () => _edit(correction: false), icon: const Icon(Icons.edit_rounded), label: const Text('Edit')),
                          OutlinedButton.icon(onPressed: () => _edit(correction: true), icon: const Icon(Icons.gavel_rounded), label: const Text('Correction (finalized period)')),
                        ]),
                      const SizedBox(height: 12),
                      SectionCard(title: 'History', child: Column(children: [
                        for (final h in r.list('history'))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              SizedBox(width: 130, child: Text('${Fmt.date(h.str('created_at'))} ${Fmt.time(h.str('created_at'))}', style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                              Expanded(child: Text('${h.str('action_type').replaceAll('_', ' ')} by ${h.str('user_name', '-')}${h.strOrNull('reason') == null ? '' : ' - ${h.str('reason')}'}', style: const TextStyle(fontSize: 13))),
                            ]),
                          ),
                      ])),
                    ]),
      ),
    );
  }
}
