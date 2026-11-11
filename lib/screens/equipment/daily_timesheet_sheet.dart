import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/file_save.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Weekly equipment timesheet (Excel, ready to print). It replaced the daily one (Nov 2026); the file keeps its name.
/// One sheet per vendor, one box per machine with a line per day (Saturday to Thursday; Friday only when worked):
/// In, Out, Lunch (min), Our supervisor / Vendor driver signatures, Remarks; Accountant and Administration at the end.
/// Recorded days come out filled, the others stay empty to fill by hand.
/// Supervisor: his own sites. Admin / Accountant: every site, or one site.
class WeeklyTimesheetSheet extends StatefulWidget {
  const WeeklyTimesheetSheet({super.key, this.initialDate, this.showSitePicker = false});

  final String? initialDate;
  final bool showSitePicker;

  /// Opens the sheet; when the file is saved, the confirmation is shown on the calling screen.
  static Future<void> open(BuildContext context, {String? date}) async {
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => WeeklyTimesheetSheet(initialDate: date, showSitePicker: !Auth.I.isSupervisor),
    );
    if (msg != null && context.mounted) showSnack(context, msg);
  }

  @override
  State<WeeklyTimesheetSheet> createState() => _WeeklyTimesheetSheetState();
}

class _WeeklyTimesheetSheetState extends State<WeeklyTimesheetSheet> {
  /// The server accepts a day up to 31 days ahead (a blank sheet printed before the week).
  static const _maxDaysAhead = 31;

  late String _date;
  String _shift = 'All';
  PickOption? _site;
  bool _busy = false;
  String? _error;

  /// The week of [_date] as the server counts it (the weekly off day is a setting): label, from, to.
  String? _weekLabel;
  String? _weekFrom;
  String? _weekTo;
  bool _weekLoading = false;
  int _weekRequest = 0;

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
    _weekLoading = true;
    _loadWeek();
  }

  Future<void> _loadWeek() async {
    final req = ++_weekRequest; // only the answer of the latest request is shown
    try {
      final w = await Api.I.getObj('/equipment/reports/weekly-timesheet/week', query: {'date': _date});
      if (!mounted || req != _weekRequest) return;
      setState(() {
        _weekLabel = w['label']?.toString();
        _weekFrom = w['from']?.toString();
        _weekTo = w['to']?.toString();
        _weekLoading = false;
      });
    } catch (_) {
      if (!mounted || req != _weekRequest) return;
      setState(() {
        _weekLabel = null;
        _weekFrom = null;
        _weekTo = null;
        _weekLoading = false;
      });
    }
  }

  void _setDate(String d) {
    setState(() {
      _date = d;
      _error = null;
      _weekLoading = true;
      _weekLabel = null;
      _weekFrom = null;
      _weekTo = null;
    });
    _loadWeek();
  }

  /// The quick choices: a day inside each week.
  Map<String, String> get _quick => {
        'Last week': _addDays(_today, -7),
        'This week': _today,
        'Next week': _addDays(_today, 7),
      };

  /// The quick choice whose week holds [_date] (null when another week is chosen).
  String? get _selectedQuick {
    for (final e in _quick.entries) {
      if (e.value == _date) return e.key;
    }
    final from = _weekFrom;
    final to = _weekTo;
    if (from == null || to == null) return null;
    for (final e in _quick.entries) {
      // the off day after "to" still belongs to the week
      if (e.value.compareTo(from) >= 0 && e.value.compareTo(_addDays(to, 1)) <= 0 && _date.compareTo(from) >= 0 && _date.compareTo(_addDays(to, 1)) <= 0) {
        return e.key;
      }
    }
    return null;
  }

  String get _fileName {
    final week = _weekFrom != null && _weekTo != null ? '${_weekFrom}_to_$_weekTo' : _date;
    final shift = _shift == 'All' ? '' : '-$_shift';
    final site = _site == null ? '' : '-${_site!.label.trim().split(RegExp(r'\s+')).first}';
    return 'Weekly-Timesheet-$week$shift$site.xlsx'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final siteId = _site?.value;
      final bytes = await Api.I.getBytes('/equipment/reports/weekly-timesheet.xlsx', query: {
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
    final selected = _selectedQuick;
    final otherWeek = selected == null;
    final weekText = _weekLabel ?? (_weekLoading ? 'Finding the week...' : 'Week of ${Fmt.date(_date)}');

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
                    Text('Weekly timesheet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    Text('Excel file, ready to print', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                widget.showSitePicker
                    ? 'One sheet per vendor, a box per machine with a line per day to sign. Accountant and Administration sign at the end.'
                    : 'One sheet per vendor for your sites, a box per machine with a line per day to sign.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const _Label('Week'),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final e in _quick.entries)
                  ChoiceChip(
                    label: Text(e.key),
                    selected: selected == e.key,
                    onSelected: _busy ? null : (_) => _setDate(e.value),
                  ),
                ChoiceChip(
                  avatar: Icon(Icons.event_rounded, size: 18, color: otherWeek ? AppColors.navy : AppColors.muted),
                  label: Text(otherWeek ? 'Week of ${Fmt.dayLabel(_date)}' : 'Other week'),
                  selected: otherWeek,
                  showCheckmark: false,
                  onSelected: _busy
                      ? null
                      : (_) async {
                          final picked = await pickDate(context, initial: _date, last: _lastDate);
                          if (picked != null && mounted) _setDate(picked);
                        },
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.date_range_rounded, size: 18, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(child: Text(weekText, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                ]),
              ),
              const SizedBox(height: 6),
              const Text(
                'Days already recorded come out filled; the others stay empty to fill by hand. Signature boxes are always empty.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
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
