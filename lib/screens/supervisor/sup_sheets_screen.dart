import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';

bool get _isPhone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Supervisor view of the monthly paper sheets: print, photograph the signed sheet, see versions.
class SupSheetsScreen extends StatefulWidget {
  const SupSheetsScreen({super.key});
  @override
  State<SupSheetsScreen> createState() => _SupSheetsScreenState();
}

class _SupSheetsScreenState extends State<SupSheetsScreen> {
  String _month = Fmt.thisMonth();
  final _s = Loadable<List<Json>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/timesheets', query: {'month': _month});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  void _shift(int months) {
    final d = DateTime.parse('$_month-01');
    final n = DateTime(d.year, d.month + months, 1);
    if (n.isAfter(DateTime.now())) return;
    setState(() => _month = '${n.year}-${n.month.toString().padLeft(2, '0')}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final toScan = rows.where((r) => r.flag('needs_scan')).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Paper sheets')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(children: [
                      IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                      Expanded(child: Text(Fmt.monthLabel(_month), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      IconButton(onPressed: _month == Fmt.thisMonth() ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                    ]),
                  ),
                ),
                if (toScan > 0)
                  Card(
                    color: const Color(0xFFFFF6E5),
                    child: ListTile(
                      leading: const Icon(Icons.photo_camera_rounded, color: AppColors.standby),
                      title: Text('$toScan sheet(s) have new rows not photographed yet', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Photograph the signed paper after each day or week.'),
                    ),
                  ),
                const SizedBox(height: 6),
                if (_s.loading && _s.data == null)
                  const LoadingView()
                else if (_s.error != null)
                  ErrorView(error: _s.error!, onRetry: _load)
                else if (rows.isEmpty)
                  const Card(child: EmptyView(text: 'No sheet this month. A sheet starts with the first check-in of the machine.', icon: Icons.description_rounded))
                else
                  for (final r in rows)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => SupSheetDetailScreen(id: r.intv('timesheet_id'))));
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.description_rounded, color: AppColors.navy),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${r.str('equipment_code')}  ${r.str('type_name')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text('${r.str('site_code')}  ·  ${r.str('sheet_code')}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                const SizedBox(height: 4),
                                Text('${r.str('last_row_no')} row(s)  ·  photographed up to row ${r.str('scanned_through_row', '0')}',
                                    style: const TextStyle(fontSize: 12.5)),
                              ]),
                            ),
                            if (r.flag('needs_scan'))
                              const Pill('Photo needed', color: AppColors.standby, icon: Icons.photo_camera_rounded)
                            else if (r.str('status') == 'Closed')
                              const Pill('Closed', color: AppColors.neutral)
                            else
                              const Pill('Up to date', color: AppColors.working),
                          ]),
                        ),
                      ),
                    ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class SupSheetDetailScreen extends StatefulWidget {
  const SupSheetDetailScreen({super.key, required this.id});
  final int id;
  @override
  State<SupSheetDetailScreen> createState() => _SupSheetDetailScreenState();
}

class _SupSheetDetailScreenState extends State<SupSheetDetailScreen> {
  Json? _s;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Api.I.getObj('/equipment/timesheets/${widget.id}');
      if (mounted) setState(() { _s = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _print() {
    PdfViewScreen.open(context,
        title: 'Sheet ${_s!.str('sheet_code')}',
        fileName: '${_s!.str('sheet_code')}.pdf',
        load: () => Api.I.getBytes('/equipment/timesheets/${widget.id}/print.pdf'));
  }

  Future<void> _upload({required bool camera}) async {
    final files = <UploadFile>[];
    try {
      if (camera) {
        final picker = ImagePicker();
        while (true) {
          final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
          if (x == null) break;
          files.add(UploadFile(await x.readAsBytes(), 'page-${files.length + 1}.jpg'));
          if (!mounted) return;
          final more = await confirmDialog(context, 'Page ${files.length} taken', 'Take a photo of another page?', confirm: 'Next page');
          if (!more) break;
        }
      } else {
        final picked = await openFiles(acceptedTypeGroups: [const XTypeGroup(label: 'Scan (PDF or photos)', extensions: ['pdf', 'jpg', 'jpeg', 'png'])]);
        for (final f in picked) {
          files.add(UploadFile(await f.readAsBytes(), f.name));
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = asJson(await Api.I.upload('/equipment/timesheets/${widget.id}/scans', files, fileField: 'files'));
      if (mounted) showSnack(context, 'Version ${r.str('version_no')} uploaded (${r.str('page_count')} page(s), up to row ${r.str('through_row_no')}).');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Sheet' : s.str('sheet_code')),
        actions: [if (s != null) IconButton(tooltip: 'Print', onPressed: _print, icon: const Icon(Icons.print_rounded))],
      ),
      bottomNavigationBar: s == null || s.str('status') == 'Closed'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  if (_isPhone) ...[
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _upload(camera: true),
                          icon: const Icon(Icons.photo_camera_rounded),
                          label: const Text('Photograph sheet'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: _isPhone
                          ? OutlinedButton.icon(
                              onPressed: _busy ? null : () => _upload(camera: false),
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Upload file'),
                            )
                          : FilledButton.icon(
                              onPressed: _busy ? null : () => _upload(camera: false),
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Upload file'),
                            ),
                    ),
                  ),
                ]),
              ),
            ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : s == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${s.str('equipment_code')}  ${s.str('type_name')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          Text('${s.str('site_code')} ${s.str('site_name')}  ·  ${Fmt.monthLabel(s.str('period_month'))}', style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            Pill('${s.str('last_row_no')} rows', color: AppColors.navy),
                            Pill('Photographed to row ${s.str('scanned_through_row', '0')}', color: s.flag('needs_scan') ? AppColors.standby : AppColors.working),
                            Pill(s.str('status'), color: s.str('status') == 'Closed' ? AppColors.neutral : AppColors.info),
                          ]),
                          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                        ]),
                      ),
                    ),
                    SectionCard(
                      title: 'Rows',
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Column(children: [
                        for (final r in s.list('rows'))
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(radius: 15, backgroundColor: AppColors.surface, child: Text(r.str('sheet_row_no'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy))),
                            title: Text('${Fmt.dayLabel(r.str('record_date'))}  ·  ${r.str('day_status')}'),
                            subtitle: Text(r.strOrNull('check_in_time') == null ? (r.str('remarks')) : '${Fmt.time(r.str('check_in_time'))} → ${Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))}'
                                '${r.strOrNull('operator_name') == null ? '' : '  ·  ${r.str('operator_name')}'}'),
                            trailing: PaperPill(r.str('paper_status')),
                          ),
                        for (final n in (s['cancelled_rows'] as List? ?? const []))
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(radius: 15, backgroundColor: AppColors.surface, child: Text('$n', style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                            title: const Text('Cancelled row', style: TextStyle(color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    SectionCard(
                      title: 'Uploaded versions',
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: s.list('scans').isEmpty
                          ? const EmptyView(text: 'No photo of this sheet yet.', icon: Icons.photo_camera_rounded)
                          : Column(children: [
                              for (final sc in s.list('scans'))
                                ListTile(
                                  leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.breakdown),
                                  title: Text('Version ${sc.str('version_no')}  ·  up to row ${sc.str('through_row_no')}'),
                                  subtitle: Text('${Fmt.date(sc.str('uploaded_at'))} ${Fmt.time(sc.str('uploaded_at'))}  ·  ${sc.str('uploaded_by')}  ·  ${sc.str('page_count')} page(s)'),
                                  onTap: () => viewStoredFile(context,
                                      title: '${s.str('sheet_code')} v${sc.str('version_no')}',
                                      fileName: '${s.str('sheet_code')}-v${sc.str('version_no')}.pdf',
                                      load: () => Api.I.getBytes('/equipment/timesheets/${widget.id}/scans/${sc.intv('scan_id')}/file')),
                                ),
                            ]),
                    ),
                  ]),
                ),
    );
  }
}
