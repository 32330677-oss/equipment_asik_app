import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Admin review of machine attendance: approve / reject in bulk, anomalies, edits.
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
  bool _lateOnly = false;
  String _from = Fmt.dateOf(Fmt.now().subtract(const Duration(days: 30)));
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
        'status': _status, 'anomaly': _anomaly, 'paper_status': _paper, 'from': _from, 'to': _to, 'page_size': 200, if (_lateOnly) 'late': 'only',
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
    final office = Auth.I.isAdmin || Auth.I.isAccountant;
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
            DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
          ], onChanged: (v) { _status = v; _load(); }),
          FilterChip(
            label: const Text('Late entries only'),
            avatar: const Icon(Icons.history_toggle_off_rounded, size: 18),
            selected: _lateOnly,
            onSelected: (v) { _lateOnly = v; _load(); },
          ),
          if (office)
            OutlinedButton.icon(
              onPressed: () async {
                await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const OfficeChangeRequestsSheet());
                _load();
              },
              icon: const Icon(Icons.forward_to_inbox_rounded),
              label: const Text('Change requests'),
            ),
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
          KpiTile(label: 'Late entries', value: '${_counts.intv('late_entries')}', color: AppColors.standby, icon: Icons.history_toggle_off_rounded),
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
                color: r.flag('edited_after_approval') ? WidgetStatePropertyAll(AppColors.edited.withValues(alpha: 0.07)) : null,
                onSelectChanged: admin && r.str('status') == 'Submitted'
                    ? (v) => setState(() => v == true ? _selected.add(r.intv('eq_attendance_id')) : _selected.remove(r.intv('eq_attendance_id')))
                    : null,
                cells: [
                  DataCell(Text(Fmt.dayLabel(r.str('record_date'))), onTap: () => _open(r)),
                  DataCell(Text('${r.str('site_code')} ${r.str('shift_type') == 'Night' ? '(N)' : ''}'), onTap: () => _open(r)),
                  DataCell(Text('${r.str('equipment_code')}  ${r.machineType}', style: const TextStyle(fontWeight: FontWeight.w700)), onTap: () => _open(r)),
                  DataCell(
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        WorkflowPill(r.str('status')),
                        if (r.flag('edited_after_approval'))
                          Tooltip(
                            message: 'Edited after approval: ${r.str('admin_edit_reason')}',
                            child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.edit_note_rounded, size: 18, color: AppColors.edited)),
                          ),
                        if (r.flag('late_entry'))
                          Tooltip(
                            message: 'Late entry: ${r.intv('late_entry_days')} days after the day${r.strOrNull('late_entry_reason') == null ? '' : ' - ${r.str('late_entry_reason')}'}',
                            child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.history_toggle_off_rounded, size: 18, color: AppColors.standby)),
                          ),
                        if (r.intv('pending_change_requests') > 0)
                          const Tooltip(
                            message: 'The supervisor asked for a change',
                            child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.forward_to_inbox_rounded, size: 18, color: AppColors.info)),
                          ),
                      ]),
                      onTap: () => _open(r)),
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

/// Details of one row with the office actions: acknowledge anomaly, edit (several fields at once), void, standby hours,
/// supervisors' change requests, full history. A day inside an invoice handed over to finance is locked.
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

  bool get _locked => _r?.intOrNull('locked_by_batch_id') != null;

  /// Monthly machines: the Admin/Accountant give the standby hours paid for this row (no %), max = hours per day.
  /// The first decision needs no reason; changing or clearing a decision does.
  Future<void> _standbyHours() async {
    final r = _r!;
    final sc = r.obj('standby_credit');
    final max = sc.dblOrNull('max_hours') ?? 0;
    final cur = r.intOrNull('standby_credit_minutes');
    final v = await promptText(context, 'Standby hours to pay (max ${max.toStringAsFixed(2)} h)',
        label: 'Hours (0 to ${max.toStringAsFixed(2)}; empty = not decided)', initial: cur == null ? '' : (cur / 60).toStringAsFixed(2), required: false, maxLines: 1);
    if (v == null || !mounted) return;
    final clear = v.isEmpty;
    final hours = clear ? null : double.tryParse(v.replaceAll(',', '.'));
    if (!clear && (hours == null || hours < 0 || hours > max)) {
      showError(context, ApiException(null, 'VALIDATION', 'Type a number of hours between 0 and ${max.toStringAsFixed(2)}.'));
      return;
    }
    if (clear && cur == null) return;
    final changing = cur != null;
    final note = await promptText(context, changing ? 'Why change the hours already decided?' : 'Why these hours? (optional)',
        label: 'Note', required: changing, minLength: changing ? 5 : 0);
    if (note == null || !mounted) return;
    await _do(() => Api.I.patch('/equipment/admin/attendance/${widget.id}/standby-credit', {'hours': hours, if (note.isNotEmpty) 'note': note}),
        clear ? 'Cleared.' : 'Standby hours saved.');
  }

  /// Current value of a field: the pending change if any, else the row.
  Object? _cur(Json r, Map<String, dynamic> changes, String key) => changes.containsKey(key) ? changes[key] : r[key];

  /// Several fields in one go: a direct office edit (reason optional; an Approved row then shows as "edited after
  /// approval"). A draft invoice of the row then asks to be recalculated; an issued one is brought up to date by itself
  /// with the same number. Refused while the invoice is handed over to finance (14 Oct 2026).
  Future<void> _edit() async {
    final r = _r!;
    final changes = <String, dynamic>{};
    while (true) {
      final status = '${_cur(r, changes, 'day_status') ?? ''}';
      final working = status == 'Working';
      final inT = _cur(r, changes, 'check_in_time') as String?;
      final outT = _cur(r, changes, 'check_out_time') as String?;
      String mark(String key, String text) => changes.containsKey(key) ? '$text  (changed)' : text;
      final what = await pickFromList(context, 'Edit row: what is wrong?', [
        if (changes.isNotEmpty) PickOption('done', 'Done: continue with ${changes.length} change(s)', changes.keys.map(fieldLabel).join(', ')),
        PickOption('status', 'Day status', mark('day_status', status)),
        if (working || inT != null) PickOption('in', 'Check-in time', mark('check_in_time', Fmt.time(inT))),
        if (working || outT != null) PickOption('out', 'Check-out time', mark('check_out_time', Fmt.timeOn(outT, r.str('record_date')))),
        if (working) PickOption('downtime', 'Breaks / breakdown / standby periods', mark('downtime', '${(changes['downtime'] as List?)?.length ?? r.list('downtime').length} period(s)')),
        if (working) PickOption('operator', 'Operator', mark('operator_id', r.str('operator_name', '-'))),
        if (working) PickOption('meter', 'Meter readings', mark('meter_start', '${_cur(r, changes, 'meter_start') ?? '-'} -> ${_cur(r, changes, 'meter_end') ?? '-'}')),
        PickOption('work', 'Work done', mark('work_description', '${_cur(r, changes, 'work_description') ?? '-'}')),
        PickOption('remarks', 'Remarks', mark('remarks', '${_cur(r, changes, 'remarks') ?? '-'}')),
      ]);
      if (!mounted) return;
      if (what == null) {
        if (changes.isEmpty) return;
        final discard = await confirmDialog(context, 'Discard ${changes.length} change(s)?', 'Nothing has been saved yet.', confirm: 'Discard', danger: true);
        if (discard || !mounted) return;
        continue;
      }
      if (what.value == 'done') break;
      if (what.value == 'cancel_row') {
        changes['cancel_row'] = true;
        break;
      }
      await _askField(r, '${what.value}', changes);
      if (!mounted) return;
    }
    if (changes.isEmpty || !mounted) return;
    {
      final approved = r.str('status') == 'Approved';
      final notes = [
        if (approved) 'The row stays Approved and is marked as edited after approval.',
        if (_coveredText(r) != null) _coveredText(r)!,
      ];
      final reason = await promptText(context, approved ? 'Why change an approved row? (optional)' : 'Reason (optional)',
          label: 'Reason (optional)', required: false, help: notes.isEmpty ? null : notes.join(' '));
      if (reason == null) return;
      await _do(() => Api.I.patch('/equipment/admin/attendance/${widget.id}', {...changes, if (reason.trim().isNotEmpty) 'reason': reason.trim()}),
          approved ? 'Saved. The row stays Approved and is marked as edited after approval.' : 'Saved.');
    }
  }

  /// Asks the new value of one field and puts it in [changes].
  Future<void> _askField(Json r, String what, Map<String, dynamic> changes) async {
    final inT = _cur(r, changes, 'check_in_time') as String?;
    final outT = _cur(r, changes, 'check_out_time') as String?;
    switch (what) {
      case 'status': {
        final st = await pickFromList(context, 'Day status', [
          for (final x in const ['Working', 'Standby', 'Breakdown', 'Absent', 'Holiday'])
            if (x != _cur(r, changes, 'day_status')) PickOption(x, x),
        ]);
        if (st == null || !mounted) return;
        changes['day_status'] = st.value;
        if (st.value == 'Working' && inT == null) {
          final a = await pickDateTime(context, initial: '${r.str('record_date')} 07:00');
          if (a == null || !mounted) return;
          final b = await pickDateTime(context, initial: '${r.str('record_date')} 17:00');
          if (b == null) return;
          changes['check_in_time'] = a;
          changes['check_out_time'] = b;
        }
        if (st.value == 'Absent' || st.value == 'Holiday') {
          changes['check_in_time'] = null;
          changes['check_out_time'] = null;
        }
      }
      case 'in': {
        final v = await pickDateTime(context, initial: inT ?? '${r.str('record_date')} 07:00');
        if (v == null) return;
        changes['check_in_time'] = v;
      }
      case 'out': {
        final v = await pickDateTime(context, initial: outT ?? '${r.str('record_date')} 17:00');
        if (v == null) return;
        changes['check_out_time'] = v;
      }
      case 'downtime': {
        final list = await _editDowntime(r);
        if (list == null) return;
        changes['downtime'] = list;
      }
      case 'operator': {
        final ops = await Lookups.operators(r.intv('vendor_id'));
        if (!mounted) return;
        final op = await pickFromList(context, 'Operator', ops);
        if (op == null) return;
        changes['operator_id'] = op.value;
      }
      case 'meter': {
        final a = await promptText(context, 'Meter start', label: 'Meter start', initial: '${_cur(r, changes, 'meter_start') ?? ''}', maxLines: 1);
        if (a == null || !mounted) return;
        final b = await promptText(context, 'Meter end', label: 'Meter end', initial: '${_cur(r, changes, 'meter_end') ?? ''}', maxLines: 1);
        if (b == null) return;
        final ms = double.tryParse(a.replaceAll(',', '.'));
        final me = double.tryParse(b.replaceAll(',', '.'));
        if (ms == null || me == null) {
          if (mounted) showError(context, ApiException(null, 'VALIDATION', 'Type numbers for the meter readings.'));
          return;
        }
        changes['meter_start'] = ms;
        changes['meter_end'] = me;
      }
      case 'work': {
        final v = await promptText(context, 'Work done', label: 'Work done', initial: '${_cur(r, changes, 'work_description') ?? ''}', required: false);
        if (v == null) return;
        changes['work_description'] = v;
      }
      default: {
        final v = await promptText(context, 'Remarks', label: 'Remarks', initial: '${_cur(r, changes, 'remarks') ?? ''}', required: false);
        if (v == null) return;
        changes['remarks'] = v;
      }
    }
  }

  /// Edits the whole list of downtime periods of a Working row; returns the new list (replaces the old one).
  Future<List<Map<String, dynamic>>?> _editDowntime(Json r) async {
    final items = <Map<String, dynamic>>[
      for (final p in r.list('downtime'))
        if (p.strOrNull('end_time') != null)
          {'downtime_type': p.str('downtime_type'), 'start_time': p.str('start_time').substring(0, 16), 'end_time': p.str('end_time').substring(0, 16), 'reason': p.strOrNull('reason')},
    ];
    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Downtime periods'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No period.', style: TextStyle(color: AppColors.muted))),
              for (final p in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p['downtime_type']}  ${Fmt.time(p['start_time'])} - ${Fmt.time(p['end_time'])}'),
                  subtitle: p['reason'] == null ? null : Text('${p['reason']}'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.breakdown), onPressed: () => set(() => items.remove(p))),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add period'),
                  onPressed: () async {
                    final t = await pickFromList(ctx, 'Type', [for (final x in const ['Break', 'Refuel', 'Breakdown', 'Standby']) PickOption(x, x)]);
                    if (t == null || !ctx.mounted) return;
                    final a = await pickDateTime(ctx, initial: r.strOrNull('check_in_time') ?? '${r.str('record_date')} 10:00', askDate: false);
                    if (a == null || !ctx.mounted) return;
                    final b = await pickDateTime(ctx, initial: a, askDate: false);
                    if (b == null || !ctx.mounted) return;
                    final why = await promptText(ctx, 'Reason (optional)', label: 'Reason', required: false);
                    if (why == null) return;
                    set(() => items.add({'downtime_type': t.value, 'start_time': a, 'end_time': b, 'reason': why.isEmpty ? null : why}));
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, items), child: const Text('Use these periods')),
          ],
        ),
      ),
    );
  }

  /// A row that should not exist, (not in an invoice handed over to finance): kept as Cancelled (never deleted).
  Future<void> _void() async {
    final r = _r!;
    final reason = await promptText(context, 'Void this row?',
        label: 'Why should this row not exist? (optional)',
        required: false,
        confirm: 'Void the row',
        help: 'The row is kept in the history as Cancelled and is not paid.'
            '${_coveredText(r) == null ? '' : ' ${_coveredText(r)}'}');
    if (reason == null) return;
    await _do(() => Api.I.patch('/equipment/admin/attendance/${widget.id}/cancel', {if (reason.trim().isNotEmpty) 'reason': reason.trim()}),
        'Row voided (kept as Cancelled).');
  }

  Future<void> _decideRequest(Json cr, {required bool approve}) async {
    final id = cr.intv('change_request_id');
    if (!approve) {
      final note = await promptText(context, 'Reject the request', label: 'What should the supervisor know?', minLength: 3, confirm: 'Reject');
      if (note == null) return;
      await _do(() => Api.I.patch('/equipment/admin/change-requests/$id/reject', {'note': note}), 'Request rejected.');
      return;
    }
    final note = await promptText(context, 'Apply the requested change?', label: 'Note (optional)', required: false, confirm: 'Apply');
    if (note == null || !mounted) return;
    await _do(() => Api.I.patch('/equipment/admin/change-requests/$id/approve', {if (note.isNotEmpty) 'note': note}), 'Change applied to the row.');
  }

  /// What a change of this row does to its invoice (null: in no invoice).
  String? _coveredText(Json r) {
    final c = r.obj('covered_by');
    if (c.isEmpty) return null;
    final name = c.strOrNull('invoice_no') ?? 'draft invoice #${c.str('eq_batch_id')}';
    return switch (c.str('state')) {
      'draft' => 'This day is in $name: the draft then asks to be recalculated.',
      'issued' => 'This day is in $name (issued, still in the office): the invoice is brought up to date with the same number.',
      'returned' => 'This day is in $name, withdrawn from finance: re-issue it afterwards (new number).',
      _ => 'This day is in $name.',
    };
  }

  Future<void> _approve() async {
    try {
      final r = asJson(await Api.I.post('/equipment/admin/attendance/approve', {'ids': [widget.id]}));
      final skipped = r.list('skipped');
      if (mounted) {
        showSnack(context, skipped.isEmpty ? 'Row approved.' : 'Not approved: ${skipped.first.str('message', skipped.first.str('reason').replaceAll('_', ' ').toLowerCase())}',
            error: skipped.isNotEmpty);
      }
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reject() async {
    final why = await promptText(context, 'Reject this row?', label: 'Why? (the supervisor sees it and fixes the row)', minLength: 3, confirm: 'Reject');
    if (why == null) return;
    await _do(() => Api.I.post('/equipment/admin/attendance/reject', {'ids': [widget.id], 'notes': why}), 'Row rejected.');
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final admin = Auth.I.isAdmin;
    final office = Auth.I.isAdmin || Auth.I.isAccountant;
    final cancelled = r?.str('status') == 'Cancelled';
    final canGiveStandby = office && !_locked && !cancelled && (r?.obj('standby_credit').flag('applies') ?? false);
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
                      if (cancelled)
                        NoticeBox(
                          color: AppColors.neutral,
                          icon: Icons.block_rounded,
                          title: 'Cancelled',
                          text: '${r.str('cancel_reason', '-')}${r.strOrNull('cancelled_at') == null ? '' : '  (${Fmt.date(r.str('cancelled_at'))})'}. Kept for the history, never paid.',
                        ),
                      if (r.flag('late_entry'))
                        NoticeBox(
                          color: AppColors.standby,
                          icon: Icons.history_toggle_off_rounded,
                          title: 'Late entry: recorded ${r.intv('late_entry_days')} days after the day',
                          text: r.strOrNull('late_entry_reason') ?? 'The supervisor gave no reason.',
                        ),
                      if (r.strOrNull('anomaly_code') != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.standby.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.standby.withValues(alpha: 0.3))),
                          child: Row(children: [
                            const Icon(Icons.report_rounded, color: AppColors.standby),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${r.str('anomaly_code').replaceAll('_', ' ')}: ${r.str('anomaly_detail')}${r.flag('anomaly_acknowledged') ? '  (acknowledged)' : ''}')),
                            if (admin && !r.flag('anomaly_acknowledged') && !_locked)
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
                      if (canGiveStandby)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.standby.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.standby.withValues(alpha: 0.3))),
                          child: Row(children: [
                            const Icon(Icons.hourglass_bottom_rounded, color: AppColors.standby),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r.intOrNull('standby_credit_minutes') == null
                                  ? 'Monthly machine with standby: decide how many hours to pay (needed before invoicing).'
                                  : 'Standby hours paid: ${Fmt.hoursFromMinutes(r.intv('standby_credit_minutes'))} h${r.strOrNull('standby_credit_note') == null ? '' : ' - ${r.str('standby_credit_note')}'}'),
                            ),
                            TextButton(onPressed: _standbyHours, child: Text(r.intOrNull('standby_credit_minutes') == null ? 'Set hours' : 'Change')),
                          ]),
                        ),
                      if (r.flag('edited_after_approval'))
                        NoticeBox(
                          color: AppColors.edited,
                          icon: Icons.edit_note_rounded,
                          text: 'Edited after approval${r.strOrNull('admin_edit_at') == null ? '' : ' on ${Fmt.date(r.str('admin_edit_at'))}'}: ${r.str('admin_edit_reason')}',
                        ),
                      if (!_locked && _coveredText(r) != null)
                        NoticeBox(icon: Icons.receipt_long_rounded, text: _coveredText(r)!),
                      if (_locked)
                        NoticeBox(
                          color: AppColors.navy,
                          icon: Icons.lock_rounded,
                          title: r.str('locked_by_state') == 'returned' ? 'Invoice withdrawn from finance' : 'Invoice handed over to finance',
                          text: '${r.str('locked_reason', 'This day is in an invoice that is locked.')} '
                              'A difference can also be settled with a debit / credit note (Invoices).',
                        ),
                      if (office && !cancelled && !_locked)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (admin && r.str('status') == 'Submitted') ...[
                            FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.check_circle_rounded), label: const Text('Approve')),
                            OutlinedButton.icon(
                              onPressed: _reject,
                              icon: const Icon(Icons.cancel_rounded, color: AppColors.breakdown),
                              label: const Text('Reject', style: TextStyle(color: AppColors.breakdown)),
                            ),
                          ],
                          OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_rounded), label: const Text('Edit')),
                          OutlinedButton.icon(
                            onPressed: _void,
                            icon: const Icon(Icons.block_rounded, color: AppColors.breakdown),
                            label: const Text('Void row', style: TextStyle(color: AppColors.breakdown)),
                          ),
                        ]),
                      if (r.list('change_requests').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SectionCard(title: 'Requests from the supervisor', child: Column(children: [
                          for (final cr in r.list('change_requests')) _changeRequestTile(cr, office),
                        ])),
                      ],
                      if (r.list('corrections').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SectionCard(title: 'Official corrections (before 14 Oct 2026)', child: Column(children: [
                          for (final c in r.list('corrections'))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(children: [
                                Text('#${c.str('correction_id')}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                Expanded(child: Text(c.str('reason'), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                WorkflowPill(c.str('request_status')),
                              ]),
                            ),
                        ])),
                      ],
                      const SizedBox(height: 12),
                      SectionCard(title: 'History', child: Column(children: [
                        for (final h in r.list('history'))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(width: 130, child: Text('${Fmt.date(h.str('created_at'))} ${Fmt.time(h.str('created_at'))}', style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${h.str('action_type').replaceAll('_', ' ')} by ${h.str('user_name', '-')}${h.strOrNull('reason') == null ? '' : ' - ${h.str('reason')}'}', style: const TextStyle(fontSize: 13)),
                                  for (final line in changedFieldLines(h['changed_fields']))
                                    Text(line, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                  if ((h.strOrNull('payroll_effect') ?? 'none') != 'none')
                                    Text('Invoice: ${h.str('payroll_effect').replaceFirst('stale:', 'invoice #').replaceFirst('correction:', 'correction #')}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.info)),
                                ]),
                              ),
                            ]),
                          ),
                      ])),
                    ]),
      ),
    );
  }

  Widget _changeRequestTile(Json cr, bool office) {
    final pending = cr.str('status') == 'Pending';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('#${cr.str('change_request_id')} by ${cr.str('requested_by')}  ·  ${Fmt.date(cr.str('requested_at'))}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          Pill(cr.str('status'), color: pending ? AppColors.info : cr.str('status') == 'Applied' ? AppColors.working : AppColors.neutral),
        ]),
        for (final e in cr.obj('proposed_changes').entries) Text('${fieldLabel(e.key)}: ${valueLabel(e.value)}', style: const TextStyle(fontSize: 13)),
        Text('Reason: ${cr.str('reason')}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if (cr.strOrNull('decision_note') != null) Text('Decision: ${cr.str('decision_note')}', style: const TextStyle(fontSize: 12.5)),
        if (pending && office)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: [
              TextButton(onPressed: () => _decideRequest(cr, approve: false), child: const Text('Reject')),
              FilledButton.tonal(onPressed: () => _decideRequest(cr, approve: true), child: const Text('Apply')),
            ]),
          ),
      ]),
    );
  }
}

/// Pending change requests of all sites (office): open one to see the row and decide.
class OfficeChangeRequestsSheet extends StatefulWidget {
  const OfficeChangeRequestsSheet({super.key});
  @override
  State<OfficeChangeRequestsSheet> createState() => _OfficeChangeRequestsSheetState();
}

class _OfficeChangeRequestsSheetState extends State<OfficeChangeRequestsSheet> {
  final _s = Loadable<List<Json>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/admin/change-requests', query: {'status': 'Pending'});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: _s.loading && _s.data == null
            ? const LoadingView()
            : _s.error != null
                ? ErrorView(error: _s.error!, onRetry: _load)
                : ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
                    const Text('Change requests from supervisors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Rows they cannot change themselves (approved rows, days before their assignment). Open one to apply or reject it.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    if (rows.isEmpty) const EmptyView(text: 'No request waiting.', icon: Icons.forward_to_inbox_rounded),
                    for (final cr in rows)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${cr.str('equipment_code')} · ${cr.str('site_code')} · ${Fmt.dayLabel(cr.str('record_date'))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${cr.obj('proposed_changes').keys.map(fieldLabel).join(', ')}\n${cr.str('requested_by')}: ${cr.str('reason')}', maxLines: 3, overflow: TextOverflow.ellipsis),
                          isThreeLine: true,
                          trailing: WorkflowPill(cr.str('row_status')),
                          onTap: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) => AttendanceDetailSheet(id: cr.intv('eq_attendance_id')),
                            );
                            _load();
                          },
                        ),
                      ),
                  ]),
      ),
    );
  }
}
