import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/file_save.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Daily equipment timesheet (Excel, ready to print): every machine of the day in ONE sheet, grouped
/// Site > Shift > Vendor, with the Supervisor / Approved by signatures at the end.
/// Machines with nothing recorded stay empty, so the sheet can be printed and filled by hand; a recorded
/// machine comes out filled. Supervisor: his own sites. Admin / Accountant: every site, or one site.
class DailyTimesheetSheet extends StatefulWidget {
  const DailyTimesheetSheet({super.key, this.initialDate, this.showSitePicker = false});

  final String? initialDate;
  final bool showSitePicker;

  /// Opens the sheet; when the file is saved, the confirmation is shown on the calling screen.
  static Future<void> open(BuildContext context, {String? date}) async {
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DailyTimesheetSheet(initialDate: date, showSitePicker: !Auth.I.isSupervisor),
    );
    if (msg != null && context.mounted) showSnack(context, msg);
  }

  @override
  State<DailyTimesheetSheet> createState() => _DailyTimesheetSheetState();
}

class _DailyTimesheetSheetState extends State<DailyTimesheetSheet> {
  /// The server accepts a day up to 31 days ahead (a blank sheet printed before the day).
  static const _maxDaysAhead = 31;

  late String _date;
  String _shift = 'All';
  PickOption? _site;
  bool _busy = false;
  String? _error;

  /// [date] + [days] as yyyy-MM-dd (calendar days, safe across daylight-saving changes).
  static String _addDays(String date, int days) {
    final d = Fmt.parse(date) ?? Fmt.now();
    return Fmt.dateOf(DateTime(d.year, d.month, d.day + days));
  }

  String get _today => Fmt.today();
  String get _lastDate => _addDays(_today, _maxDaysAhead);

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate ?? _today;
    _date = init.compareTo(_lastDate) > 0 ? _lastDate : init;
  }

  void _setDate(String d) => setState(() {
        _date = d;
        _error = null;
      });

  String get _fileName {
    final shift = _shift == 'All' ? 'All-shifts' : '$_shift-shift';
    final site = _site == null ? '' : '-${_site!.label.trim().split(RegExp(r'\s+')).first}';
    return 'Timesheet-$_date-$shift$site.xlsx'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final siteId = _site?.value;
      final bytes = await Api.I.getBytes('/equipment/reports/daily-timesheet.xlsx', query: {
        'date': _date,
        'shift': _shift,
        if (siteId != null) 'site_id': siteId,
      });
      final msg = await FileSave.save(bytes, _fileName);
      if (!mounted) return;
      Navigator.pop(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : 'Could not prepare the timesheet. Check the connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final quick = <String, String>{'Yesterday': _addDays(today, -1), 'Today': today, 'Tomorrow': _addDays(today, 1)};
    final otherDay = !quick.containsValue(_date);
    final future = _date.compareTo(today) > 0;
    final d = Fmt.parse(_date);
    final longDay = d == null ? _date : '${Fmt.dayLabel(_date)} ${d.year}';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Center(
        heightFactor: 1, // as tall as its content (a Center alone would fill the whole sheet)
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.table_view_rounded, color: AppColors.gold),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Daily timesheet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    Text('Excel file, ready to print', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                widget.showSitePicker
                    ? 'Every machine of the day in one sheet, by site, shift and vendor, with the signatures at the end.'
                    : 'All the machines of your sites in one sheet, by site, shift and vendor, with the signatures at the end.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const _Label('Day'),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final e in quick.entries)
                  ChoiceChip(
                    label: Text(e.key),
                    selected: _date == e.value,
                    onSelected: _busy ? null : (_) => _setDate(e.value),
                  ),
                ChoiceChip(
                  avatar: Icon(Icons.event_rounded, size: 18, color: otherDay ? AppColors.navy : AppColors.muted),
                  label: Text(otherDay ? Fmt.dayLabel(_date) : 'Other day'),
                  selected: otherDay,
                  showCheckmark: false,
                  onSelected: _busy
                      ? null
                      : (_) async {
                          final picked = await pickDate(context, initial: _date, last: _lastDate);
                          if (picked != null && mounted) _setDate(picked);
                        },
                ),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(future ? Icons.edit_note_rounded : Icons.fact_check_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    future
                        ? '$longDay has not been recorded yet: the sheet comes out empty, ready to fill by hand.'
                        : '$longDay: recorded machines come out filled, the others stay empty to fill by hand.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              const _Label('Shift'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('Both shifts')),
                  ButtonSegment(value: 'Day', label: Text('Day'), icon: Icon(Icons.wb_sunny_rounded)),
                  ButtonSegment(value: 'Night', label: Text('Night'), icon: Icon(Icons.nightlight_round)),
                ],
                selected: {_shift},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() {
                          _shift = s.first;
                          _error = null;
                        }),
              ),
              if (widget.showSitePicker) ...[
                const SizedBox(height: 18),
                const _Label('Site'),
                PickerField(
                  label: _site == null ? 'All sites' : 'Site',
                  valueLabel: _site?.label,
                  icon: Icons.location_city_rounded,
                  enabled: !_busy,
                  load: () => Lookups.sites(),
                  onChanged: (p) => setState(() {
                    _site = p;
                    _error = null;
                  }),
                ),
              ],
              const SizedBox(height: 20),
              if (_error != null) NoticeBox(text: _error!, color: AppColors.breakdown, icon: Icons.error_outline_rounded),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded),
                  label: Text(_busy ? 'Preparing the sheet...' : 'Download Excel'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12)),
      );
}
