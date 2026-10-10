import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';
import 'action_sheets.dart';

/// Light separator above the machines of one vendor: the name is there to find them, not to draw attention.
class VendorHeader extends StatelessWidget {
  const VendorHeader({super.key, required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(children: [
        const Icon(Icons.business_rounded, size: 15, color: AppColors.neutral),
        const SizedBox(width: 6),
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.2)),
        ),
        const SizedBox(width: 6),
        Text('$count', style: const TextStyle(fontSize: 12, color: AppColors.neutral)),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.line)),
      ]),
    );
  }
}

/// The day status a paper row is saved as. Skip leaves the machine without a record.
const _statuses = ['Working', 'Standby', 'Breakdown', 'Absent', 'Holiday', 'Skip'];

class _Row {
  _Row(this.m, String start, String? end)
      : inT = start,
        outT = end,
        meterStart = TextEditingController(text: m.strOrNull('last_meter_end') ?? ''),
        meterEnd = TextEditingController(),
        reason = TextEditingController();

  final Json m;
  String status = 'Working';
  String inT;
  String? outT;
  bool lunch = false;

  /// The times were set for this machine (by hand or copied): the common hours above no longer change them.
  bool ownTimes = false;
  final TextEditingController meterStart;
  final TextEditingController meterEnd;
  final TextEditingController reason;

  /// null = not sent yet; '' = saved; otherwise the error (or the warning when [saved]).
  String? result;
  bool saved = false;

  bool get hasMeter => m.str('meter_unit', 'Hours') != 'None';
  String get code => m.str('equipment_code');

  void dispose() {
    meterStart.dispose();
    meterEnd.dispose();
    reason.dispose();
  }
}

/// A finished day entered from the paper sheet in one screen: every machine still without a record, pre-filled with the
/// usual hours of the shift, the start meter from its last reading and a lunch break. Only the differences are changed,
/// then everything is saved at once; a row the server refuses stays on screen with the reason, the others are saved.
class PaperEntryScreen extends StatefulWidget {
  const PaperEntryScreen({super.key, required this.siteId, required this.shift, required this.date, required this.day, required this.siteLabel});
  final int siteId;
  final String shift;
  final String date;

  /// The day board data of [date] (machines, access).
  final Json day;
  final String siteLabel;

  @override
  State<PaperEntryScreen> createState() => _PaperEntryScreenState();
}

class _PaperEntryScreenState extends State<PaperEntryScreen> {
  late String _start = shiftTime(widget.date, start: true, shift: widget.shift);
  late String _end = alignAfter(shiftTime(widget.date, start: false, shift: widget.shift), _start, shift: widget.shift);
  // a lunch break lowers the billed hours, so it is never assumed: one tap above adds it to every machine
  bool _lunch = false;
  final _late = TextEditingController();
  late final List<_Row> _rows;
  bool _saving = false;
  int _done = 0;
  int _total = 0;
  bool _copying = false;
  bool _dirty = false;

  String get _shift => widget.shift;
  Json get _access => widget.day.obj('access');

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final m in widget.day.list('machines'))
        if (m.obj('attendance').isEmpty) _Row(m, _start, _end),
    ]..sort((a, b) {
        final v = a.m.str('vendor_name').toLowerCase().compareTo(b.m.str('vendor_name').toLowerCase());
        return v != 0 ? v : a.code.compareTo(b.code);
      });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _late.dispose();
    super.dispose();
  }

  List<_Row> get _pending => _rows.where((r) => !r.saved && r.status != 'Skip').toList();

  void _change(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  // ------------------------------------------------------------------ common hours
  void _setCommon({String? start, String? end, bool? lunch}) {
    _change(() {
      if (start != null) {
        _start = start;
        _end = alignAfter(_end, _start, shift: _shift);
      }
      if (end != null) _end = end;
      if (lunch != null) _lunch = lunch;
      for (final r in _rows) {
        if (r.saved || r.ownTimes) continue;
        r.inT = _start;
        r.outT = _end;
        if (lunch != null) r.lunch = lunch;
      }
    });
  }

  // ------------------------------------------------------------------ copy the previous day
  /// Same status and clock times as on the day before, for every machine that had a record then.
  Future<void> _copyPrevious() async {
    final prev = addDaysTo(widget.date, -1);
    setState(() => _copying = true);
    try {
      final d = await Api.I.getObj('/equipment/attendance/site/${widget.siteId}', query: {'date': prev, 'shift': _shift});
      final byId = {for (final m in d.list('machines')) m.intv('equipment_id'): m.obj('attendance')};
      var n = 0;
      _change(() {
        for (final r in _rows) {
          if (r.saved) continue;
          final a = byId[r.m.intv('equipment_id')];
          if (a == null || a.isEmpty || a.str('record_date') != prev) continue;
          final st = a.str('day_status');
          if (!_statuses.contains(st)) continue;
          r.status = st;
          final inP = a.strOrNull('check_in_time');
          final outP = a.strOrNull('check_out_time');
          if (inP != null && outP != null) {
            r.inT = alignStart('${widget.date} ${Fmt.time(inP)}', widget.date, shift: _shift);
            r.outT = alignAfter('${widget.date} ${Fmt.time(outP)}', r.inT, shift: _shift);
            r.ownTimes = true;
          }
          r.lunch = a.list('downtime').any((p) => p.str('downtime_type') == 'Break');
          if (st == 'Standby' || st == 'Breakdown') r.reason.text = a.str('remarks');
          r.result = null;
          n++;
        }
      });
      if (mounted) showSnack(context, n == 0 ? 'Nothing to copy: no record on ${Fmt.dayLabel(prev)}.' : 'Copied $n machine${n == 1 ? '' : 's'} from ${Fmt.dayLabel(prev)}. Check the differences.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _copying = false);
  }

  // ------------------------------------------------------------------ save
  /// Checks one row before anything is sent; returns the problem or null.
  String? _check(_Row r) {
    if (r.status == 'Working') {
      final s = Fmt.parse(r.inT);
      final e = Fmt.parse(r.outT);
      if (e == null) return 'Set the end time.';
      if (s == null || !e.isAfter(s)) return 'The end (${Fmt.time(r.outT)}) must be after the start (${Fmt.time(r.inT)}).';
      if (e.isAfter(Fmt.now())) return 'The end time is in the future.';
      if (r.meterStart.text.trim().isNotEmpty && numOrNull(r.meterStart) == null) return 'The start meter is not a number.';
      if (r.meterEnd.text.trim().isNotEmpty && numOrNull(r.meterEnd) == null) return 'The end meter is not a number.';
      final ms = numOrNull(r.meterStart);
      final me = numOrNull(r.meterEnd);
      if (ms != null && me != null && me < ms) return 'The end meter ($me) is lower than the start meter ($ms).';
    }
    if ((r.status == 'Standby' || r.status == 'Breakdown') && r.reason.text.trim().isEmpty) return 'Give the reason.';
    return null;
  }

  Future<void> _saveRow(_Row r) async {
    final late = textOrNull(_late);
    if (r.status == 'Working') {
      final ms = numOrNull(r.meterStart);
      final me = numOrNull(r.meterEnd);
      final res = await Api.I.request('POST', '/equipment/attendance/check-in', body: {
        'equipment_id': r.m.intv('equipment_id'), 'site_id': widget.siteId, 'shift_type': _shift,
        'record_date': widget.date, 'check_in_time': r.inT, 'check_out_time': r.outT,
        if (r.hasMeter && ms != null) 'meter_start': ms,
        if (r.hasMeter && me != null) 'meter_end': me,
        if (late != null) 'late_reason': late,
      });
      r.saved = true;
      r.result = '';
      if (r.lunch) {
        final l = lunchDefault(r.inT, r.outT!);
        try {
          await Api.I.post('/equipment/attendance/${res.obj('data').intv('eq_attendance_id')}/downtime/start', {
            'downtime_type': 'Break', 'start_time': l.$1, 'end_time': l.$2, 'reason': 'Lunch',
          });
        } catch (e) {
          // the session is saved; the lunch can be added from the row
          r.result = 'Saved without the lunch: open the machine and tap "Add lunch". (${e is ApiException ? e.message : e})';
        }
      }
    } else {
      await Api.I.request('POST', '/equipment/attendance/day-status', body: {
        'equipment_id': r.m.intv('equipment_id'), 'site_id': widget.siteId, 'shift_type': _shift, 'record_date': widget.date,
        'day_status': r.status,
        if (textOrNull(r.reason) != null) 'remarks': textOrNull(r.reason),
        if (late != null) 'late_reason': late,
      });
      r.saved = true;
      r.result = '';
    }
  }

  Future<void> _saveAll() async {
    final rows = _pending;
    if (rows.isEmpty) {
      showSnack(context, 'Nothing to save: every machine is skipped or already saved.');
      return;
    }
    var bad = 0;
    setState(() {
      for (final r in rows) {
        r.result = _check(r);
        if (r.result != null) bad++;
      }
    });
    if (bad > 0) {
      showSnack(context, '$bad machine${bad == 1 ? '' : 's'} to fix first (marked in red).', error: true);
      return;
    }
    setState(() {
      _saving = true;
      _done = 0;
      _total = rows.length;
    });
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      try {
        await _saveRow(r);
      } catch (e) {
        r.result = e is ApiException ? e.message : 'Not saved. Please try again.';
        if (e is ApiException && e.isNetwork) {
          // no connection: stop here, the next rows were not sent
          for (final x in rows.skip(i + 1)) {
            x.result = 'Not sent: no connection. Tap "Save all" again.';
          }
          break;
        }
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final failed = rows.where((r) => !r.saved).length;
    if (failed == 0) {
      Navigator.pop(context, true);
    } else {
      showSnack(context, '${rows.length - failed} saved, $failed not saved: see the reasons in red.', error: true);
    }
  }

  Future<void> _leave() async {
    final anySaved = _rows.any((r) => r.saved);
    final unsent = _pending.isNotEmpty && _dirty;
    if (unsent) {
      final ok = await confirmDialog(context, 'Leave without saving?', 'What you entered here for the machines not saved yet will be lost.', confirm: 'Leave', danger: true);
      if (!ok || !mounted) return;
    }
    Navigator.pop(context, anySaved);
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_Row>>{};
    for (final r in _rows) {
      groups.putIfAbsent(r.m.str('vendor_name', 'Other'), () => []).add(r);
    }
    final pending = _pending.length;
    final skipped = _rows.where((r) => !r.saved && r.status == 'Skip').length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Fill from the paper sheet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text('${widget.siteLabel}  ·  ${_shift == 'Night' ? 'Night' : 'Day'} shift  ·  ${Fmt.dayLabel(widget.date)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
          bottom: _saving
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3, value: _total == 0 ? null : _done / _total),
                )
              : null,
        ),
        bottomNavigationBar: _SaveBar(
          pending: pending,
          skipped: skipped,
          saving: _saving,
          done: _done,
          total: _total,
          onSave: _saving ? null : _saveAll,
        ),
        body: _rows.isEmpty
            ? const EmptyView(text: 'Every machine already has a record for this day.', icon: Icons.task_alt_rounded)
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (isLateDay(_access)) ...[
                          NoticeBox(
                            color: AppColors.standby,
                            icon: Icons.history_toggle_off_rounded,
                            title: 'Late entry: ${_access.intv('days_old')} days after the day',
                            text: 'The rows are saved, but the office sees them marked as late entries. Say why once for all of them.',
                          ),
                          TextField(
                            controller: _late,
                            maxLines: 2,
                            decoration: const InputDecoration(labelText: 'Why is it entered late?', hintText: 'e.g. the paper sheet came back from site late'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _commonCard(),
                        const SizedBox(height: 4),
                        for (final g in groups.entries) ...[
                          VendorHeader(name: g.key, count: g.value.length),
                          for (final r in g.value) _rowCard(r),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _commonCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.navy),
            const SizedBox(width: 6),
            const Expanded(child: Text('Usual hours of the day', style: TextStyle(fontWeight: FontWeight.w800))),
            TextButton.icon(
              onPressed: _copying || _saving ? null : _copyPrevious,
              icon: _copying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.content_copy_rounded, size: 18),
              label: Text('Same as ${Fmt.dayLabel(addDaysTo(widget.date, -1))}'),
            ),
          ]),
          const Text('Applied to every machine you did not change by hand.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _TimeChip(label: 'Start', value: _start, baseDate: widget.date, shift: _shift, onChanged: _saving ? null : (v) => _setCommon(start: v)),
            _TimeChip(label: 'End', value: _end, baseDate: widget.date, shift: _shift, after: _start, onChanged: _saving ? null : (v) => _setCommon(end: v)),
            FilterChip(
              avatar: const Icon(Icons.coffee_rounded, size: 18),
              label: const Text('Lunch break'),
              selected: _lunch,
              onSelected: _saving ? null : (v) => _setCommon(lunch: v),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _rowCard(_Row r) {
    final error = r.result != null && r.result!.isNotEmpty && !r.saved;
    final warn = r.saved && (r.result ?? '').isNotEmpty;
    final skip = r.status == 'Skip';
    final color = r.saved ? AppColors.working : (error ? AppColors.breakdown : (skip ? AppColors.line : StateStyle.of(r.status).color));
    final locked = r.saved || _saving;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 5))),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
        child: Opacity(
          opacity: skip && !r.saved ? 0.6 : 1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(r.code, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [r.m.str('type_name'), if (r.m.strOrNull('plate_number') != null) r.m.str('plate_number')].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
              if (r.saved) const Pill('Saved', color: AppColors.working, icon: Icons.check_rounded),
            ]),
            const SizedBox(height: 8),
            if (!r.saved)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final st in _statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(st == 'Working' ? 'Worked' : st),
                        selected: r.status == st,
                        onSelected: locked
                            ? null
                            : (_) => _change(() {
                                  r.status = st;
                                  r.result = null;
                                  r.reason.clear();
                                }),
                      ),
                    ),
                ]),
              ),
            if (!r.saved && r.status == 'Working') ...[
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _TimeChip(
                  label: 'Start',
                  value: r.inT,
                  baseDate: widget.date,
                  shift: _shift,
                  onChanged: locked
                      ? null
                      : (v) => _change(() {
                            r.inT = v;
                            if (r.outT != null) r.outT = alignAfter(r.outT!, v, shift: _shift);
                            r.ownTimes = true;
                            r.result = null;
                          }),
                ),
                _TimeChip(
                  label: 'End',
                  value: r.outT,
                  baseDate: widget.date,
                  shift: _shift,
                  after: r.inT,
                  onChanged: locked
                      ? null
                      : (v) => _change(() {
                            r.outT = v;
                            r.ownTimes = true;
                            r.result = null;
                          }),
                ),
                FilterChip(
                  avatar: const Icon(Icons.coffee_rounded, size: 18),
                  label: const Text('Lunch'),
                  selected: r.lunch,
                  onSelected: locked ? null : (v) => _change(() => r.lunch = v),
                ),
              ]),
              if (r.hasMeter) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _meterField(r.meterStart, 'Meter start', r, enabled: !locked)),
                  const SizedBox(width: 10),
                  Expanded(child: _meterField(r.meterEnd, 'Meter end', r, enabled: !locked)),
                ]),
              ],
            ],
            if (!r.saved && (r.status == 'Standby' || r.status == 'Breakdown')) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final q in r.status == 'Breakdown' ? breakdownReasons : standbyReasons)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(q, style: const TextStyle(fontSize: 12.5)),
                    selected: r.reason.text == q,
                    onSelected: locked
                        ? null
                        : (_) => _change(() {
                              r.reason.text = q;
                              r.result = null;
                            }),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: r.reason,
                enabled: !locked,
                onChanged: (_) => _change(() => r.result = null),
                decoration: const InputDecoration(isDense: true, labelText: 'Reason *'),
              ),
            ],
            if (error || warn)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 18, color: error ? AppColors.breakdown : AppColors.standby),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r.result!, style: TextStyle(color: error ? AppColors.breakdown : AppColors.standby, fontWeight: FontWeight.w600, fontSize: 13))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _meterField(TextEditingController c, String label, _Row r, {required bool enabled}) => TextField(
        controller: c,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _change(() => r.result = null),
        decoration: InputDecoration(isDense: true, labelText: label, suffixText: r.m.str('meter_unit') == 'Km' ? 'km' : 'h'),
      );
}

/// Compact time button: the clock time, and "Next day" when a night session ends after midnight.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.value, required this.baseDate, required this.shift, required this.onChanged, this.after});
  final String label;
  final String? value;
  final String baseDate;
  final String shift;
  final String? after;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ref = after != null ? after!.substring(0, 10) : baseDate;
    final day = value?.substring(0, 10);
    final nextDay = day != null && day != ref;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), minimumSize: const Size(0, 48)),
      onPressed: onChanged == null
          ? null
          : () async {
              final seed = value ?? alignAfter(shiftTime(baseDate, start: after == null, shift: shift), after, shift: shift);
              final v = await pickDateTime(context, initial: seed, askDate: false);
              if (v != null) onChanged!(after != null ? alignAfter(v, after, shift: shift) : alignStart(v, baseDate, shift: shift));
            },
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w500)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value == null ? '--:--' : Fmt.time(value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
          if (nextDay) ...[
            const SizedBox(width: 6),
            Icon(shift == 'Night' ? Icons.nightlight_round : Icons.warning_amber_rounded, size: 14, color: shift == 'Night' ? AppColors.navy : AppColors.standby),
            const SizedBox(width: 2),
            Text('Next day', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: shift == 'Night' ? AppColors.navy : AppColors.standby)),
          ],
        ]),
      ]),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.pending, required this.skipped, required this.saving, required this.done, required this.total, required this.onSave});
  final int pending;
  final int skipped;
  final bool saving;
  final int done;
  final int total;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final msg = saving
        ? 'Saving $done of $total...'
        : pending == 0
            ? 'Nothing left to save.'
            : '$pending machine${pending == 1 ? '' : 's'} to save${skipped > 0 ? ' · $skipped skipped' : ''}';
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: pending == 0 ? null : onSave,
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(saving ? 'Saving' : 'Save all'),
            ),
          ]),
        ),
      ),
    );
  }
}
