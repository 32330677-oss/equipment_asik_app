import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';

/// Monthly paper sheets: progress of scans and reconciliation.
class TimesheetsScreen extends StatefulWidget {
  const TimesheetsScreen({super.key});
  @override
  State<TimesheetsScreen> createState() => _TimesheetsScreenState();
}

class _TimesheetsScreenState extends State<TimesheetsScreen> {
  final _s = Loadable<List<Json>>();
  String _month = Fmt.thisMonth();
  String? _needs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/timesheets', query: {'month': _month, 'needs': _needs});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  void _shiftMonth(int delta) {
    final d = DateTime.parse('$_month-01');
    _month = Fmt.dateOf(DateTime(d.year, d.month + delta, 1)).substring(0, 7);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sheets = _s.data ?? <Json>[];
    final rows = sheets.fold<int>(0, (a, s) => a + s.intv('rows_count'));
    final matched = sheets.fold<int>(0, (a, s) => a + s.intv('matched'));
    final mism = sheets.fold<int>(0, (a, s) => a + s.intv('mismatch'));
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Paper sheets', subtitle: 'One signed sheet per machine, site and month - scan, compare, close', actions: [
          IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
          Text(Fmt.monthLabel(_month), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
          Dropdown<String?>(label: 'Show', value: _needs, width: 170, items: const [
            DropdownMenuItem(value: null, child: Text('All sheets')),
            DropdownMenuItem(value: 'scan', child: Text('Needs a scan')),
            DropdownMenuItem(value: 'check', child: Text('Needs checking')),
          ], onChanged: (v) { _needs = v; _load(); }),
        ]),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'Sheets', value: '${sheets.length}', icon: Icons.description_rounded),
          KpiTile(label: 'Rows matched', value: '$matched / $rows', color: AppColors.working, icon: Icons.verified_rounded),
          KpiTile(label: 'Mismatches', value: '$mism', color: AppColors.breakdown, icon: Icons.error_rounded),
          KpiTile(label: 'Need a scan', value: '${sheets.where((s) => s.flag('needs_scan')).length}', color: AppColors.standby, icon: Icons.document_scanner_rounded),
        ]),
        const SizedBox(height: 14),
        if (_s.loading && _s.data == null) const LoadingView()
        else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
        else if (sheets.isEmpty) const Card(child: EmptyView(text: 'No sheet for this month yet. A sheet is created with the first attendance row of a machine.', icon: Icons.description_outlined))
        else TableCard(
          columns: const [
            DataColumn(label: Text('Sheet')), DataColumn(label: Text('Machine')), DataColumn(label: Text('Site')), DataColumn(label: Text('Vendor')),
            DataColumn(label: Text('Progress')), DataColumn(label: Text('Last scan')), DataColumn(label: Text('Status')),
          ],
          rows: [
            for (final s in sheets)
              DataRow(onSelectChanged: (_) => _open(s), cells: [
                DataCell(Text(s.str('sheet_code'), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('${s.str('equipment_code')}  ${s.str('type_name')}')),
                DataCell(Text(s.str('site_code'))),
                DataCell(Text(s.str('vendor_name'))),
                DataCell(SizedBox(width: 170, child: _Progress(total: s.intv('rows_count'), matched: s.intv('matched'), mismatch: s.intv('mismatch')))),
                DataCell(Text(s.strOrNull('last_scan_version') == null ? 'No scan' : 'v${s.str('last_scan_version')}  ${Fmt.date(s.str('last_scan_at'))}  (rows 1-${s.str('scanned_through_row')})')),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  Pill(s.str('status'), color: s.str('status') == 'Reconciled' ? AppColors.working : s.str('status') == 'Closed' ? AppColors.info : AppColors.muted),
                  if (s.flag('needs_scan')) ...[const SizedBox(width: 6), const Pill('Scan needed', color: AppColors.standby)],
                ])),
              ]),
          ],
        ),
      ],
    );
  }

  Future<void> _open(Json s) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ReconcileScreen(sheetId: s.intv('timesheet_id'))));
    _load();
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.total, required this.matched, required this.mismatch});
  final int total;
  final int matched;
  final int mismatch;
  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : matched / total;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: AppColors.line, color: mismatch > 0 ? AppColors.standby : AppColors.working),
        ),
      ),
      const SizedBox(width: 8),
      Text('$matched/$total', style: const TextStyle(fontSize: 12)),
    ]);
  }
}

/// Scan on the left, rows on the right; mark each row Matched / Mismatch / Missing.
class ReconcileScreen extends StatefulWidget {
  const ReconcileScreen({super.key, required this.sheetId});
  final int sheetId;
  @override
  State<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<ReconcileScreen> {
  Json? _sheet;
  Object? _error;
  int? _scanId;
  Uint8List? _scanBytes;
  bool _scanLoading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Api.I.getObj('/equipment/timesheets/${widget.sheetId}');
      final scans = s.list('scans');
      setState(() { _sheet = s; _error = null; });
      if (scans.isNotEmpty && (_scanId == null || !scans.any((x) => x.intv('scan_id') == _scanId))) {
        _loadScan(scans.first.intv('scan_id'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadScan(int id) async {
    setState(() { _scanId = id; _scanLoading = true; _scanBytes = null; });
    try {
      final b = await Api.I.getBytes('/equipment/timesheets/${widget.sheetId}/scans/$id/file');
      if (mounted) setState(() => _scanBytes = b);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _scanLoading = false);
  }

  Future<void> _check(Json row, String result, {String? note, String? paperIn, String? paperOut, bool signed = true}) async {
    setState(() => _busy = true);
    try {
      final r = asJson(await Api.I.post('/equipment/timesheets/${widget.sheetId}/paper-checks', {
        'scan_id': _scanId,
        'items': [
          {
            'eq_attendance_id': row.intv('eq_attendance_id'), 'result': result, 'note': note,
            'paper_check_in': paperIn, 'paper_check_out': paperOut,
            'employee_signed': signed, 'operator_signed': signed,
          }
        ],
      }));
      final errors = r.list('errors');
      if (errors.isNotEmpty && mounted) showSnack(context, errors.first.str('message'), error: true);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paperValues(Json row) async {
    final res = await showDialog<Json>(context: context, builder: (_) => _PaperDialog(row: row));
    if (res == null) return;
    await _check(row, res.str('result'), note: res.strOrNull('note'), paperIn: res.strOrNull('in'), paperOut: res.strOrNull('out'),
        signed: res.flag('signed'));
  }

  Future<void> _uploadScan() async {
    try {
      final files = await openFiles(acceptedTypeGroups: [const XTypeGroup(label: 'Scan (PDF or photos)', extensions: ['pdf', 'jpg', 'jpeg', 'png'])]);
      if (files.isEmpty) return;
      setState(() => _busy = true);
      final up = <UploadFile>[];
      for (final f in files) {
        up.add(UploadFile(await f.readAsBytes(), f.name));
      }
      final r = asJson(await Api.I.upload('/equipment/timesheets/${widget.sheetId}/scans', up, fileField: 'files'));
      if (mounted) showSnack(context, 'Scan version ${r.str('version_no')} uploaded.');
      _scanId = null;
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final eng = await promptText(context, 'Close the month', label: 'Site engineer (name on the sign-off)', maxLines: 1, confirm: 'Next');
    if (eng == null || !mounted) return;
    final rep = await promptText(context, 'Close the month', label: 'Vendor representative (name on the sign-off)', maxLines: 1, confirm: 'Close sheet');
    if (rep == null) return;
    try {
      final s = asJson(await Api.I.patch('/equipment/timesheets/${widget.sheetId}/close', {'site_engineer_name': eng, 'vendor_rep_name': rep}));
      if (mounted) showSnack(context, 'Sheet ${s.str('status')}.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reopen() async {
    final reason = await promptText(context, 'Reopen the sheet', label: 'Reason');
    if (reason == null) return;
    try {
      await Api.I.patch('/equipment/timesheets/${widget.sheetId}/reopen', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sheet;
    if (s == null) {
      return Scaffold(appBar: AppBar(title: const Text('Paper sheet')), body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());
    }
    final wide = MediaQuery.of(context).size.width >= 1100;
    final rows = s.list('rows');
    final canCheck = Auth.I.isAdmin || Auth.I.isAccountant;
    final scans = s.list('scans');

    final scanPane = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(children: [
            const Icon(Icons.document_scanner_rounded, color: AppColors.navy),
            const SizedBox(width: 8),
            Expanded(
              child: scans.isEmpty
                  ? const Text('No scan uploaded yet')
                  : DropdownButton<int>(
                      value: _scanId,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final sc in scans)
                          DropdownMenuItem(value: sc.intv('scan_id'), child: Text('Version ${sc.str('version_no')} - ${Fmt.date(sc.str('uploaded_at'))} - rows 1-${sc.str('through_row_no')} - ${sc.str('uploaded_by')}')),
                      ],
                      onChanged: (v) { if (v != null) _loadScan(v); },
                    ),
            ),
            FilledButton.tonalIcon(onPressed: _busy ? null : _uploadScan, icon: const Icon(Icons.upload_file_rounded), label: const Text('Upload scan')),
          ]),
        ),
        const Divider(),
        Expanded(
          child: _scanLoading
              ? const LoadingView()
              : _scanBytes == null
                  ? const EmptyView(text: 'Upload a photo or PDF of the signed sheet to compare it with the rows.', icon: Icons.image_search_rounded)
                  : PdfPreview(
                      build: (_) async => _scanBytes!,
                      useActions: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      maxPageWidth: 1100,
                    ),
        ),
      ]),
    );

    final rowsPane = Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: Text('Rows (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text('${rows.where((r) => r.str('paper_status') == 'Matched').length} matched', style: const TextStyle(color: AppColors.working, fontWeight: FontWeight.w700)),
          ]),
        ),
        const Divider(),
        Expanded(
          child: rows.isEmpty
              ? const EmptyView(text: 'No rows on this sheet.')
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final working = r.str('day_status') == 'Working';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(radius: 15, backgroundColor: AppColors.surface, child: Text('${r.intv('sheet_row_no')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(Fmt.dayLabel(r.str('record_date')), style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Text(working ? '${Fmt.time(r.strOrNull('check_in_time'))} - ${Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))}' : r.str('day_status'), style: const TextStyle(color: AppColors.muted)),
                              const SizedBox(width: 8),
                              if (working) Text('${Fmt.hoursFromMinutes(r.intOrNull('working_minutes'))} h', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              PaperPill(r.str('paper_status')),
                              WorkflowPill(r.str('status')),
                              if (r.strOrNull('operator_name') != null) Text(r.str('operator_name'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              if (r.objOrNull('current_check') != null && r.obj('current_check').strOrNull('note') != null)
                                Text('"${r.obj('current_check').str('note')}"', style: const TextStyle(color: AppColors.breakdown, fontSize: 12)),
                            ]),
                          ]),
                        ),
                        if (canCheck && s.str('status') != 'Reconciled')
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Tooltip(
                              message: 'Matches the paper, both signatures present',
                              child: IconButton.filledTonal(
                                onPressed: _busy || r.str('paper_status') == 'Matched' ? null : () => _check(r, 'Matched'),
                                icon: const Icon(Icons.check_rounded, color: AppColors.working),
                              ),
                            ),
                            Tooltip(
                              message: 'Different on paper / missing signature / not on the scan',
                              child: IconButton(onPressed: _busy ? null : () => _paperValues(r), icon: const Icon(Icons.edit_note_rounded)),
                            ),
                          ]),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(s.str('sheet_code')),
        actions: [
          TextButton.icon(
            onPressed: () => PdfViewScreen.open(context,
                title: 'Print ${s.str('sheet_code')}',
                fileName: '${s.str('sheet_code')}.pdf',
                load: () => Api.I.getBytes('/equipment/timesheets/${widget.sheetId}/print.pdf')),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Print sheet'),
          ),
          if (canCheck && s.str('status') == 'Open') TextButton.icon(onPressed: _close, icon: const Icon(Icons.lock_rounded), label: const Text('Close month')),
          if (Auth.I.isAdmin && s.str('status') != 'Open') TextButton.icon(onPressed: _reopen, icon: const Icon(Icons.lock_open_rounded), label: const Text('Reopen')),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${s.str('equipment_code')} ${s.str('type_name')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${s.str('site_code')} - ${s.str('site_name')}  |  ${s.str('vendor_name')}  |  ${Fmt.monthLabel(s.str('period_month'))}', style: const TextStyle(color: AppColors.muted)),
            Pill(s.str('status'), color: s.str('status') == 'Reconciled' ? AppColors.working : s.str('status') == 'Closed' ? AppColors.info : AppColors.muted),
            if (s.list('cancelled_rows').isNotEmpty || (s['cancelled_rows'] as List?)?.isNotEmpty == true)
              Pill('Cancelled rows: ${(s['cancelled_rows'] as List).join(', ')}', color: AppColors.neutral),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 6, child: scanPane),
                    const SizedBox(width: 14),
                    Expanded(flex: 5, child: rowsPane),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 5, child: scanPane),
                    const SizedBox(height: 12),
                    Expanded(flex: 6, child: rowsPane),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _PaperDialog extends StatefulWidget {
  const _PaperDialog({required this.row});
  final Json row;
  @override
  State<_PaperDialog> createState() => _PaperDialogState();
}

class _PaperDialogState extends State<_PaperDialog> {
  String _result = 'Mismatch';
  String? _in;
  String? _out;
  bool _signed = true;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _in = widget.row.strOrNull('check_in_time')?.substring(0, 16);
    _out = widget.row.strOrNull('check_out_time')?.substring(0, 16);
  }

  @override
  Widget build(BuildContext context) {
    final working = widget.row.strOrNull('check_in_time') != null;
    return AlertDialog(
      title: Text('Row #${widget.row.str('sheet_row_no')} on paper'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Matched', label: Text('Matches')),
              ButtonSegment(value: 'Mismatch', label: Text('Different')),
              ButtonSegment(value: 'Missing', label: Text('Not on scan')),
            ],
            selected: {_result},
            onSelectionChanged: (v) => setState(() => _result = v.first),
          ),
          const SizedBox(height: 14),
          if (working && _result != 'Missing') ...[
            const Text('Times written on the paper', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async { final v = await pickDateTime(context, initial: _in); if (v != null) setState(() => _in = v); }, child: Text('In ${Fmt.time(_in == null ? null : '$_in:00')}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () async { final v = await pickDateTime(context, initial: _out); if (v != null) setState(() => _out = v); }, child: Text('Out ${Fmt.time(_out == null ? null : '$_out:00')}'))),
            ]),
            const SizedBox(height: 10),
          ],
          if (_result != 'Missing')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _signed,
              onChanged: (v) => setState(() => _signed = v ?? false),
              title: const Text('Employee and operator both signed'),
            ),
          TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: _result == 'Mismatch' ? 'What is different? (required)' : 'Note (optional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_result == 'Mismatch' && _note.text.trim().isEmpty) return;
            Navigator.pop(context, <String, dynamic>{
              'result': _result, 'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
              'in': working ? _in : null, 'out': working ? _out : null, 'signed': _signed,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
