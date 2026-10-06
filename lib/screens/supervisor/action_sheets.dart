import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Bottom sheets used by the supervisor day board. Every function returns true when something was saved.

const breakdownReasons = ['Hydraulic leak', 'Engine problem', 'Tyre / track', 'Electrical', 'Waiting for mechanic', 'Accident damage'];
const standbyReasons = ['No work available', 'Waiting for material', 'Waiting for instructions', 'Weather', 'Site closed', 'No operator'];

/// Default wall time for an action on [date] when it is not today.
String defaultTime(String date, {required bool start, String shift = 'Day'}) {
  if (date == Fmt.today()) return Fmt.nowWall();
  final d = Fmt.parse(date) ?? Fmt.now();
  if (shift == 'Night') {
    return start ? Fmt.wallOf(DateTime(d.year, d.month, d.day, 19)) : Fmt.wallOf(DateTime(d.year, d.month, d.day + 1, 5));
  }
  return Fmt.wallOf(DateTime(d.year, d.month, d.day, start ? 7 : 17));
}

/// Big, touch-friendly time field ('yyyy-MM-dd HH:mm'). Shows the day when it differs from [baseDate].
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.value, required this.onChanged, this.baseDate, this.clearable = false});
  final String label;
  final String? value;
  final String? baseDate;
  final ValueChanged<String?> onChanged;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    final otherDay = has && baseDate != null && Fmt.dateOf(Fmt.parse(value)!) != baseDate;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final v = await pickDateTime(context, initial: value ?? Fmt.nowWall(), askDate: false);
              if (v != null) onChanged(v);
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Row(children: [
                Text(has ? Fmt.time(value) : '--:--', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.navy)),
                if (otherDay) ...[
                  const SizedBox(width: 8),
                  Pill(Fmt.dayLabel(value!.substring(0, 10)), color: AppColors.standby),
                ],
              ]),
            ]),
          ),
        ),
        IconButton(
          tooltip: 'Now',
          icon: const Icon(Icons.update_rounded),
          onPressed: () => onChanged(Fmt.nowWall()),
        ),
        IconButton(
          tooltip: 'Other day',
          icon: const Icon(Icons.event_rounded),
          onPressed: () async {
            final v = await pickDateTime(context, initial: value ?? Fmt.nowWall(), askDate: true);
            if (v != null) onChanged(v);
          },
        ),
        if (clearable && has) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => onChanged(null)),
      ]),
    );
  }
}

/// Generic action sheet: header with icon, scrollable form, one big submit button.
Future<bool?> showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required IconData icon,
  required Color color,
  required String submitLabel,
  required List<Widget> Function(BuildContext ctx, StateSetter set) body,
  required Future<void> Function() submit,
}) {
  final key = GlobalKey<FormState>();
  var busy = false;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: key,
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      if (subtitle != null) Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                ...body(ctx, set),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: busy
                        ? null
                        : () async {
                            if (!key.currentState!.validate()) return;
                            set(() => busy = true);
                            try {
                              await submit();
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              if (ctx.mounted) {
                                set(() => busy = false);
                                showError(ctx, e);
                              }
                            }
                          },
                    child: busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(submitLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _gap() => const SizedBox(height: 12);

/// 'yyyy-MM-dd HH:mm' of an API date-time ('yyyy-MM-dd HH:mm:ss').
String? wall16(String? v) => v == null ? null : (v.length > 16 ? v.substring(0, 16) : v);

/// True when the day is older than the late-entry limit (a setting, default 3 days): the row is saved, but flagged.
bool isLateDay(Json access) => access.isNotEmpty && access.intv('days_old') > access.intv('late_after_days', 3);

/// Late entry notice + optional reason field. Never blocks saving.
List<Widget> lateReasonFields(Json access, TextEditingController c) {
  if (!isLateDay(access)) return const [];
  return [
    NoticeBox(
      color: AppColors.standby,
      icon: Icons.history_toggle_off_rounded,
      title: 'Late entry: ${access.intv('days_old')} days after the day',
      text: 'It will be saved, but the office sees it marked as a late entry. Say why it is entered late.',
    ),
    textField(c, 'Why is it entered late?', maxLines: 2, hint: 'e.g. the paper sheet came back from site late'),
    _gap(),
  ];
}

/// Shows the warnings of a saved action (late entry...) without blocking.
void showWarnings(BuildContext context, Json envelope) {
  final w = warningsText(envelope);
  if (w != null && context.mounted) showSnack(context, w);
}

// ----------------------------------------------------------------- check-in
/// Check-in. For a past day the end time can be given too: the whole session is recorded in one step
/// (needed when the machine already has later sessions, otherwise an open check-in would overlap them).
Future<bool?> checkInSheet(BuildContext context,
    {required Json machine, required int siteId, required String shift, required String date, Json access = const {}}) {
  var time = defaultTime(date, start: true, shift: shift);
  final past = date != Fmt.today();
  String? outTime;
  final meter = TextEditingController(text: machine.strOrNull('last_meter_end') ?? '');
  final meterEnd = TextEditingController();
  final remarks = TextEditingController();
  final late = TextEditingController();
  final hasMeter = machine.str('meter_unit', 'Hours') != 'None';
  return showActionSheet(
    context,
    title: 'Check in ${machine.str('equipment_code')}',
    subtitle: '${machine.str('type_name')} · ${machine.str('vendor_name')}',
    icon: Icons.login_rounded,
    color: AppColors.working,
    submitLabel: past ? 'Save' : 'Start work',
    submit: () async {
      final ms = numOrNull(meter);
      final me = numOrNull(meterEnd);
      if (outTime != null && ms != null && me != null && me < ms) {
        throw ApiException(null, 'VALIDATION', 'The end meter ($me) is lower than the start meter ($ms).');
      }
      final r = await Api.I.request('POST', '/equipment/attendance/check-in', body: {
        'equipment_id': machine.intv('equipment_id'), 'site_id': siteId, 'shift_type': shift, 'check_in_time': time,
        if (ms != null) 'meter_start': ms,
        if (outTime != null) 'check_out_time': outTime,
        if (outTime != null && me != null) 'meter_end': me,
        if (textOrNull(remarks) != null) 'remarks': textOrNull(remarks),
        if (textOrNull(late) != null) 'late_reason': textOrNull(late),
      });
      if (context.mounted) showWarnings(context, r);
    },
    body: (ctx, set) => [
      ...lateReasonFields(access, late),
      TimeField(label: 'Start time', value: time, baseDate: date, onChanged: (v) => set(() => time = v ?? time)),
      if (past) ...[
        _gap(),
        TimeField(
          label: 'End time (if the day is already over)',
          value: outTime,
          baseDate: date,
          clearable: true,
          onChanged: (v) => set(() => outTime = v),
        ),
        if (outTime == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Add the end time to record the whole session from the paper sheet in one step.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ),
      ],
      if (hasMeter) ...[
        _gap(),
        Row(children: [
          Expanded(
            child: textField(meter, 'Meter at start', number: true, suffix: machine.str('meter_unit') == 'Km' ? 'km' : 'h',
                hint: machine.strOrNull('last_meter_end') == null ? null : 'last reading ${machine.str('last_meter_end')}'),
          ),
          if (outTime != null) ...[
            const SizedBox(width: 12),
            Expanded(child: textField(meterEnd, 'Meter at end', number: true)),
          ],
        ]),
      ],
      _gap(),
      textField(remarks, 'Remarks', maxLines: 2),
    ],
  );
}

// ----------------------------------------------------------------- downtime
Future<bool?> downtimeSheet(BuildContext context, {required Json att, required String type, required String date}) {
  var start = date == Fmt.today() ? Fmt.nowWall() : (att.strOrNull('check_in_time') ?? defaultTime(date, start: true));
  String? end;
  final reason = TextEditingController();
  final needsReason = type == 'Breakdown' || type == 'Standby';
  final quick = type == 'Breakdown' ? breakdownReasons : type == 'Standby' ? standbyReasons : const <String>[];
  final style = StateStyle.of(type == 'Break' || type == 'Refuel' ? 'OnBreak' : type);
  return showActionSheet(
    context,
    title: {'Break': 'Start a break', 'Refuel': 'Refuelling', 'Breakdown': 'Report a breakdown', 'Standby': 'Machine on standby'}[type] ?? type,
    subtitle: '${att.str('equipment_code')} · the clock stops until you resume',
    icon: type == 'Refuel' ? Icons.local_gas_station_rounded : style.icon,
    color: style.color,
    submitLabel: 'Save',
    submit: () => Api.I.post('/equipment/attendance/${att.intv('eq_attendance_id')}/downtime/start', {
      'downtime_type': type, 'start_time': start, if (end != null) 'end_time': end,
      if (textOrNull(reason) != null) 'reason': textOrNull(reason),
    }),
    body: (ctx, set) => [
      TimeField(label: 'From', value: start, baseDate: date, onChanged: (v) => set(() => start = v ?? start)),
      _gap(),
      TimeField(label: 'Until (leave empty if still going)', value: end, baseDate: date, clearable: true, onChanged: (v) => set(() => end = v)),
      if (quick.isNotEmpty) ...[
        _gap(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in quick)
            ChoiceChip(label: Text(q), selected: reason.text == q, onSelected: (_) => set(() => reason.text = q)),
        ]),
      ],
      _gap(),
      textField(reason, needsReason ? 'Reason' : 'Note', required: needsReason, maxLines: 2),
    ],
  );
}

Future<bool?> endDowntimeSheet(BuildContext context, {required Json att, required String date}) {
  final p = att.obj('open_downtime');
  var end = date == Fmt.today() ? Fmt.nowWall() : defaultTime(date, start: false);
  final type = p.str('downtime_type');
  return showActionSheet(
    context,
    title: 'Resume work',
    subtitle: '${att.str('equipment_code')} · $type since ${Fmt.time(p.str('start_time'))}',
    icon: Icons.play_arrow_rounded,
    color: AppColors.working,
    submitLabel: 'Back to work',
    submit: () => Api.I.post('/equipment/attendance/${att.intv('eq_attendance_id')}/downtime/${p.intv('downtime_id')}/end', {'end_time': end}),
    body: (ctx, set) => [
      TimeField(label: 'End of $type', value: end, baseDate: date, onChanged: (v) => set(() => end = v ?? end)),
    ],
  );
}

// ----------------------------------------------------------------- check-out
Future<bool?> checkOutSheet(BuildContext context, {required Json machine, required Json att, required String date, required String shift}) {
  var time = date == Fmt.today() && att.str('record_date') == date ? Fmt.nowWall() : defaultTime(att.str('record_date'), start: false, shift: shift);
  final meter = TextEditingController();
  final work = TextEditingController(text: att.str('work_description'));
  final remarks = TextEditingController();
  final hasMeter = machine.str('meter_unit', 'Hours') != 'None';
  final meterStart = att.dblOrNull('meter_start');
  return showActionSheet(
    context,
    title: 'Check out ${att.str('equipment_code')}',
    subtitle: 'Started ${Fmt.time(att.str('check_in_time'))}',
    icon: Icons.logout_rounded,
    color: AppColors.navy,
    submitLabel: 'Finish the day',
    submit: () async {
      final m = numOrNull(meter);
      if (m != null && meterStart != null && m < meterStart) {
        throw ApiException(null, 'VALIDATION', 'The end meter ($m) is lower than the start meter ($meterStart).');
      }
      await Api.I.post('/equipment/attendance/${att.intv('eq_attendance_id')}/check-out', {
        'check_out_time': time,
        if (m != null) 'meter_end': m,
        if (textOrNull(work) != null) 'work_description': textOrNull(work),
        if (textOrNull(remarks) != null) 'remarks': textOrNull(remarks),
      });
    },
    body: (ctx, set) => [
      TimeField(label: 'End time', value: time, baseDate: att.str('record_date'), onChanged: (v) => set(() => time = v ?? time)),
      _gap(),
      // daily fuel is not recorded here: fuel is handled by the approximate-fuel policy and the office's fuel issues
      if (hasMeter) ...[
        textField(meter, 'Meter at end', number: true, hint: meterStart == null ? null : 'start ${att.str('meter_start')}'),
        _gap(),
      ],
      textField(work, 'Work done today', maxLines: 2, hint: 'e.g. excavation zone B, loading trucks'),
      _gap(),
      textField(remarks, 'Remarks', maxLines: 2),
    ],
  );
}

// ----------------------------------------------------------------- full-day status
Future<bool?> dayStatusSheet(BuildContext context,
    {required Json machine, required int siteId, required String shift, required String date, String? initial, Json access = const {}}) async {
  var status = initial ?? 'Standby';
  final late = TextEditingController();
  var withTimes = false;
  var from = defaultTime(date, start: true, shift: shift);
  var to = defaultTime(date, start: false, shift: shift);
  final remarks = TextEditingController();
  var discard = false;

  Future<void> send() async {
    final r = await Api.I.request('POST', '/equipment/attendance/day-status', body: {
      'equipment_id': machine.intv('equipment_id'), 'site_id': siteId, 'shift_type': shift, 'record_date': date,
      'day_status': status, if (withTimes && (status == 'Standby' || status == 'Breakdown')) ...{'check_in_time': from, 'check_out_time': to},
      if (textOrNull(remarks) != null) 'remarks': textOrNull(remarks), 'confirm_discard_session': discard,
      if (textOrNull(late) != null) 'late_reason': textOrNull(late),
    });
    if (context.mounted) showWarnings(context, r);
  }

  return showActionSheet(
    context,
    title: 'Whole day for ${machine.str('equipment_code')}',
    subtitle: 'Use when the machine did not work at all on ${Fmt.dayLabel(date)}',
    icon: Icons.event_busy_rounded,
    color: StateStyle.of(status).color,
    submitLabel: 'Save day',
    submit: () async {
      try {
        await send();
      } on ApiException catch (e) {
        if (e.code != 'SESSION_WILL_BE_DISCARDED') rethrow;
        // ask once, then replace the recorded session
        if (!context.mounted) rethrow;
        final ok = await confirmDialog(context, 'Replace the recorded session?',
            'This machine already has working times that day. They are replaced by this day status (the old times stay in the history).', confirm: 'Replace', danger: true);
        if (!ok) throw ApiException(null, 'CANCELLED', 'Nothing changed.');
        discard = true;
        await send();
      }
    },
    body: (ctx, set) => [
      ...lateReasonFields(access, late),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'Standby', label: Text('Standby')),
          ButtonSegment(value: 'Breakdown', label: Text('Breakdown')),
          ButtonSegment(value: 'Absent', label: Text('Absent')),
          ButtonSegment(value: 'Holiday', label: Text('Holiday')),
        ],
        selected: {status},
        onSelectionChanged: (v) => set(() {
          status = v.first;
          remarks.clear();
        }),
      ),
      const SizedBox(height: 8),
      Text(
        {
          'Standby': 'On site and ready, but no work was given (billed at the standby % of the price).',
          'Breakdown': 'Broken the whole day (normally not billed).',
          'Absent': 'The machine did not come to the site.',
          'Holiday': 'Official day off.',
        }[status]!,
        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
      ),
      if (status == 'Standby' || status == 'Breakdown') ...[
        _gap(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in status == 'Breakdown' ? breakdownReasons : standbyReasons)
            ChoiceChip(label: Text(q), selected: remarks.text == q, onSelected: (_) => set(() => remarks.text = q)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: withTimes,
          onChanged: (v) => set(() => withTimes = v),
          title: const Text('Record the hours on site'),
        ),
        if (withTimes) ...[
          TimeField(label: 'From', value: from, baseDate: date, onChanged: (v) => set(() => from = v ?? from)),
          _gap(),
          TimeField(label: 'To', value: to, baseDate: date, onChanged: (v) => set(() => to = v ?? to)),
        ],
      ],
      _gap(),
      textField(remarks, status == 'Standby' || status == 'Breakdown' ? 'Reason' : 'Remarks', required: status == 'Standby' || status == 'Breakdown', maxLines: 2),
    ],
  );
}

// ----------------------------------------------------------------- edit a row
Future<bool?> editRowSheet(BuildContext context, {required Json att, int? vendorId}) {
  final working = att.str('day_status') == 'Working';
  final timed = working || att.strOrNull('check_in_time') != null;
  var inT = att.strOrNull('check_in_time');
  var outT = att.strOrNull('check_out_time');
  final mStart = TextEditingController(text: att.str('meter_start'));
  final mEnd = TextEditingController(text: att.str('meter_end'));
  final work = TextEditingController(text: att.str('work_description'));
  final remarks = TextEditingController(text: att.str('remarks'));
  final date = att.str('record_date');
  return showActionSheet(
    context,
    title: 'Edit ${att.str('equipment_code')} · ${Fmt.dayLabel(date)}',
    subtitle: 'Sheet row #${att.obj('sheet').str('sheet_row_no')}',
    icon: Icons.edit_rounded,
    color: AppColors.navy,
    submitLabel: 'Save changes',
    submit: () {
      final body = <String, dynamic>{};
      if (inT != att.strOrNull('check_in_time') && inT != null) body['check_in_time'] = inT;
      if (outT != att.strOrNull('check_out_time') && outT != null) body['check_out_time'] = outT;
      if (working) {
        if (mStart.text.trim() != att.str('meter_start') && numOrNull(mStart) != null) body['meter_start'] = numOrNull(mStart);
        if (mEnd.text.trim() != att.str('meter_end') && numOrNull(mEnd) != null) body['meter_end'] = numOrNull(mEnd);
        if (work.text.trim() != att.str('work_description')) body['work_description'] = work.text.trim();
      }
      if (remarks.text.trim() != att.str('remarks')) body['remarks'] = remarks.text.trim();
      if (body.isEmpty) return Future.value();
      return Api.I.patch('/equipment/attendance/${att.intv('eq_attendance_id')}', body);
    },
    body: (ctx, set) => [
      if (timed) ...[
        TimeField(label: 'Start', value: inT, baseDate: date, onChanged: (v) => set(() => inT = v ?? inT)),
        _gap(),
        TimeField(label: 'End', value: outT, baseDate: date, onChanged: (v) => set(() => outT = v ?? outT)),
        _gap(),
      ],
      if (working) ...[
        Row(children: [
          Expanded(child: textField(mStart, 'Meter start', number: true)),
          const SizedBox(width: 12),
          Expanded(child: textField(mEnd, 'Meter end', number: true)),
        ]),
        _gap(),
        textField(work, 'Work done', maxLines: 2),
        _gap(),
      ],
      textField(remarks, 'Remarks', maxLines: 2),
    ],
  );
}

// ----------------------------------------------------------------- correct a pause in place
/// Changes the type, times or reason of one pause of an editable row (instead of deleting and re-adding it).
Future<bool?> downtimeEditSheet(BuildContext context, {required Json att, required Json period}) {
  final date = att.str('record_date');
  final oldType = period.str('downtime_type');
  final oldStart = wall16(period.strOrNull('start_time'));
  final oldEnd = wall16(period.strOrNull('end_time'));
  var type = oldType;
  var start = oldStart ?? defaultTime(date, start: true);
  var end = oldEnd;
  final reason = TextEditingController(text: period.str('reason'));
  bool needsReason() => type == 'Breakdown' || type == 'Standby';
  return showActionSheet(
    context,
    title: 'Correct this pause',
    subtitle: '${att.str('equipment_code')} · ${Fmt.dayLabel(date)}',
    icon: Icons.edit_calendar_rounded,
    color: AppColors.navy,
    submitLabel: 'Save',
    submit: () async {
      final body = <String, dynamic>{
        if (type != oldType) 'downtime_type': type,
        if (start != oldStart) 'start_time': start,
        if (end != null && end != oldEnd) 'end_time': end,
        if (reason.text.trim() != period.str('reason') && reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
      };
      if (body.isEmpty) return;
      await Api.I.patch('/equipment/attendance/${att.intv('eq_attendance_id')}/downtime/${period.intv('downtime_id')}', body);
    },
    body: (ctx, set) => [
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'Break', label: Text('Break')),
          ButtonSegment(value: 'Refuel', label: Text('Refuel')),
          ButtonSegment(value: 'Breakdown', label: Text('Breakdown')),
          ButtonSegment(value: 'Standby', label: Text('Standby')),
        ],
        selected: {type},
        onSelectionChanged: (v) => set(() => type = v.first),
      ),
      _gap(),
      TimeField(label: 'From', value: start, baseDate: date, onChanged: (v) => set(() => start = v ?? start)),
      _gap(),
      TimeField(label: oldEnd == null ? 'Until (leave empty if still going)' : 'Until', value: end, baseDate: date, onChanged: (v) => set(() => end = v ?? end)),
      _gap(),
      textField(reason, needsReason() ? 'Reason' : 'Note', required: needsReason(), maxLines: 2),
    ],
  );
}

// ----------------------------------------------------------------- ask the office for a change
/// For rows the supervisor may not change directly (Approved, or a day before their assignment to the site):
/// several fields in one request, with a reason. The Admin or the Accountant applies it (or turns it into an official
/// Correction when the period is already paid).
Future<bool?> changeRequestSheet(BuildContext context, {required Json att}) {
  final date = att.str('record_date');
  final oldStatus = att.str('day_status');
  final oldIn = wall16(att.strOrNull('check_in_time'));
  final oldOut = wall16(att.strOrNull('check_out_time'));
  var status = oldStatus;
  var inT = oldIn;
  var outT = oldOut;
  final mStart = TextEditingController(text: att.str('meter_start'));
  final mEnd = TextEditingController(text: att.str('meter_end'));
  final work = TextEditingController(text: att.str('work_description'));
  final remarks = TextEditingController(text: att.str('remarks'));
  final reason = TextEditingController();
  return showActionSheet(
    context,
    title: 'Ask the office to change this row',
    subtitle: '${att.str('equipment_code')} · ${Fmt.dayLabel(date)} · row #${att.obj('sheet').str('sheet_row_no')}',
    icon: Icons.forward_to_inbox_rounded,
    color: AppColors.navy,
    submitLabel: 'Send the request',
    submit: () async {
      final changes = <String, dynamic>{};
      if (status != oldStatus) changes['day_status'] = status;
      final timed = status == 'Working' || status == 'Standby' || status == 'Breakdown';
      if (status == 'Working' && (inT == null || outT == null)) {
        throw ApiException(null, 'VALIDATION', 'A working day needs the start and the end time: set both.');
      }
      if (!timed && (oldIn != null || oldOut != null)) {
        changes['check_in_time'] = null;
        changes['check_out_time'] = null;
      } else {
        if (inT != oldIn && inT != null) changes['check_in_time'] = inT;
        if (outT != oldOut && outT != null) changes['check_out_time'] = outT;
      }
      if (mStart.text.trim() != att.str('meter_start') && numOrNull(mStart) != null) changes['meter_start'] = numOrNull(mStart);
      if (mEnd.text.trim() != att.str('meter_end') && numOrNull(mEnd) != null) changes['meter_end'] = numOrNull(mEnd);
      if (work.text.trim() != att.str('work_description')) changes['work_description'] = work.text.trim();
      if (remarks.text.trim() != att.str('remarks')) changes['remarks'] = remarks.text.trim();
      if (changes.isEmpty) throw ApiException(null, 'VALIDATION', 'Change at least one value: nothing differs from the row.');
      await Api.I.post('/equipment/attendance/${att.intv('eq_attendance_id')}/change-requests', {'reason': reason.text.trim(), 'changes': changes});
      if (context.mounted) showSnack(context, 'Request sent. The Admin or the Accountant decides; you see the answer in "My change requests".');
    },
    body: (ctx, set) => [
      const NoticeBox(
        text: 'You cannot change this row yourself. Write the correct values (all the fields that are wrong) and why. '
            'Nothing changes until the office approves.',
      ),
      DropdownButtonFormField<String>(
        initialValue: status,
        decoration: const InputDecoration(labelText: 'Day status'),
        items: [for (final x in const ['Working', 'Standby', 'Breakdown', 'Absent', 'Holiday']) DropdownMenuItem(value: x, child: Text(x))],
        onChanged: (v) => set(() => status = v ?? status),
      ),
      if (status == 'Working' || status == 'Standby' || status == 'Breakdown') ...[
        _gap(),
        TimeField(label: 'Start', value: inT, baseDate: date, onChanged: (v) => set(() => inT = v ?? inT)),
        _gap(),
        TimeField(label: 'End', value: outT, baseDate: date, onChanged: (v) => set(() => outT = v ?? outT)),
      ],
      if (status == 'Working') ...[
        _gap(),
        Row(children: [
          Expanded(child: textField(mStart, 'Meter start', number: true)),
          const SizedBox(width: 12),
          Expanded(child: textField(mEnd, 'Meter end', number: true)),
        ]),
        _gap(),
        textField(work, 'Work done', maxLines: 2),
      ],
      _gap(),
      textField(remarks, 'Remarks', maxLines: 2),
      _gap(),
      TextFormField(
        controller: reason,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Why must it change? *', hintText: 'e.g. the signed sheet shows 06:30 - 16:00'),
        validator: (v) => (v ?? '').trim().length < 5 ? 'Write at least 5 characters' : null,
      ),
    ],
  );
}
