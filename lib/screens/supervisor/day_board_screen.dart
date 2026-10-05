import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';
import 'action_sheets.dart';

/// The supervisor's working screen for one site, shift and day:
/// one card per deployed machine with ONE obvious next action, and a submit bar.
class DayBoardScreen extends StatefulWidget {
  const DayBoardScreen({super.key, required this.siteId, required this.shift, required this.date, this.title});
  final int siteId;
  final String shift;
  final String date;
  final String? title;

  @override
  State<DayBoardScreen> createState() => _DayBoardScreenState();
}

class _DayBoardScreenState extends State<DayBoardScreen> {
  late String _date = widget.date;
  Json? _d;
  Object? _error;
  bool _loading = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // refresh the running durations every minute
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await Api.I.getObj('/equipment/attendance/site/${widget.siteId}', query: {'date': _date, 'shift': widget.shift});
      if (mounted) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _after(Future<bool?> action) async {
    final ok = await action;
    if (ok == true) _load();
  }

  Future<void> _submit() async {
    final d = _d!;
    final s = d.obj('submit');
    final notArrived = d.list('machines').where((m) => m.obj('attendance').isEmpty).map((m) => m.str('equipment_code')).toList();
    final ok = await confirmDialog(
      context,
      'Submit ${Fmt.dayLabel(_date)}?',
      '${s.intv('draft_rows')} row(s) will be sent to the office for approval. You cannot change them after, unless they are rejected.'
          '${notArrived.isEmpty ? '' : '\n\nNo record for: ${notArrived.join(', ')}. Mark them Absent first if they did not come.'}',
      confirm: 'Submit day',
    );
    if (!ok) return;
    try {
      final r = asJson(await Api.I.post('/equipment/attendance/submit', {'site_id': widget.siteId, 'shift_type': widget.shift, 'record_date': _date}));
      if (!mounted) return;
      final missing = (r['machines_without_row'] as List?)?.cast<Object>() ?? const [];
      showSnack(context, '${r.intv('submitted')} row(s) submitted.${missing.isEmpty ? '' : ' Without record: ${missing.join(', ')}.'}', error: missing.isNotEmpty);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pickDate() async {
    final d = await pickDate(context, initial: _date, last: Fmt.today());
    if (d == null) return;
    setState(() { _date = d; _d = null; });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final isToday = _date == Fmt.today();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d == null ? (widget.title ?? 'Site') : '${d.obj('site').str('site_code')}  ${d.obj('site').str('site_name')}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('${widget.shift == 'Night' ? 'Night shift' : 'Day shift'}  ·  ${isToday ? 'Today' : Fmt.dayLabel(_date)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        actions: [
          IconButton(tooltip: 'Change day', onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') {
                PdfViewScreen.open(context,
                    title: 'Daily report $_date',
                    fileName: 'daily-${widget.siteId}-$_date.pdf',
                    load: () => Api.I.getBytes('/equipment/reports/daily.pdf', query: {'date': _date, 'site_id': widget.siteId}));
              }
              if (v == 'refresh') _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Refresh'))),
              PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('Daily report PDF'))),
            ],
          ),
        ],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      bottomNavigationBar: d == null ? null : _SubmitBar(submit: d.obj('submit'), onSubmit: _submit),
      body: _error != null && d == null
          ? ErrorView(error: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (!isToday)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: AppColors.standby.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                                child: Row(children: [
                                  const Icon(Icons.history_rounded, color: AppColors.standby),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text('You are recording ${Fmt.dayLabel(_date)}, not today.', style: const TextStyle(fontWeight: FontWeight.w600))),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _date = Fmt.today());
                                      _load();
                                    },
                                    child: const Text('Go to today'),
                                  ),
                                ]),
                              ),
                            _SummaryStrip(summary: d.obj('summary')),
                            const SizedBox(height: 12),
                            if (d.list('machines').isEmpty)
                              const Card(child: EmptyView(text: 'No machine is deployed on this site and shift for this day.', icon: Icons.precision_manufacturing_rounded))
                            else
                              for (final m in d.list('machines'))
                                _MachineCard(
                                  m: m,
                                  date: _date,
                                  onAction: (fut) => _after(fut),
                                  siteId: widget.siteId,
                                  shift: widget.shift,
                                  onChanged: _load,
                                ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});
  final Json summary;

  @override
  Widget build(BuildContext context) {
    Widget chip(String state, String key) {
      final s = StateStyle.of(state);
      final n = summary.intv(key);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: n == 0 ? Colors.white : s.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: n == 0 ? AppColors.line : s.color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(s.icon, size: 18, color: n == 0 ? AppColors.neutral : s.color),
          const SizedBox(width: 6),
          Text('$n', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: n == 0 ? AppColors.muted : s.color)),
          const SizedBox(width: 4),
          Text(s.label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in const [
          ('Working', 'working'), ('OnBreak', 'on_break'), ('Breakdown', 'breakdown'), ('Standby', 'standby'),
          ('NotArrived', 'not_arrived'), ('Finished', 'finished'), ('Absent', 'absent'),
        ])
          Padding(padding: const EdgeInsets.only(right: 8), child: chip(e.$1, e.$2)),
      ]),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({required this.m, required this.date, required this.onAction, required this.siteId, required this.shift, required this.onChanged});
  final Json m;
  final String date;
  final int siteId;
  final String shift;
  final void Function(Future<bool?>) onAction;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final att = m.obj('attendance');
    final hasRow = att.isNotEmpty;
    final state = m.str('live_state');
    final style = StateStyle.of(state);
    final status = att.str('status', 'Draft');
    final editable = !hasRow || status == 'Draft' || status == 'Rejected';
    final open = att.objOrNull('open_downtime');
    final recordDate = att.str('record_date', date);

    // running minutes for a working session today
    String? running;
    if (hasRow && att.strOrNull('check_in_time') != null && att.strOrNull('check_out_time') == null) {
      final start = Fmt.parse(att.str('check_in_time'));
      if (start != null) running = Fmt.duration(DateTime.now().difference(start).inMinutes);
    }

    final List<Widget> actions = [];
    if (editable) {
      switch (state) {
        case 'NotArrived':
          actions.add(_primary('Check in', Icons.login_rounded, AppColors.working,
              () => onAction(checkInSheet(context, machine: m, siteId: siteId, shift: shift, date: date))));
          actions.add(_secondary('Did not work', Icons.event_busy_rounded,
              () => onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date))));
          break;
        case 'Working':
          actions.add(_primary('Check out', Icons.logout_rounded, AppColors.navy,
              () => onAction(checkOutSheet(context, machine: m, att: att, date: date, shift: shift))));
          actions.add(_downtimeMenu(context, att));
          break;
        case 'OnBreak':
        case 'Breakdown':
        case 'Standby':
          if (open != null) {
            actions.add(_primary('Resume work', Icons.play_arrow_rounded, AppColors.working,
                () => onAction(endDowntimeSheet(context, att: att, date: recordDate))));
          } else {
            actions.add(_secondary('Change', Icons.edit_calendar_rounded,
                () => onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date, initial: state))));
          }
          break;
        case 'Absent':
        case 'Holiday':
          actions.add(_secondary('It came after all', Icons.login_rounded,
              () => onAction(checkInSheet(context, machine: m, siteId: siteId, shift: shift, date: date))));
          actions.add(_secondary('Change', Icons.edit_calendar_rounded,
              () => onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date, initial: state))));
          break;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasRow ? () => _details(context) : null,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: style.color, width: 5))),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(m.str('equipment_code'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(m.str('type_name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted))),
                  ]),
                  Text(
                    [m.str('vendor_name'), if (m.strOrNull('plate_number') != null) m.str('plate_number')].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                StatePill(state),
                if (hasRow && status != 'Draft') Padding(padding: const EdgeInsets.only(top: 4), child: WorkflowPill(status)),
                if (att.flag('from_previous_day')) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Since yesterday', color: AppColors.standby)),
              ]),
            ]),
            if (hasRow) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 16, runSpacing: 6, children: [
                if (att.strOrNull('check_in_time') != null)
                  _fact(Icons.schedule_rounded, '${Fmt.time(att.str('check_in_time'))} → ${att.strOrNull('check_out_time') == null ? 'now' : Fmt.timeOn(att.strOrNull('check_out_time'), recordDate)}'),
                if (running != null) _fact(Icons.timelapse_rounded, running, color: AppColors.working),
                if (att.strOrNull('check_out_time') != null) _fact(Icons.timer_rounded, '${Fmt.duration(att.intOrNull('working_minutes'))} work'),
                if (att.intv('breakdown_minutes') > 0) _fact(Icons.build_rounded, Fmt.duration(att.intv('breakdown_minutes')), color: AppColors.breakdown),
                if (att.intv('standby_minutes') > 0) _fact(Icons.pause_rounded, Fmt.duration(att.intv('standby_minutes')), color: AppColors.standby),
                _fact(Icons.description_rounded, 'row #${att.obj('sheet').str('sheet_row_no')}'),
              ]),
              if (open != null)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: style.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(style.icon, color: style.color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${open.str('downtime_type')} since ${Fmt.time(open.str('start_time'))}${open.strOrNull('reason') == null ? '' : ' · ${open.str('reason')}'}',
                          style: TextStyle(color: style.color, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              if (att.strOrNull('remarks') != null && open == null && (state == 'Standby' || state == 'Breakdown' || state == 'Absent'))
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(att.str('remarks'), style: const TextStyle(color: AppColors.muted, fontSize: 13))),
              if (status == 'Rejected' && att.strOrNull('admin_rejection_notes') != null)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.breakdown.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Text('Office: ${att.str('admin_rejection_notes')}', style: const TextStyle(color: AppColors.breakdown)),
                ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  i == 0 ? Expanded(child: actions[i]) : actions[i],
                ],
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _fact(IconData icon, String text, {Color color = AppColors.ink}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color == AppColors.ink ? AppColors.muted : color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13.5, color: color, fontWeight: color == AppColors.ink ? FontWeight.w500 : FontWeight.w700)),
      ]);

  Widget _primary(String label, IconData icon, Color color, VoidCallback onTap) => SizedBox(
        height: 48,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _secondary(String label, IconData icon, VoidCallback onTap) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 20), label: Text(label)),
      );

  Widget _downtimeMenu(BuildContext context, Json att) {
    return SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Pause',
        onSelected: (t) => onAction(downtimeSheet(context, att: att, type: t, date: att.str('record_date', date))),
        itemBuilder: (_) => [
          for (final t in const [
            ('Break', Icons.coffee_rounded, AppColors.onBreak, 'Break'),
            ('Refuel', Icons.local_gas_station_rounded, AppColors.onBreak, 'Refuelling'),
            ('Breakdown', Icons.build_circle_rounded, AppColors.breakdown, 'Breakdown'),
            ('Standby', Icons.pause_circle_filled_rounded, AppColors.standby, 'Standby (no work)'),
          ])
            PopupMenuItem(value: t.$1, child: ListTile(leading: Icon(t.$2, color: t.$3), title: Text(t.$4))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pause_rounded, size: 20),
            SizedBox(width: 6),
            Text('Pause', style: TextStyle(fontWeight: FontWeight.w600)),
            Icon(Icons.arrow_drop_down_rounded),
          ]),
        ),
      ),
    );
  }

  Future<void> _details(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => RowDetailSheet(att: m.obj('attendance'), vendorId: m.intv('vendor_id')),
    );
    onChanged();
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.submit, required this.onSubmit});
  final Json submit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final drafts = submit.intv('draft_rows');
    final open = submit.intv('open_rows');
    final gate = submit.obj('week_gate');
    final can = submit.flag('can_submit');
    String msg;
    if (drafts == 0) {
      msg = 'Nothing to submit for this day.';
    } else if (open > 0) {
      msg = '$open machine(s) still working: check them out before submitting.';
    } else if (gate.flag('blocked')) {
      msg = 'Submit last week first (${Fmt.date(gate.str('prev_start'))} - ${Fmt.date(gate.str('prev_end'))}).';
    } else {
      msg = '$drafts row(s) ready to send to the office.';
    }
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Icon(can ? Icons.task_alt_rounded : Icons.info_outline_rounded, color: can ? AppColors.working : AppColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 13.5))),
            const SizedBox(width: 10),
            FilledButton.icon(onPressed: can ? onSubmit : null, icon: const Icon(Icons.send_rounded), label: const Text('Submit day')),
          ]),
        ),
      ),
    );
  }
}

/// Everything about one row: times, downtime list (with delete), edit, delete, resubmit.
class RowDetailSheet extends StatefulWidget {
  const RowDetailSheet({super.key, required this.att, this.vendorId});
  final Json att;
  final int? vendorId;
  @override
  State<RowDetailSheet> createState() => _RowDetailSheetState();
}

class _RowDetailSheetState extends State<RowDetailSheet> {
  late Json _a = widget.att;

  bool get _editable => _a.str('status') == 'Draft' || _a.str('status') == 'Rejected';

  Future<void> _reload() async {
    // the row view comes back from any write; read it through the rejected list or the site board otherwise
    try {
      final d = await Api.I.getObj('/equipment/attendance/site/${_a.intv('site_id')}', query: {'date': _a.str('record_date'), 'shift': _a.str('shift_type')});
      final m = d.list('machines').where((x) => x.obj('attendance').intv('eq_attendance_id') == _a.intv('eq_attendance_id')).toList();
      if (m.isNotEmpty && mounted) setState(() => _a = m.first.obj('attendance'));
    } catch (_) {}
  }

  Future<void> _deleteDowntime(Json p) async {
    final ok = await confirmDialog(context, 'Delete this ${p.str('downtime_type').toLowerCase()}?', 'The period ${Fmt.time(p.str('start_time'))} - ${Fmt.time(p.strOrNull('end_time'))} is removed.', confirm: 'Delete', danger: true);
    if (!ok) return;
    try {
      await Api.I.delete('/equipment/attendance/${_a.intv('eq_attendance_id')}/downtime/${p.intv('downtime_id')}');
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteRow() async {
    final ok = await confirmDialog(context, 'Delete this record?',
        'Row #${_a.obj('sheet').str('sheet_row_no')} of the paper sheet will be marked cancelled. Write "cancelled" on that paper row too.', confirm: 'Delete', danger: true);
    if (!ok) return;
    try {
      await Api.I.delete('/equipment/attendance/${_a.intv('eq_attendance_id')}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _resubmit() async {
    try {
      final r = asJson(await Api.I.patch('/equipment/attendance/${_a.intv('eq_attendance_id')}/resubmit'));
      if (!mounted) return;
      setState(() => _a = r);
      showSnack(context, 'Sent again to the office.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final date = a.str('record_date');
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Expanded(child: Text('${a.str('equipment_code')} · ${Fmt.dayLabel(date)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          StatePill(a.str('live_state', a.str('day_status'))),
          const SizedBox(width: 6),
          WorkflowPill(a.str('status')),
        ]),
        const SizedBox(height: 12),
        if (a.strOrNull('admin_rejection_notes') != null && a.str('status') == 'Rejected')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.breakdown.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Text('Office note: ${a.str('admin_rejection_notes')}', style: const TextStyle(color: AppColors.breakdown, fontWeight: FontWeight.w600)),
          ),
        if (a.strOrNull('anomaly_code') != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.standby.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Text('Check: ${a.str('anomaly_detail', a.str('anomaly_code'))}', style: const TextStyle(color: AppColors.standby)),
          ),
        SectionCard(child: Column(children: [
          InfoRow('Day', a.str('day_status'), width: 120),
          InfoRow('Start / end', a.strOrNull('check_in_time') == null ? '-' : '${Fmt.time(a.str('check_in_time'))} → ${Fmt.timeOn(a.strOrNull('check_out_time'), date)}', width: 120),
          InfoRow('Work time', Fmt.duration(a.intOrNull('working_minutes')), width: 120),
          InfoRow('Meter', '${a.str('meter_start', '-')} → ${a.str('meter_end', '-')}', width: 120),
          InfoRow('Work done', a.str('work_description'), width: 120),
          InfoRow('Remarks', a.str('remarks'), width: 120),
          InfoRow('Paper sheet', '${a.obj('sheet').str('sheet_code')} · row #${a.obj('sheet').str('sheet_row_no')}', width: 120),
        ])),
        if (a.list('downtime').isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Pauses',
            child: Column(children: [
              for (final p in a.list('downtime'))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(StateStyle.of(p.str('downtime_type') == 'Break' || p.str('downtime_type') == 'Refuel' ? 'OnBreak' : p.str('downtime_type')).icon,
                      color: StateStyle.of(p.str('downtime_type') == 'Break' || p.str('downtime_type') == 'Refuel' ? 'OnBreak' : p.str('downtime_type')).color),
                  title: Text('${p.str('downtime_type')}  ${Fmt.time(p.str('start_time'))} - ${p.strOrNull('end_time') == null ? 'now' : Fmt.time(p.str('end_time'))}'),
                  subtitle: p.strOrNull('reason') == null ? null : Text(p.str('reason')),
                  trailing: _editable ? IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.breakdown), onPressed: () => _deleteDowntime(p)) : null,
                ),
            ]),
          ),
        ],
        if (_editable) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                final ok = await editRowSheet(context, att: a, vendorId: widget.vendorId ?? a.intOrNull('vendor_id'));
                if (ok == true) await _reload();
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Edit'),
            ),
            if (a.str('status') == 'Rejected') FilledButton.icon(onPressed: _resubmit, icon: const Icon(Icons.send_rounded), label: const Text('Send again')),
            if (a.str('status') == 'Draft')
              OutlinedButton.icon(
                onPressed: _deleteRow,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.breakdown),
                label: const Text('Delete', style: TextStyle(color: AppColors.breakdown)),
              ),
          ]),
        ],
      ]),
    );
  }
}
