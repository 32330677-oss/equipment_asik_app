import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';
import 'action_sheets.dart';
import 'paper_entry_screen.dart';

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

  /// Only the answer of the latest request is shown (switching days quickly must not show an older day).
  int _seq = 0;

  /// Live state shown only (null = all), set by tapping the summary.
  String? _filter;
  final _search = TextEditingController();

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
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final date = _date;
    setState(() => _loading = true);
    try {
      final d = await Api.I.getObj('/equipment/attendance/site/${widget.siteId}', query: {'date': date, 'shift': widget.shift});
      if (mounted && seq == _seq) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e);
    }
    if (mounted && seq == _seq) setState(() => _loading = false);
  }

  /// Opens another day: the old day's cards are removed at once so no action is taken on them by mistake.
  void _goTo(String date) {
    if (date == _date) return;
    setState(() {
      _date = date;
      _d = null;
      _error = null;
      _filter = null;
    });
    _load();
  }

  Future<void> _openPaperEntry() async {
    final d = _d;
    if (d == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaperEntryScreen(
          siteId: widget.siteId,
          shift: widget.shift,
          date: _date,
          day: d,
          siteLabel: '${d.obj('site').str('site_code')}  ${d.obj('site').str('site_name')}',
        ),
      ),
    );
    // rows may be saved even when the screen is left with some still failing: always reload
    if (mounted) _load();
    if (saved == true && mounted) showSnack(context, 'Paper sheet saved.');
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
      '${s.intv('draft_rows')} row(s) will be sent to the office for approval. Until the office approves them you can still recall them to fix a mistake.'
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

  /// Takes back every Submitted row of the day (not approved yet) to Draft.
  Future<void> _recallDay() async {
    final reason = await promptText(context, 'Recall ${Fmt.dayLabel(_date)}?', label: 'What needs fixing (kept in the history)', confirm: 'Recall');
    if (reason == null) return;
    try {
      final r = asJson(await Api.I.post('/equipment/attendance/recall', {'site_id': widget.siteId, 'shift_type': widget.shift, 'record_date': _date, 'reason': reason}));
      if (mounted) showSnack(context, '${r.intv('recalled')} row(s) back to Draft.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pickDate() async {
    final d = await pickDate(context, initial: _date, last: Fmt.today());
    if (d != null) _goTo(d);
  }

  /// The machines to show: filtered by state and search, then grouped by vendor (vendors A-Z, the board's order inside).
  List<(String, List<Json>)> _groups(List<Json> machines) {
    final q = _search.text.trim().toLowerCase();
    final shown = machines.where((m) {
      if (_filter != null && m.str('live_state') != _filter) return false;
      if (q.isEmpty) return true;
      return [m.str('equipment_code'), m.str('plate_number'), m.str('type_name'), m.str('machine_label'), m.str('vendor_name')].any((x) => x.toLowerCase().contains(q));
    });
    final byVendor = <String, List<Json>>{};
    for (final m in shown) {
      byVendor.putIfAbsent(m.str('vendor_name', 'Other'), () => []).add(m);
    }
    final names = byVendor.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final n in names) (n, byVendor[n]!)];
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final isToday = _date == Fmt.today();
    final machines = d?.list('machines') ?? const <Json>[];
    final groups = _groups(machines);
    final canEdit = d != null && (d.obj('access').isEmpty || d.obj('access').flag('can_edit'));
    // a finished day still missing machines is entered from the paper sheet in one screen
    final paperRows = canEdit && !isLiveDay(_date, shift: widget.shift) ? machines.where((m) => m.obj('attendance').isEmpty).length : 0;
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
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') {
                PdfViewScreen.open(context,
                    title: 'Daily report $_date',
                    fileName: 'daily-${widget.siteId}-$_date.pdf',
                    load: () => Api.I.getBytes('/equipment/reports/daily.pdf', query: {'date': _date, 'site_id': widget.siteId}));
              }
              if (v == 'refresh') _load();
              if (v == 'paper') _openPaperEntry();
              if (v == 'recall') _recallDay();
              if (v == 'requests') Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const MyChangeRequestsScreen()));
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Refresh'))),
              if (paperRows > 0) const PopupMenuItem(value: 'paper', child: ListTile(leading: Icon(Icons.table_rows_rounded), title: Text('Fill from the paper sheet'))),
              const PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('Daily report PDF'))),
              const PopupMenuItem(value: 'requests', child: ListTile(leading: Icon(Icons.forward_to_inbox_rounded), title: Text('My change requests'))),
              if ((d?.obj('submit').intv('submitted_rows') ?? 0) > 0)
                PopupMenuItem(
                    value: 'recall',
                    child: ListTile(leading: const Icon(Icons.undo_rounded), title: Text('Recall the day (${d!.obj('submit').intv('submitted_rows')} submitted)'))),
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
                            _DayNavigator(
                              date: _date,
                              shift: widget.shift,
                              onPrev: () => _goTo(addDaysTo(_date, -1)),
                              onNext: isToday ? null : () => _goTo(addDaysTo(_date, 1)),
                              onPick: _pickDate,
                              onToday: isToday ? null : () => _goTo(Fmt.today()),
                            ),
                            const SizedBox(height: 10),
                            if (!d.obj('access').flag('can_edit') && d.obj('access').isNotEmpty) _ReadOnlyBanner(reason: d.obj('access').str('reason')),
                            if (paperRows > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton.tonalIcon(
                                    onPressed: _openPaperEntry,
                                    icon: const Icon(Icons.table_rows_rounded),
                                    label: Text('Fill from the paper sheet  ·  $paperRows machine${paperRows == 1 ? '' : 's'}',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ),
                            _SummaryStrip(
                              summary: d.obj('summary'),
                              selected: _filter,
                              onSelect: (st) => setState(() => _filter = _filter == st ? null : st),
                            ),
                            if (machines.length > 6) ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  hintText: 'Search code, plate, type or vendor',
                                  suffixIcon: _search.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Clear',
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () => setState(_search.clear),
                                        ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            if (machines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Card(child: EmptyView(text: 'No machine is deployed on this site and shift for this day.', icon: Icons.precision_manufacturing_rounded)),
                              )
                            else if (groups.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Card(
                                  child: EmptyView(
                                    text: 'No machine matches.',
                                    icon: Icons.filter_alt_off_rounded,
                                    action: TextButton(
                                      onPressed: () => setState(() {
                                        _filter = null;
                                        _search.clear();
                                      }),
                                      child: const Text('Show all'),
                                    ),
                                  ),
                                ),
                              )
                            else
                              for (final g in groups) ...[
                                VendorHeader(name: g.$1, count: g.$2.length),
                                for (final m in g.$2)
                                  _MachineCard(
                                    m: m,
                                    date: _date,
                                    access: d.obj('access'),
                                    onAction: (fut) => _after(fut),
                                    siteId: widget.siteId,
                                    shift: widget.shift,
                                    onChanged: _load,
                                  ),
                              ],
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// "Historical visibility is not editing permission": the day is shown, the actions are hidden, and the banner says
/// what the supervisor can do instead.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.reason});
  final String reason;
  @override
  Widget build(BuildContext context) {
    final text = switch (reason) {
      'moved_away' => 'You no longer supervise this site and shift, so this day is read-only. '
          'If something is wrong, tell the current supervisor or the office.',
      'before_assignment' => 'This day is before you became supervisor of this site and shift: you can see it, but not change it. '
          'Open a row and use "Ask the office" to request a change.',
      _ => 'You can see this day but not change it.',
    };
    return NoticeBox(color: AppColors.navy, icon: Icons.visibility_rounded, title: 'Read only', text: text);
  }
}

/// Previous / next day around the date, with a clear "not today" state and a way back to today.
class _DayNavigator extends StatelessWidget {
  const _DayNavigator({required this.date, required this.shift, required this.onPrev, required this.onNext, required this.onPick, required this.onToday});
  final String date;
  final String shift;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final past = onToday != null;
    final color = past ? AppColors.standby : AppColors.navy;
    return Container(
      decoration: BoxDecoration(
        color: past ? AppColors.standby.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: past ? AppColors.standby.withValues(alpha: 0.35) : AppColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(tooltip: 'Previous day', onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded, size: 28)),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.calendar_month_rounded, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(Fmt.dayLabel(date), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
                ]),
                Text(
                  past ? 'Not today · recording a past day' : (shift == 'Night' ? 'Tonight' : 'Today'),
                  style: TextStyle(fontSize: 12, color: past ? AppColors.standby : AppColors.muted, fontWeight: past ? FontWeight.w600 : FontWeight.w400),
                ),
              ]),
            ),
          ),
        ),
        if (onToday != null) TextButton(onPressed: onToday, child: const Text('Today')),
        IconButton(tooltip: 'Next day', onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded, size: 28)),
      ]),
    );
  }
}

/// Counts per state; tapping one shows only those machines (tap again for all).
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.selected, required this.onSelect});
  final Json summary;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String state, String key) {
      final s = StateStyle.of(state);
      final n = summary.intv(key);
      final on = selected == state;
      final dim = selected != null && !on;
      return Opacity(
        opacity: dim ? 0.5 : 1,
        child: Material(
          color: on ? s.color.withValues(alpha: 0.18) : (n == 0 ? Colors.white : s.color.withValues(alpha: 0.1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: on ? s.color : (n == 0 ? AppColors.line : s.color.withValues(alpha: 0.4)), width: on ? 1.6 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: n == 0 && !on ? null : () => onSelect(state),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s.icon, size: 18, color: n == 0 ? AppColors.neutral : s.color),
                const SizedBox(width: 6),
                Text('$n', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: n == 0 ? AppColors.muted : s.color)),
                const SizedBox(width: 4),
                Text(s.label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                if (on) ...[const SizedBox(width: 4), Icon(Icons.close_rounded, size: 15, color: s.color)],
              ]),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in const [
          ('Working', 'working'), ('OnBreak', 'on_break'), ('Breakdown', 'breakdown'), ('Standby', 'standby'),
          ('NotArrived', 'not_arrived'), ('Finished', 'finished'), ('Absent', 'absent'), ('Holiday', 'holiday'),
        ])
          if (e.$1 != 'Holiday' || summary.intv(e.$2) > 0) Padding(padding: const EdgeInsets.only(right: 8), child: chip(e.$1, e.$2)),
      ]),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard(
      {required this.m, required this.date, required this.onAction, required this.siteId, required this.shift, required this.onChanged, this.access = const {}});
  final Json m;
  final String date;
  final Json access;
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
    final canEdit = access.isEmpty || access.flag('can_edit');
    final editable = canEdit && (!hasRow || status == 'Draft' || status == 'Rejected');
    final open = att.objOrNull('open_downtime');
    final recordDate = att.str('record_date', date);

    // running minutes for a working session today
    String? running;
    if (hasRow && att.strOrNull('check_in_time') != null && att.strOrNull('check_out_time') == null) {
      final start = Fmt.parse(att.str('check_in_time'));
      if (start != null) running = Fmt.duration(Fmt.now().difference(start).inMinutes);
    }

    final List<Widget> actions = [];
    if (editable) {
      switch (state) {
        case 'NotArrived':
          actions.add(_primary('Check in', Icons.login_rounded, AppColors.working,
              () => onAction(checkInSheet(context, machine: m, siteId: siteId, shift: shift, date: date, access: access))));
          actions.add(_secondary('Did not work', Icons.event_busy_rounded,
              () => onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date, access: access))));
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
                () => onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date, initial: state, access: access))));
          }
          break;
        case 'Finished':
          // checked out: a forgotten lunch can still be added, and the times corrected, until the day is submitted
          if (att.str('day_status') == 'Working' && att.strOrNull('check_in_time') != null) {
            actions.add(_primary('Add lunch / break', Icons.coffee_rounded, AppColors.onBreak,
                () => onAction(downtimeSheet(context, att: att, type: 'Break', date: recordDate))));
            // same width as the old "Edit" button: Edit times, or replace the session by a whole-day status
            // (a machine recorded as working that was in fact broken / absent). The server asks to confirm the
            // replacement; the row keeps its paper sheet number and the old times stay in the history.
            actions.add(_editMenu(context, att, recordDate));
          }
          break;
        case 'Absent':
        case 'Holiday':
          actions.add(_secondary('It came after all', Icons.login_rounded,
              () => onAction(checkInSheet(context, machine: m, siteId: siteId, shift: shift, date: date, access: access))));
          actions.add(_secondary('Change', Icons.edit_calendar_rounded,
              () => onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date, initial: state, access: access))));
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
                  // 016: the machine's own number inside its vendor + type ("Excavator #3") is the big title, so two
                  // machines of the same type and vendor are not confused; the internal code stays next to it.
                  Row(children: [
                    Flexible(
                        child: Text(m.machineType, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink))),
                    const SizedBox(width: 8),
                    Text(m.str('equipment_code'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                  ]),
                  // the vendor is the group header above the card
                  if (m.strOrNull('plate_number') != null)
                    Text(m.str('plate_number'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                StatePill(state),
                if (hasRow && status != 'Draft') Padding(padding: const EdgeInsets.only(top: 4), child: WorkflowPill(status)),
                if (att.flag('from_previous_day')) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Since yesterday', color: AppColors.standby)),
                if (att.flag('late_entry')) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Late entry', color: AppColors.standby, icon: Icons.history_toggle_off_rounded)),
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

  Widget _editMenu(BuildContext context, Json att, String recordDate) {
    return SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Edit',
        onSelected: (v) {
          if (v == 'times') _details(context);
          // a breakdown or standby at another time of the day, also after the lunch and after the check-out
          if (v == 'Breakdown' || v == 'Standby' || v == 'Refuel') onAction(downtimeSheet(context, att: att, type: v, date: recordDate));
          if (v == 'day') onAction(dayStatusSheet(context, machine: m, siteId: siteId, shift: shift, date: date, initial: 'Breakdown', access: access));
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'times', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit times'))),
          PopupMenuItem(value: 'Breakdown', child: ListTile(leading: Icon(Icons.build_circle_rounded, color: AppColors.breakdown), title: Text('Add a breakdown'))),
          PopupMenuItem(value: 'Standby', child: ListTile(leading: Icon(Icons.pause_circle_filled_rounded, color: AppColors.standby), title: Text('Add a standby period'))),
          PopupMenuItem(value: 'Refuel', child: ListTile(leading: Icon(Icons.local_gas_station_rounded, color: AppColors.onBreak), title: Text('Add a refuelling stop'))),
          PopupMenuItem(
            value: 'day',
            child: ListTile(
              leading: Icon(Icons.event_busy_rounded, color: AppColors.breakdown),
              title: Text('Did not work'),
              subtitle: Text('Breakdown, standby, absent... replaces the times'),
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit_rounded, size: 20),
            SizedBox(width: 6),
            Text('Edit', style: TextStyle(fontWeight: FontWeight.w600)),
            Icon(Icons.arrow_drop_down_rounded),
          ]),
        ),
      ),
    );
  }

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
      builder: (_) => RowDetailSheet(
        att: m.obj('attendance'),
        vendorId: m.intv('vendor_id'),
        canEdit: access.isEmpty || access.flag('can_edit'),
        denial: access.strOrNull('reason'),
      ),
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
  const RowDetailSheet({super.key, required this.att, this.vendorId, this.canEdit = true, this.denial});
  final Json att;
  final int? vendorId;
  /// false when the supervisor may only read this day (moved away, or a day before their assignment)
  final bool canEdit;
  /// why not: 'moved_away' / 'before_assignment' / ...
  final String? denial;
  @override
  State<RowDetailSheet> createState() => _RowDetailSheetState();
}

class _RowDetailSheetState extends State<RowDetailSheet> {
  late Json _a = widget.att;

  bool get _editable => widget.canEdit && (_a.str('status') == 'Draft' || _a.str('status') == 'Rejected');

  /// The supervisor asks the office: an Approved row of their site, or a day before their assignment.
  bool get _canAskOffice =>
      _a.str('status') != 'Cancelled' && ((widget.canEdit && _a.str('status') == 'Approved') || widget.denial == 'before_assignment');

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

  Future<void> _editDowntime(Json p) async {
    final ok = await downtimeEditSheet(context, att: _a, period: p);
    if (ok == true) await _reload();
  }

  /// A Rejected row that should not exist (wrong machine, wrong day): kept for history as Cancelled, never deleted.
  Future<void> _cancelRow() async {
    final reason = await promptText(context, 'Cancel this row?',
        label: 'Why should this row not exist?',
        minLength: 5,
        confirm: 'Cancel the row',
        help: 'Use this when the record is wrong as a whole (wrong machine, wrong day, duplicate). '
            'The row stays in the history as Cancelled. Write "cancelled" on row #${_a.obj('sheet').str('sheet_row_no')} of the paper sheet too.');
    if (reason == null) return;
    try {
      final r = asJson(await Api.I.patch('/equipment/attendance/${_a.intv('eq_attendance_id')}/cancel', {'reason': reason}));
      if (!mounted) return;
      setState(() => _a = r);
      showSnack(context, 'Row cancelled.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _askOffice() async {
    final ok = await changeRequestSheet(context, att: _a);
    if (ok == true && mounted) Navigator.pop(context);
  }

  Future<void> _recall() async {
    final reason = await promptText(context, 'Recall this row?', label: 'What needs fixing (kept in the history)', confirm: 'Recall');
    if (reason == null) return;
    try {
      final r = asJson(await Api.I.patch('/equipment/attendance/${_a.intv('eq_attendance_id')}/recall', {'reason': reason}));
      if (!mounted) return;
      setState(() => _a = r);
      showSnack(context, 'Back to Draft. Fix it, then submit the day again.');
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
        if (!widget.canEdit && a.str('status') != 'Cancelled')
          NoticeBox(
            color: AppColors.navy,
            icon: Icons.visibility_rounded,
            text: widget.denial == 'before_assignment'
                ? 'This day is before your assignment to the site: ask the office to change it.'
                : 'Read only: you no longer supervise this site and shift.',
          ),
        if (a.str('status') == 'Cancelled')
          NoticeBox(
            color: AppColors.neutral,
            icon: Icons.block_rounded,
            title: 'Cancelled',
            text: '${a.str('cancel_reason', 'No reason given')}${a.strOrNull('cancelled_at') == null ? '' : '  (${Fmt.date(a.str('cancelled_at'))})'}',
          ),
        if (a.flag('late_entry'))
          NoticeBox(
            color: AppColors.standby,
            icon: Icons.history_toggle_off_rounded,
            title: 'Late entry (${a.intv('late_entry_days')} days after the day)',
            text: a.strOrNull('late_entry_reason') ?? 'No reason given. The office sees this row as a late entry.',
          ),
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
                  trailing: _editable
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Correct', icon: const Icon(Icons.edit_rounded), onPressed: () => _editDowntime(p)),
                          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, color: AppColors.breakdown), onPressed: () => _deleteDowntime(p)),
                        ])
                      : null,
                ),
            ]),
          ),
        ],
        if (widget.canEdit && a.str('status') == 'Submitted') ...[
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Sent to the office, not approved yet. Recall it to fix a mistake.', style: TextStyle(color: AppColors.muted, fontSize: 13))),
            OutlinedButton.icon(onPressed: _recall, icon: const Icon(Icons.undo_rounded), label: const Text('Recall')),
          ]),
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
            // a pause (lunch...) can be added at any time on an editable Working row, also after the check-out
            if (a.str('day_status') == 'Working' && a.strOrNull('check_in_time') != null && a.objOrNull('open_downtime') == null)
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await downtimeSheet(context, att: a, type: 'Break', date: date);
                  if (ok == true) await _reload();
                },
                icon: const Icon(Icons.coffee_rounded),
                label: const Text('Add break'),
              ),
            // a breakdown at another time of the day (a lunch already recorded does not block it)
            if (a.str('day_status') == 'Working' && a.strOrNull('check_in_time') != null && a.objOrNull('open_downtime') == null)
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await downtimeSheet(context, att: a, type: 'Breakdown', date: date);
                  if (ok == true) await _reload();
                },
                icon: const Icon(Icons.build_circle_rounded),
                label: const Text('Add breakdown'),
              ),
            if (a.str('status') == 'Rejected') FilledButton.icon(onPressed: _resubmit, icon: const Icon(Icons.send_rounded), label: const Text('Send again')),
            if (a.str('status') == 'Draft')
              OutlinedButton.icon(
                onPressed: _deleteRow,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.breakdown),
                label: const Text('Delete', style: TextStyle(color: AppColors.breakdown)),
              ),
            // a row the office approved once is voided by the office, never cancelled by the supervisor
            if (a.str('status') == 'Rejected' && !a.flag('was_approved'))
              OutlinedButton.icon(
                onPressed: _cancelRow,
                icon: const Icon(Icons.block_rounded, color: AppColors.breakdown),
                label: const Text('Cancel the row', style: TextStyle(color: AppColors.breakdown)),
              ),
          ]),
        ],
        if (_canAskOffice) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(
                a.str('status') == 'Approved' ? 'Approved by the office. Something wrong? Ask the office to change it.' : 'Something wrong? Ask the office to change it.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
            OutlinedButton.icon(onPressed: _askOffice, icon: const Icon(Icons.forward_to_inbox_rounded), label: const Text('Ask the office')),
          ]),
        ],
      ]),
    );
  }
}

/// The supervisor's change requests and the office's answers; a pending one can be withdrawn.
class MyChangeRequestsScreen extends StatefulWidget {
  const MyChangeRequestsScreen({super.key});
  @override
  State<MyChangeRequestsScreen> createState() => _MyChangeRequestsScreenState();
}

class _MyChangeRequestsScreenState extends State<MyChangeRequestsScreen> {
  final _s = Loadable<List<Json>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/attendance/change-requests');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _withdraw(Json r) async {
    final ok = await confirmDialog(context, 'Withdraw this request?', 'The office will not see it any more. Nothing on the row changes.', confirm: 'Withdraw');
    if (!ok) return;
    try {
      await Api.I.patch('/equipment/attendance/change-requests/${r.intv('change_request_id')}/withdraw');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    return Scaffold(
      appBar: AppBar(title: const Text('My change requests')),
      body: _s.loading && _s.data == null
          ? const LoadingView()
          : _s.error != null
              ? ErrorView(error: _s.error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    if (rows.isEmpty) const Card(child: EmptyView(text: 'You have not asked the office for any change.', icon: Icons.forward_to_inbox_rounded)),
                    for (final r in rows)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text('${r.str('equipment_code')} · ${r.str('site_code')} · ${Fmt.dayLabel(r.str('record_date'))}',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              ),
                              Pill(r.str('status'),
                                  color: switch (r.str('status')) {
                                    'Applied' => AppColors.working,
                                    'Rejected' => AppColors.breakdown,
                                    'Pending' => AppColors.info,
                                    _ => AppColors.neutral,
                                  }),
                            ]),
                            const SizedBox(height: 6),
                            for (final e in r.obj('proposed_changes').entries)
                              Text('${fieldLabel(e.key)}: ${valueLabel(e.value)}', style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('Reason: ${r.str('reason')}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                            if (r.strOrNull('decision_note') != null)
                              Text('Office: ${r.str('decision_note')}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            if (r.str('status') == 'Pending')
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(onPressed: () => _withdraw(r), icon: const Icon(Icons.undo_rounded), label: const Text('Withdraw')),
                              ),
                          ]),
                        ),
                      ),
                  ]),
                ),
    );
  }
}