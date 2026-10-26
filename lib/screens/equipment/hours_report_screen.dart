import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/file_save.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';

/// Hours since the start of the project: every machine (regular, OT, total, invoiced / not invoiced yet), grouped by
/// vendor with a total per vendor and a grand total. Optional vendor / site filter. PDF and Excel.
class HoursReportScreen extends StatefulWidget {
  const HoursReportScreen({super.key});
  @override
  State<HoursReportScreen> createState() => _HoursReportScreenState();
}

class _HoursReportScreenState extends State<HoursReportScreen> {
  PickOption? _vendor;
  PickOption? _site;
  Json? _data;
  Object? _error;
  bool _loading = false;

  Map<String, dynamic> get _query => {if (_vendor != null) 'vendor_id': _vendor!.value, if (_site != null) 'site_id': _site!.value};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await Api.I.getObj('/equipment/reports/hours', query: _query);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  void _pdf() => PdfViewScreen.open(context,
      title: 'Hours since the start',
      fileName: 'equipment-hours-since-start-${Fmt.today()}.pdf',
      load: () => Api.I.getBytes('/equipment/reports/hours', query: {..._query, 'format': 'pdf'}));

  Future<void> _excel() async {
    try {
      final bytes = await Api.I.getBytes('/equipment/reports/hours', query: {..._query, 'format': 'xlsx'});
      final msg = await FileSave.save(bytes, 'equipment-hours-since-start-${Fmt.today()}.xlsx');
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  static String _h(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '$whole.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final filters = Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      PickerField(
        label: 'Vendor (all)', width: 280, icon: Icons.business_rounded, valueLabel: _vendor?.label,
        load: () => Lookups.vendors(),
        onChanged: (p) { setState(() => _vendor = p); _load(); },
      ),
      PickerField(
        label: 'Site (all)', width: 260, icon: Icons.location_city_rounded, valueLabel: _site?.label,
        load: () => Lookups.sites(activeOnly: false),
        onChanged: (p) { setState(() => _site = p); _load(); },
      ),
      FilledButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF')),
      OutlinedButton.icon(onPressed: _excel, icon: const Icon(Icons.grid_on_rounded), label: const Text('Excel')),
      IconButton(onPressed: _loading ? null : _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded)),
    ]);

    Widget body;
    if (_loading && _data == null) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = ErrorView(error: _error!, onRetry: _load);
    } else {
      body = _table(_data ?? {});
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Hours since the start of the project',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          filters,
          const SizedBox(height: 8),
          const Text('Hours as billed: in invoices (drafts included) + approved days not in any invoice yet. Rows still waiting for approval are only counted.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 12),
      if (_loading && _data != null) const LinearProgressIndicator(),
      body,
    ]);
  }

  Widget _table(Json d) {
    final vendors = d.list('vendors');
    final errors = d.list('errors');
    if (vendors.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hours recorded for this selection.', style: TextStyle(color: AppColors.muted))));
    }
    const bold = TextStyle(fontWeight: FontWeight.w800);
    DataRow totalRow(String label, Json t, {Color? color}) => DataRow(color: WidgetStatePropertyAll(color ?? AppColors.navy.withValues(alpha: 0.06)), cells: [
          DataCell(Text(label, style: bold)), const DataCell(Text('')), const DataCell(Text('')),
          DataCell(Text('${t.intv('worked_days')}', style: bold)),
          DataCell(Text(_h(t.dbl('regular_hours')), style: bold)), DataCell(Text(_h(t.dbl('overtime_hours')), style: bold)),
          DataCell(Text(_h(t.dbl('total_hours')), style: bold)),
          DataCell(Text(_h(t.dbl('invoiced_hours')), style: bold)), DataCell(Text(_h(t.dbl('not_invoiced_hours')), style: bold)),
          DataCell(Text(t.intv('rows_waiting_approval') == 0 ? '-' : '${t.intv('rows_waiting_approval')}', style: bold)),
        ]);
    final rows = <DataRow>[];
    for (final g in vendors) {
      for (final m in g.list('machines')) {
        final first = m.strOrNull('first_day');
        rows.add(DataRow(cells: [
          DataCell(Text(g.str('vendor_name'), style: const TextStyle(color: AppColors.muted))),
          DataCell(Text('${m.str('equipment_code')}  ${m.strOrNull('machine_label') ?? m.str('type_name')}')),
          DataCell(Text(first == null ? '-' : '${Fmt.date(first)} - ${Fmt.date(m.strOrNull('last_day'))}')),
          DataCell(Text('${m.intv('worked_days')}')),
          DataCell(Text(_h(m.dbl('regular_hours')))), DataCell(Text(m.dbl('overtime_hours') == 0 ? '-' : _h(m.dbl('overtime_hours')))),
          DataCell(Text(_h(m.dbl('total_hours')), style: bold)),
          DataCell(Text(_h(m.dbl('invoiced_hours')))), DataCell(Text(m.dbl('not_invoiced_hours') == 0 ? '-' : _h(m.dbl('not_invoiced_hours')))),
          DataCell(Text(m.intv('rows_waiting_approval') == 0 ? '-' : '${m.intv('rows_waiting_approval')}')),
        ]));
      }
      rows.add(totalRow('Total ${g.str('vendor_name')}', g.obj('totals')));
    }
    if (vendors.length > 1) rows.add(totalRow('GRAND TOTAL', d.obj('totals'), color: AppColors.navy.withValues(alpha: 0.14)));
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Not-invoiced part could not be calculated for: ${errors.map((e) => '${e.str('from')} - ${e.str('to')}: ${e.str('message')}').join('; ')}',
                style: const TextStyle(color: AppColors.breakdown)),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(AppColors.navy),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('Vendor')), DataColumn(label: Text('Machine')), DataColumn(label: Text('First - last day')),
              DataColumn(label: Text('Worked days'), numeric: true), DataColumn(label: Text('Regular hours'), numeric: true),
              DataColumn(label: Text('OT hours'), numeric: true), DataColumn(label: Text('Total hours'), numeric: true),
              DataColumn(label: Text('Invoiced'), numeric: true), DataColumn(label: Text('Not invoiced yet'), numeric: true),
              DataColumn(label: Text('Awaiting approval'), numeric: true),
            ],
            rows: rows,
          ),
        ),
      ]),
    );
  }
}
