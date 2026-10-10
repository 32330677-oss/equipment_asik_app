import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';

/// Daily Equipment Report for an external party (sub-contractor / client).
/// Lists only the machines that checked in on the day: no vendor, no hours, no money.
/// English PDF = main copy, Arabic PDF = separate copy. "To" / "Issued by" and the info labels are remembered.
class ClientReportScreen extends StatefulWidget {
  const ClientReportScreen({super.key, this.siteId, this.siteLabel, this.shift, this.standalone = false});

  /// Fixed site (supervisor opening it from his day board); null = choose sites.
  final int? siteId;
  final String? siteLabel;

  /// Initial shift ('Day' / 'Night'); null = both.
  final String? shift;

  /// Pushed as its own page (with an app bar) instead of inside the shell.
  final bool standalone;

  static Future<void> open(BuildContext context, {int? siteId, String? siteLabel, String? shift}) {
    return Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => ClientReportScreen(siteId: siteId, siteLabel: siteLabel, shift: shift, standalone: true)));
  }

  @override
  State<ClientReportScreen> createState() => _ClientReportScreenState();
}

class _InfoLine {
  _InfoLine([String label = '', String value = ''])
      : label = TextEditingController(text: label),
        value = TextEditingController(text: value);
  final TextEditingController label;
  final TextEditingController value;
  void dispose() { label.dispose(); value.dispose(); }
}

class _ClientReportScreenState extends State<ClientReportScreen> {
  static const _kTo = 'client_report.to';
  static const _kBy = 'client_report.issued_by';
  static const _kTitle = 'client_report.issued_title';
  static const _kLabels = 'client_report.info_labels';
  static const _maxLines = 20;

  String _date = Fmt.today();
  late String _shift = widget.shift ?? 'All';
  List<PickOption>? _sites;
  Object? _sitesError;
  final Set<int> _selected = {}; // empty = every active site
  final _to = TextEditingController();
  final _by = TextEditingController();
  final _title = TextEditingController();
  final List<_InfoLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _restore();
    if (widget.siteId == null) _loadSites();
  }

  @override
  void dispose() {
    _to.dispose(); _by.dispose(); _title.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      _to.text = p.getString(_kTo) ?? '';
      _by.text = p.getString(_kBy) ?? '';
      _title.text = p.getString(_kTitle) ?? '';
      // the labels used last time come back empty-valued, ready to fill
      for (final l in p.getStringList(_kLabels) ?? const <String>[]) { _lines.add(_InfoLine(l)); }
    } catch (_) {/* nothing remembered: start empty */}
    if (mounted) setState(() {});
  }

  Future<void> _remember() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kTo, _to.text.trim());
      await p.setString(_kBy, _by.text.trim());
      await p.setString(_kTitle, _title.text.trim());
      await p.setStringList(_kLabels, [for (final l in _lines) if (l.label.text.trim().isNotEmpty) l.label.text.trim()]);
    } catch (_) {/* not critical */}
  }

  Future<void> _loadSites() async {
    try {
      _sites = await Lookups.sites();
      _sitesError = null;
    } catch (e) {
      _sitesError = e;
    }
    if (mounted) setState(() {});
  }

  String? _check() {
    for (final l in _lines) {
      final a = l.label.text.trim(); final b = l.value.text.trim();
      if (a.length > 80) return 'An information title is longer than 80 characters.';
      if (b.length > 500) return 'An information value is longer than 500 characters.';
      if (a.isEmpty && b.isNotEmpty) return 'Give a title to every information line (e.g. Weather).';
    }
    return null;
  }

  Future<void> _open(String lang) async {
    final err = _check();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await _remember();
    final notes = [
      for (final l in _lines)
        if (l.label.text.trim().isNotEmpty || l.value.text.trim().isNotEmpty) {'label': l.label.text.trim(), 'value': l.value.text.trim()},
    ];
    final ids = widget.siteId != null ? [widget.siteId!] : (_selected.toList()..sort());
    final query = <String, dynamic>{
      'date': _date,
      'shift': _shift,
      'lang': lang,
      'site_ids': ids.isEmpty ? null : ids.join(','),
      'to': _to.text.trim(),
      'issued_by': _by.text.trim(),
      'issued_title': _title.text.trim(),
      'notes': notes.isEmpty ? null : jsonEncode(notes),
    };
    if (!mounted) return;
    await PdfViewScreen.open(context,
        title: lang == 'ar' ? 'Daily equipment report (Arabic)' : 'Daily equipment report',
        fileName: 'daily-equipment-report-$_date-${lang.toUpperCase()}.pdf',
        load: () => Api.I.getBytes('/equipment/reports/client-daily.pdf', query: query));
  }

  Widget _sitesCard() {
    if (widget.siteId != null) {
      return SectionCard(title: 'Site', child: Text(widget.siteLabel ?? 'Site #${widget.siteId}', style: const TextStyle(fontWeight: FontWeight.w700)));
    }
    final sites = _sites;
    return SectionCard(
      title: 'Sites',
      trailing: Text(_selected.isEmpty ? 'All active sites' : '${_selected.length} selected', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      child: sites == null
          ? (_sitesError != null ? ErrorView(error: _sitesError!, onRetry: _loadSites) : const LinearProgressIndicator())
          : Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('All sites'),
                selected: _selected.isEmpty,
                onSelected: (_) => setState(_selected.clear),
              ),
              for (final s in sites)
                FilterChip(
                  label: Text(s.label),
                  tooltip: s.subtitle,
                  selected: _selected.contains(s.value),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selected.add(s.value! as int);
                    } else {
                      _selected.remove(s.value);
                    }
                  }),
                ),
            ]),
    );
  }

  Widget _infoCard() {
    return SectionCard(
      title: 'Additional information',
      trailing: TextButton.icon(
        onPressed: _lines.length >= _maxLines ? null : () => setState(() => _lines.add(_InfoLine())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add line'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_lines.isEmpty)
          const Text('Optional: add lines such as Weather, Safety, Site access, Remarks. Each line is printed as a title and its text.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
        for (final line in _lines)
          Padding(
            key: ObjectKey(line),
            padding: const EdgeInsets.only(bottom: 10),
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 560;
              final remove = IconButton(
                tooltip: 'Remove',
                onPressed: () {
                  setState(() => _lines.remove(line));
                  WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());
                },
                icon: const Icon(Icons.delete_outline_rounded),
              );
              final label = TextField(controller: line.label, maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Weather', counterText: ''));
              final value = TextField(controller: line.value, maxLength: 500, minLines: 1, maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Text', hintText: 'e.g. Clear, 31 C', counterText: ''));
              return wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 200, child: label), const SizedBox(width: 10), Expanded(child: value), remove,
                    ])
                  : Column(children: [Row(children: [Expanded(child: label), remove]), const SizedBox(height: 6), value]);
            }),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = PageBody(maxWidth: 900, children: [
      if (!widget.standalone)
        const PageHeader(title: 'Daily report (client)', subtitle: 'Machines that worked on the day - for the sub-contractor or the client'),
      if (widget.standalone) const SizedBox(height: 16),
      SectionCard(
        title: 'Day and shift',
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DateField(label: 'Date', value: _date, width: 200, last: Fmt.today(), onChanged: (v) { if (v != null) setState(() => _date = v); }),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'All', label: Text('Both shifts')),
              ButtonSegment(value: 'Day', label: Text('Day'), icon: Icon(Icons.wb_sunny_rounded)),
              ButtonSegment(value: 'Night', label: Text('Night'), icon: Icon(Icons.nightlight_round)),
            ],
            selected: {_shift},
            onSelectionChanged: (s) => setState(() => _shift = s.first),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _sitesCard(),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Addressed to / issued by',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _to, maxLength: 150, decoration: const InputDecoration(labelText: 'To', hintText: 'Company or person receiving the report', counterText: '')),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 10, children: [
            SizedBox(width: 300, child: TextField(controller: _by, maxLength: 120, decoration: const InputDecoration(labelText: 'Issued by (name)', counterText: ''))),
            SizedBox(width: 300, child: TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Site Manager', counterText: ''))),
          ]),
          const SizedBox(height: 4),
          const Text('Remembered on this device for the next report.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 12),
      _infoCard(),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 10, alignment: WrapAlignment.end, children: [
        OutlinedButton.icon(onPressed: () => _open('ar'), icon: const Icon(Icons.translate_rounded), label: const Text('Arabic PDF')),
        FilledButton.icon(onPressed: () => _open('en'), icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('English PDF')),
      ]),
    ]);
    if (!widget.standalone) return body;
    return Scaffold(appBar: AppBar(title: const Text('Daily report (client)')), body: body);
  }
}
