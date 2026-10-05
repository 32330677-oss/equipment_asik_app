import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/file_save.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';

/// Shown with the blockers but never stop the generation.
const _infoOnly = {'IN_OTHER_BATCH', 'SCAN_MISSING'};

const _blockerHelp = {
  'NOT_APPROVED': 'Approve or reject them in Attendance review.',
  'OPEN_SESSION': 'The supervisor must check the machine out.',
  'UNACK_ANOMALY': 'Acknowledge the anomaly in Attendance review.',
  'PAPER_NOT_MATCHED': 'Upload the signed sheet and reconcile it in Paper sheets.',
  'NO_RATE_CARD': 'Add a rate card for these dates on the machine page.',
  'FUEL_UNPRICED': 'Enter the price per litre in Fuel & adjustments.',
  'STANDBY_HOURS_NOT_SET': 'Monthly machine standby: open the row in Attendance review and set the standby hours to pay.',
  'IN_OTHER_BATCH': 'Already paid in another batch; they are skipped.',
  'FUEL_PRICE_MISSING': 'Add the official fuel price for these dates in Fuel & adjustments > Fuel prices.',
  'SCAN_MISSING': 'Information only: the accountant must upload these signed sheets (Paper sheets) before the Admin finalizes.',
};

Color _batchColor(String status, bool finalized) {
  switch (status) {
    case 'Paid':
      return AppColors.working;
    case 'Voided':
      return AppColors.breakdown;
    case 'Superseded':
      return AppColors.neutral;
    default:
      return finalized ? AppColors.info : AppColors.standby;
  }
}

String _batchLabel(String status, bool finalized) => status == 'Generated' ? (finalized ? 'Finalized' : 'Draft') : status;

/// Payroll batches list + entry point to the "new payroll" wizard.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final _s = Loadable<List<Json>>();
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/payroll/batches', query: {'status': _status});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _new() async {
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const NewPayrollScreen()));
    await _load();
    if (id != null && mounted) _openBatch(id);
  }

  Future<void> _openBatch(int id) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => BatchScreen(id: id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final drafts = rows.where((r) => r.str('status') == 'Generated' && !r.flag('is_finalized')).length;
    final toPay = rows.where((r) => r.str('status') == 'Generated' && r.flag('is_finalized')).toList();
    final unpaid = <String, double>{};
    for (final r in toPay) {
      unpaid[r.str('currency')] = (unpaid[r.str('currency')] ?? 0) + r.dbl('total_net');
    }
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Payroll', subtitle: 'Vendor statements per machine, from approved attendance', actions: [
          Dropdown<String?>(label: 'Status', value: _status, width: 160, items: const [
            DropdownMenuItem(value: null, child: Text('All')),
            DropdownMenuItem(value: 'Generated', child: Text('Draft / finalized')),
            DropdownMenuItem(value: 'Paid', child: Text('Paid')),
            DropdownMenuItem(value: 'Superseded', child: Text('Superseded')),
            DropdownMenuItem(value: 'Voided', child: Text('Voided')),
          ], onChanged: (v) { _status = v; _load(); }),
          FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('New payroll')),
        ]),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'Batches', value: '${rows.length}', icon: Icons.folder_copy_rounded),
          KpiTile(label: 'Drafts to finalize', value: '$drafts', color: AppColors.standby, icon: Icons.edit_note_rounded),
          KpiTile(label: 'Finalized, not paid', value: '${toPay.length}', color: AppColors.info, icon: Icons.schedule_rounded),
          for (final e in unpaid.entries)
            KpiTile(label: 'To pay (${e.key})', value: Fmt.money(e.value, e.key), color: AppColors.navy, icon: Icons.account_balance_wallet_rounded, width: 220),
        ]),
        const SizedBox(height: 14),
        if (_s.loading && _s.data == null)
          const LoadingView()
        else if (_s.error != null)
          ErrorView(error: _s.error!, onRetry: _load)
        else
          TableCard(
            empty: 'No payroll batch yet. Use "New payroll" to calculate one.',
            columns: const [
              DataColumn(label: Text('#')), DataColumn(label: Text('Period')), DataColumn(label: Text('Scope')),
              DataColumn(label: Text('Status')), DataColumn(label: Text('Ver.'), numeric: true), DataColumn(label: Text('Machines'), numeric: true),
              DataColumn(label: Text('Gross'), numeric: true), DataColumn(label: Text('Deductions'), numeric: true), DataColumn(label: Text('Net'), numeric: true),
              DataColumn(label: Text('Generated')),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  onSelectChanged: (_) => _openBatch(r.intv('eq_batch_id')),
                  cells: [
                    DataCell(Text('#${r.str('eq_batch_id')}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text('${Fmt.date(r.str('start_date'))} - ${Fmt.date(r.str('end_date'))}')),
                    DataCell(Text(_scopeText(r))),
                    DataCell(Pill(_batchLabel(r.str('status'), r.flag('is_finalized')), color: _batchColor(r.str('status'), r.flag('is_finalized')))),
                    DataCell(Text('v${r.str('version_number')}')),
                    DataCell(Text(r.str('total_equipment'))),
                    DataCell(Text(Fmt.money2(r.strOrNull('total_gross'), r.str('currency')))),
                    DataCell(Text(Fmt.money2(r.strOrNull('total_deductions'), r.str('currency')))),
                    DataCell(Text(Fmt.money2(r.strOrNull('total_net'), r.str('currency')), style: const TextStyle(fontWeight: FontWeight.w800))),
                    DataCell(Text('${Fmt.date(r.str('generated_at'))}  ${r.str('generated_by')}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

String _scopeText(Json b) {
  final parts = <String>[
    if (b.strOrNull('scope_vendor_name') != null) b.str('scope_vendor_name'),
    if (b.strOrNull('scope_equipment_code') != null) b.str('scope_equipment_code'),
    if (b.strOrNull('scope_site_code') != null) b.str('scope_site_code'),
  ];
  return parts.isEmpty ? 'All vendors' : parts.join(' · ');
}

// =================================================================== new payroll
class NewPayrollScreen extends StatefulWidget {
  const NewPayrollScreen({super.key});
  @override
  State<NewPayrollScreen> createState() => _NewPayrollScreenState();
}

class _NewPayrollScreenState extends State<NewPayrollScreen> {
  late String _from;
  late String _to;
  PickOption? _vendor;
  PickOption? _machine;
  PickOption? _site;
  String? _currency;

  bool _busy = false;
  List<Json>? _blockers;
  Json? _preview;
  Object? _previewError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - 1, 1);
    final last = DateTime(now.year, now.month, 0);
    _from = Fmt.dateOf(first);
    _to = Fmt.dateOf(last);
  }

  Map<String, dynamic> get _scope => {
        'start_date': _from,
        'end_date': _to,
        if (_vendor != null) 'vendor_id': _vendor!.value,
        if (_machine != null) 'equipment_id': _machine!.value,
        if (_site != null) 'site_id': _site!.value,
        if (_currency != null) 'currency': _currency,
      };

  void _changed(VoidCallback fn) => setState(() {
        fn();
        _blockers = null;
        _preview = null;
        _previewError = null;
      });

  Future<void> _check() async {
    setState(() { _busy = true; _previewError = null; });
    try {
      _blockers = asJsonList(await Api.I.get('/equipment/payroll/blockers', query: _scope));
      try {
        _preview = asJson(await Api.I.post('/equipment/payroll/preview', _scope));
      } catch (e) {
        _preview = null;
        _previewError = e;
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  bool get _hasBlocking => (_blockers ?? []).any((b) => !_infoOnly.contains(b.str('code')));

  Future<void> _generate({bool accept = false, String? currency}) async {
    if (_hasBlocking && !accept) {
      final ok = await confirmDialog(context, 'Generate with open problems?',
          'Rows with problems are left out of this batch. They can be paid later in another batch.\n\nContinue?',
          confirm: 'Generate anyway', danger: true);
      if (!ok) return;
      accept = true;
    }
    setState(() => _busy = true);
    try {
      final body = {..._scope, 'accept_blockers': accept, if (currency != null) 'currency': currency};
      final r = await Api.I.request('POST', '/equipment/payroll/generate', body: body);
      final b = asJson(r['data']);
      final warnings = asJsonList(r['warnings']);
      if (!mounted) return;
      showSnack(context, 'Batch #${b.str('eq_batch_id')} generated${warnings.isEmpty ? '' : ' with ${warnings.length} warning(s)'}.');
      Navigator.pop(context, b.intv('eq_batch_id'));
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'MIXED_CURRENCY') {
        final cur = (e.details?['currencies'] as List?)?.map((x) => '$x').toList() ?? <String>[];
        final p = await pickFromList(context, 'Several currencies: choose one batch currency', [for (final c in cur) PickOption(c, c)]);
        if (p != null) await _generate(accept: accept, currency: p.value as String);
        return;
      }
      if (e.code == 'BLOCKERS_PRESENT') {
        setState(() => _blockers = asJsonList(e.details?['blockers']));
        final ok = await confirmDialog(context, 'Generate with open problems?', e.message, confirm: 'Generate anyway', danger: true);
        if (ok) await _generate(accept: true, currency: currency);
        return;
      }
      showError(context, e);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final items = p == null ? <Json>[] : p.list('items');
    final totals = p == null ? <Json>[] : p.list('totals');
    final warnings = p == null ? <Json>[] : p.list('warnings');
    return Scaffold(
      appBar: AppBar(title: const Text('New payroll')),
      body: PageBody(maxWidth: 1300, children: [
        const SizedBox(height: 16),
        SectionCard(
          title: '1. Scope',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              DateField(label: 'From', value: _from, width: 170, onChanged: (v) => _changed(() => _from = v!)),
              DateField(label: 'To', value: _to, width: 170, onChanged: (v) => _changed(() => _to = v!)),
              PickerField(label: 'Vendor (all)', width: 240, icon: Icons.business_rounded, valueLabel: _vendor?.label, load: () => Lookups.vendors(),
                  onChanged: (v) => _changed(() { _vendor = v; _machine = null; })),
              PickerField(label: 'Machine (all)', width: 240, icon: Icons.precision_manufacturing_rounded, valueLabel: _machine?.label,
                  load: () => Lookups.machines(vendorId: _vendor?.value as int?), onChanged: (v) => _changed(() => _machine = v)),
              PickerField(label: 'Site (all)', width: 220, icon: Icons.location_city_rounded, valueLabel: _site?.label, load: () => Lookups.sites(activeOnly: false),
                  onChanged: (v) => _changed(() => _site = v)),
              Dropdown<String?>(label: 'Currency', value: _currency, width: 130, items: const [
                DropdownMenuItem(value: null, child: Text('Auto')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
                DropdownMenuItem(value: 'SYP', child: Text('SYP')),
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
              ], onChanged: (v) => _changed(() => _currency = v)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in _quickRanges())
                  ActionChip(label: Text(q.$1), onPressed: () => _changed(() { _from = q.$2; _to = q.$3; })),
              ]),
              FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.calculate_rounded),
                label: const Text('Calculate preview'),
              ),
            ]),
          ]),
        ),
        if (_blockers != null) ...[
          const SizedBox(height: 14),
          _BlockersCard(blockers: _blockers!),
        ],
        if (_previewError != null) ...[
          const SizedBox(height: 14),
          Card(
            color: const Color(0xFFFDECEA),
            child: ListTile(
              leading: const Icon(Icons.error_outline_rounded, color: AppColors.breakdown),
              title: const Text('The preview cannot be calculated', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_previewError is ApiException ? (_previewError as ApiException).message : '$_previewError'),
            ),
          ),
        ],
        if (p != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: '2. Preview',
            trailing: FilledButton.icon(
              onPressed: _busy || items.isEmpty ? null : () => _generate(),
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Generate batch'),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (items.isEmpty) const EmptyView(text: 'Nothing payable in this scope and period.', icon: Icons.money_off_rounded),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final t in totals) ...[
                  KpiTile(label: 'Machines / vendors', value: '${t.str('machines')} / ${t.str('vendors')}', icon: Icons.precision_manufacturing_rounded),
                  KpiTile(label: 'Work hours', value: t.str('work_hours'), icon: Icons.timer_rounded, color: AppColors.working),
                  KpiTile(label: 'Gross (${t.str('currency')})', value: Fmt.money2(t.strOrNull('gross'), t.str('currency')), width: 200),
                  KpiTile(label: 'Deductions', value: Fmt.money2(t.strOrNull('deductions'), t.str('currency')), color: AppColors.breakdown, width: 200),
                  KpiTile(label: 'Net to pay', value: Fmt.money2(t.strOrNull('net'), t.str('currency')), color: AppColors.navy, width: 220, icon: Icons.account_balance_wallet_rounded),
                ],
              ]),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.standby),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${w.str('code').replaceAll('_', ' ')}${w.strOrNull('message') == null ? '' : ': ${w.str('message')}'}', style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
              ],
              const SizedBox(height: 12),
              for (final it in items) _ItemTile(item: it, preview: true),
            ]),
          ),
        ],
      ]),
    );
  }

  List<(String, String, String)> _quickRanges() {
    final n = DateTime.now();
    return [
      ('Last month', Fmt.dateOf(DateTime(n.year, n.month - 1, 1)), Fmt.dateOf(DateTime(n.year, n.month, 0))),
      ('This month', Fmt.dateOf(DateTime(n.year, n.month, 1)), Fmt.dateOf(DateTime(n.year, n.month + 1, 0))),
      ('1st half', Fmt.dateOf(DateTime(n.year, n.month, 1)), Fmt.dateOf(DateTime(n.year, n.month, 15))),
    ];
  }
}

class _BlockersCard extends StatelessWidget {
  const _BlockersCard({required this.blockers});
  final List<Json> blockers;

  @override
  Widget build(BuildContext context) {
    if (blockers.isEmpty) {
      return Card(
        color: const Color(0xFFE8F5EE),
        child: const ListTile(
          leading: Icon(Icons.verified_rounded, color: AppColors.working),
          title: Text('No blockers', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Every row of this scope is approved, closed and reconciled.'),
        ),
      );
    }
    return SectionCard(
      title: 'Problems in this scope',
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(children: [
        for (final b in blockers)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(_infoOnly.contains(b.str('code')) ? Icons.info_outline_rounded : Icons.block_rounded,
                  color: _infoOnly.contains(b.str('code')) ? AppColors.info : AppColors.breakdown),
              title: Text('${b.str('message')}  (${b.str('count')})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(_blockerHelp[b.str('code')] ?? '', style: const TextStyle(fontSize: 12.5)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final i in b.list('items').take(60))
                    Pill([
                      if (i.strOrNull('sheet_code') != null) '${i.str('sheet_code')} rows to ${i.str('needed_row')}, uploaded to ${i.str('scanned_row')}',
                      i.str('equipment_code'),
                      if (i.strOrNull('site_code') != null) i.str('site_code'),
                      Fmt.date(i.strOrNull('record_date') ?? i.strOrNull('issue_date')),
                      if (i.strOrNull('status') != null && b.str('code') == 'NOT_APPROVED') i.str('status'),
                    ].join(' · '), color: AppColors.ink, outlined: true),
                  if (b.list('items').length > 60) Pill('+${b.list('items').length - 60} more'),
                ]),
              ],
            ),
          ),
      ]),
    );
  }
}

/// One machine line of a preview / batch with its calculation lines.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, this.preview = false, this.onRows, this.onPdf, this.onFuelPdf});
  final Json item;
  final bool preview;
  final VoidCallback? onRows;
  final VoidCallback? onPdf;
  final VoidCallback? onFuelPdf;

  @override
  Widget build(BuildContext context) {
    final cur = item.str('currency');
    final net = preview ? item.str('net') : item.str('net_amount');
    final gross = preview ? item.str('gross') : item.str('gross_amount');
    final ded = preview ? item.str('deductions') : item.str('deductions_amount');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      elevation: 0,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          title: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item.str('equipment_code')}  ${item.str('type_name')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${item.str('vendor_name')}  ·  ${item.str('site_code')}  ·  ${item.str('billing_mode')}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                if (item.strOrNull('invoice_no') != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, children: [
                      Pill(item.str('invoice_no'), color: AppColors.navy, icon: Icons.receipt_long_rounded),
                      if (item.strOrNull('fuel_invoice_no') != null) Pill(item.str('fuel_invoice_no'), color: AppColors.gold, icon: Icons.local_gas_station_rounded),
                    ]),
                  ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.money2(net, cur), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy)),
              Text('gross ${Fmt.money2(gross, cur)}${double.tryParse(ded) == 0 ? '' : '  ·  ded. ${Fmt.money2(ded, cur)}'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 14, runSpacing: 4, children: [
              kv('Days', '${item.str('worked_days')}/${item.str('days_recorded')}'),
              kv('Work h', item.str('work_hours')),
              if (item.dbl('overtime_hours') > 0) kv('OT h', item.str('overtime_hours')),
              if (item.dbl('standby_hours') > 0) kv('Standby h', item.str('standby_hours')),
              if (item.dbl('breakdown_hours') > 0) kv('Breakdown h', item.str('breakdown_hours')),
              if (item.dbl('topup_hours') > 0) kv('Min. top-up h', item.str('topup_hours')),
              if ((item.dblOrNull('fuel_difference') ?? 0) != 0) kv('Fuel price difference', Fmt.money(item.dbl('fuel_difference'), cur)),
            ]),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            for (final mo in (item.list('monthly_calc').isNotEmpty ? item.list('monthly_calc') : item.obj('rate_snapshot').list('monthly_calc')))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '${mo.str('month')}: ${mo.str('deployed_working_days')} of ${mo.str('working_days')} working days'
                  '${mo.intv('holiday_days') > 0 ? ' (${mo.str('holiday_days')} holidays)' : ''} x ${mo.str('hours_per_day')} h = ${mo.dbl('required_hours').toStringAsFixed(2)} h due  ·  '
                  'done ${mo.dbl('billable_hours').toStringAsFixed(2)} h  ·  hourly price ${mo.dbl('hourly_price').toStringAsFixed(3)}  ·  '
                  '${mo.dbl('overtime_hours') > 0 ? '+${mo.dbl('overtime_hours').toStringAsFixed(2)} h overtime' : mo.dbl('missing_hours') > 0 ? '-${mo.dbl('missing_hours').toStringAsFixed(2)} h missing' : 'hours complete'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            Table(
              columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.4)},
              children: [
                const TableRow(children: [
                  _Th('Line'), _Th('Quantity', right: true), _Th('Unit price', right: true), _Th('Amount', right: true),
                ]),
                for (final l in item.list('lines'))
                  TableRow(
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('${_lineName(l.str('line_type'))}${l.strOrNull('note') == null ? '' : '\n${l.str('note')}'}', style: const TextStyle(fontSize: 13)),
                      ),
                      _Td('${Fmt.num2(l.dblOrNull('quantity'))} ${l.str('unit')}'),
                      _Td(['FuelPriceDifference', 'Fuel', 'HoursShortfall', 'Overtime'].contains(l.str('line_type'))
                          ? (l.dblOrNull('unit_price') ?? 0).toStringAsFixed(3)
                          : Fmt.num2(l.dblOrNull('unit_price'))),
                      _Td(Fmt.money(l.dblOrNull('amount'), cur), color: l.dbl('amount') < 0 ? AppColors.breakdown : AppColors.ink, bold: true),
                    ],
                  ),
              ],
            ),
            if (item.list('site_allocation').isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Cost by site (monthly machine at several sites, split by hours)', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              for (final a in item.list('site_allocation'))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Expanded(child: Text(a.str('site_code', '#${a.str('site_id')}'), style: const TextStyle(fontSize: 13))),
                    SizedBox(width: 90, child: Text('${Fmt.num2(a.dblOrNull('hours'))} h', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                    SizedBox(width: 70, child: Text('${Fmt.num2(a.dblOrNull('share_pct'))}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                    SizedBox(width: 120, child: Text(Fmt.money(a.dblOrNull('amount'), cur), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  ]),
                ),
            ],
            if (onRows != null || onPdf != null || onFuelPdf != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, children: [
                  if (onRows != null) TextButton.icon(onPressed: onRows, icon: const Icon(Icons.list_alt_rounded, size: 18), label: const Text('Daily rows')),
                  if (onPdf != null) TextButton.icon(onPressed: onPdf, icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Machine invoice')),
                  if (onFuelPdf != null) TextButton.icon(onPressed: onFuelPdf, icon: const Icon(Icons.local_gas_station_rounded, size: 18), label: const Text('Fuel difference statement')),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

String _lineName(String t) {
  const names = {
    'MonthlyBase': 'Monthly base',
    'Work': 'Work',
    'Overtime': 'Overtime',
    'Standby': 'Standby (billable part)',
    'Breakdown': 'Breakdown (billable part)',
    'MinimumTopUp': 'Minimum hours top-up',
    'Operator': 'Operator',
    'Fuel': 'Fuel deduction',
    'Adjustment': 'Adjustment',
    'AbsenceDeduction': 'Absence deduction',
    'BreakdownDeduction': 'Breakdown deduction',
    'FuelPriceDifference': 'Fuel price difference',
    'HoursShortfall': 'Missing hours (below the monthly hours due)',
    'SecondShift': 'Second shift the same day',
  };
  return names[t] ?? t.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
}

class _Th extends StatelessWidget {
  const _Th(this.text, {this.right = false});
  final String text;
  final bool right;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Td extends StatelessWidget {
  const _Td(this.text, {this.color = AppColors.ink, this.bold = false});
  final String text;
  final Color color;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      );
}

// =================================================================== batch detail
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.id});
  final int id;
  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  Json? _b;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await Api.I.getObj('/equipment/payroll/batches/${widget.id}');
      if (mounted) setState(() { _b = b; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<dynamic> Function() fn, String ok, {bool reloadOther = false}) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (!mounted) return;
      showSnack(context, ok);
      if (reloadOther && r is Map && asJson(r).intOrNull('eq_batch_id') != null && asJson(r).intv('eq_batch_id') != widget.id) {
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => BatchScreen(id: asJson(r).intv('eq_batch_id'))));
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalize() async {
    final ok = await confirmDialog(context, 'Finalize batch #${widget.id}?',
        'The rows, fuel and adjustments of this batch are locked. Later changes need a correction and a new version.', confirm: 'Finalize');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Api.I.patch('/equipment/payroll/batches/${widget.id}/finalize');
      if (mounted) showSnack(context, 'Batch finalized. Invoice numbers issued.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'SCAN_MISSING') {
        final sheets = e.details == null ? <Json>[] : e.details!.list('sheets');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Signed sheets missing'),
            content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('The accountant must upload the signed monthly sheet (Paper sheets) up to these rows before the batch can be finalized:'),
                const SizedBox(height: 10),
                for (final sh in sheets)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_rounded, color: AppColors.standby),
                    title: Text('${sh.str('sheet_code')}  ·  ${sh.str('equipment_code')} at ${sh.str('site_code')}'),
                    subtitle: Text('Rows up to ${sh.str('needed_row')} needed, uploaded up to ${sh.str('scanned_row')}'),
                  ),
              ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid() async {
    final ok = await confirmDialog(context, 'Mark as paid?', 'Record that the vendors were paid for batch #${widget.id}.', confirm: 'Mark paid');
    if (ok) _act(() => Api.I.patch('/equipment/payroll/batches/${widget.id}/mark-paid', {'paid_at': Fmt.nowWall()}), 'Marked as paid.');
  }

  Future<void> _void() async {
    final reason = await promptText(context, 'Void batch #${widget.id}', label: 'Reason', confirm: 'Void');
    if (reason != null) _act(() => Api.I.patch('/equipment/payroll/batches/${widget.id}/void', {'reason': reason}), 'Batch voided. Its rows can be paid again.');
  }

  Future<void> _supersede() async {
    final reason = await promptText(context, 'New version of batch #${widget.id}', label: 'Why a new version?', confirm: 'Create version');
    if (reason == null) return;
    Future<dynamic> run(bool accept) => Api.I.post('/equipment/payroll/batches/${widget.id}/supersede', {'reason': reason, 'accept_blockers': accept});
    setState(() => _busy = true);
    try {
      final r = asJson(await run(false));
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => BatchScreen(id: r.intv('eq_batch_id'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'BLOCKERS_PRESENT') {
        final ok = await confirmDialog(context, 'Open problems', '${e.message}\n\nCreate the new version anyway (rows with problems are left out)?', confirm: 'Continue', danger: true);
        if (ok) await _act(() => run(true), 'New version created.', reloadOther: true);
      } else {
        showError(context, e);
      }
    }
  }

  Future<void> _versions() async {
    try {
      final rows = await Api.I.getList('/equipment/payroll/batches/${widget.id}/versions');
      if (!mounted) return;
      final cur = _b!.str('currency');
      final p = await pickFromList(context, 'Versions', [
        for (final v in rows)
          PickOption(v.intv('eq_batch_id'), 'v${v.str('version_number')}  ·  #${v.str('eq_batch_id')}  ·  ${_batchLabel(v.str('status'), v.flag('is_finalized'))}',
              '${Fmt.money2(v.strOrNull('total_net'), cur)}  ·  ${Fmt.date(v.str('generated_at'))}${v.strOrNull('supersede_reason') == null ? '' : '  ·  ${v.str('supersede_reason')}'}'),
      ]);
      if (p != null && p.value != widget.id && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => BatchScreen(id: p.value as int)));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _pdf(String view, {int? vendorId, int? equipmentId, String suffix = ''}) {
    PdfViewScreen.open(context,
        title: 'Batch #${widget.id} ${view == 'summary' ? 'summary' : suffix}',
        fileName: 'payroll-${widget.id}-$view${suffix.isEmpty ? '' : '-$suffix'}.pdf',
        load: () => Api.I.getBytes('/equipment/payroll/batches/${widget.id}/export.pdf', query: {'view': view, 'vendor_id': vendorId, 'equipment_id': equipmentId}));
  }

  Future<void> _vendorPdf() async {
    final items = _b!.list('items');
    final vendors = <int, String>{for (final i in items) i.intv('vendor_id'): i.str('vendor_name')};
    if (vendors.length == 1) {
      _pdf('vendor', vendorId: vendors.keys.first, suffix: vendors.values.first);
      return;
    }
    final p = await pickFromList(context, 'Vendor statement', [for (final e in vendors.entries) PickOption(e.key, e.value)]);
    if (p != null) _pdf('vendor', vendorId: p.value as int, suffix: p.label);
  }

  Future<void> _excel() async {
    try {
      final bytes = await Api.I.getBytes('/equipment/payroll/batches/${widget.id}/export.xlsx');
      final msg = await FileSave.save(bytes, 'equipment-payroll-${widget.id}-v${_b!.str('version_number')}.xlsx');
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rows(Json item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SnapshotSheet(batchId: widget.id, item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    return Scaffold(
      appBar: AppBar(
        title: Text('Payroll batch #${widget.id}'),
        actions: [
          if (b != null) ...[
            IconButton(tooltip: 'Versions', onPressed: _versions, icon: const Icon(Icons.history_rounded)),
            IconButton(tooltip: 'Excel', onPressed: _excel, icon: const Icon(Icons.grid_on_rounded)),
            PopupMenuButton<String>(
              tooltip: 'PDF',
              icon: const Icon(Icons.picture_as_pdf_rounded),
              onSelected: (v) => v == 'summary' ? _pdf('summary') : _vendorPdf(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'summary', child: Text('Summary PDF')),
                PopupMenuItem(value: 'vendor', child: Text('Vendor invoice PDF')),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : b == null
              ? const LoadingView()
              : _body(b),
    );
  }

  Widget _body(Json b) {
    final cur = b.str('currency');
    final status = b.str('status');
    final fin = b.flag('is_finalized');
    final canFinalize = status == 'Generated' && !fin && Auth.I.isAdmin; // the Admin finalizes and marks paid
    final canPay = status == 'Generated' && fin && Auth.I.isAdmin;
    final hasFuelDiff = b.list('items').any((i) => (i.dblOrNull('fuel_difference') ?? 0) != 0);
    final vendorInvoices = b.list('invoices').where((i) => i.str('kind') == 'Vendor' && !i.flag('cancelled')).toList();
    final cancelledInvoices = b.list('invoices').where((i) => i.flag('cancelled')).toList();
    final canVoid = status == 'Generated';
    // a paid batch is never recalculated: differences go through an official correction
    final canSupersede = fin && status == 'Generated';
    return PageBody(onRefresh: _load, maxWidth: 1200, children: [
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${Fmt.date(b.str('start_date'))}  to  ${Fmt.date(b.str('end_date'))}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${_scopeText(b)}  ·  version ${b.str('version_number')}  ·  $cur', style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
              Pill(_batchLabel(status, fin), color: _batchColor(status, fin)),
            ]),
            if (b.flag('stale'))
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.standby.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.standby),
                  SizedBox(width: 10),
                  Expanded(child: Text('Something that changes the amounts changed after this batch was generated. Void it and generate again before finalizing.')),
                ]),
              ),
            if (b.flag('stale'))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(b.list('stale_reasons').take(6).map(_staleReason).join('\n'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            if (cancelledInvoices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Cancelled numbers (kept, never reused): ${cancelledInvoices.map((i) => i.str('invoice_no')).join(', ')}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            if (b.strOrNull('void_reason') != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Void reason: ${b.str('void_reason')}', style: const TextStyle(color: AppColors.breakdown))),
            if (b.strOrNull('supersede_reason') != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Version reason: ${b.str('supersede_reason')}', style: const TextStyle(color: AppColors.muted))),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, children: [
              KpiTile(label: 'Machines', value: b.str('total_equipment'), icon: Icons.precision_manufacturing_rounded),
              KpiTile(label: 'Gross', value: Fmt.money2(b.strOrNull('total_gross'), cur), width: 200),
              KpiTile(label: 'Deductions', value: Fmt.money2(b.strOrNull('total_deductions'), cur), color: AppColors.breakdown, width: 200),
              KpiTile(label: 'Net to pay', value: Fmt.money2(b.strOrNull('total_net'), cur), color: AppColors.navy, width: 220, icon: Icons.account_balance_wallet_rounded),
            ]),
            const SizedBox(height: 14),
            _Timeline(b: b),
            const SizedBox(height: 14),
            if (vendorInvoices.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Vendor invoices:', style: TextStyle(color: AppColors.muted)),
                for (final v in vendorInvoices)
                  ActionChip(
                    avatar: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: Text('${v.str('invoice_no')}  ·  ${Fmt.money2(v.strOrNull('amount'), cur)}'),
                    onPressed: () => _pdf('vendor', vendorId: v.intv('vendor_id'), suffix: v.str('invoice_no')),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            if (status == 'Generated' && !fin && !Auth.I.isAdmin)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Upload the signed monthly sheets in Paper sheets; the Admin then finalizes this batch.', style: TextStyle(color: AppColors.muted)),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (hasFuelDiff) OutlinedButton.icon(onPressed: () => _pdf('fueldiff', suffix: 'fuel-difference'), icon: const Icon(Icons.local_gas_station_rounded), label: const Text('Fuel difference statements')),
              if (canFinalize) FilledButton.icon(onPressed: _busy || b.flag('stale') ? null : _finalize, icon: const Icon(Icons.lock_rounded), label: const Text('Finalize')),
              if (canPay) FilledButton.icon(onPressed: _busy ? null : _markPaid, icon: const Icon(Icons.paid_rounded), label: const Text('Mark paid'), style: FilledButton.styleFrom(backgroundColor: AppColors.working)),
              if (canSupersede) OutlinedButton.icon(onPressed: _busy ? null : _supersede, icon: const Icon(Icons.difference_rounded), label: const Text('New version')),
              if (canVoid) OutlinedButton.icon(onPressed: _busy ? null : _void, icon: const Icon(Icons.block_rounded, color: AppColors.breakdown), label: const Text('Void', style: TextStyle(color: AppColors.breakdown))),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'Machines (${b.list('items').length})',
        child: Column(children: [
          for (final it in b.list('items'))
            _ItemTile(
              item: {...it, 'currency': cur},
              onRows: () => _rows(it),
              onPdf: () => _pdf('machine', equipmentId: it.intv('equipment_id'), suffix: it.str('equipment_code')),
              onFuelPdf: (it.dblOrNull('fuel_difference') ?? 0) == 0 ? null : () => _pdf('fueldiff', equipmentId: it.intv('equipment_id'), suffix: 'fuel-${it.str('equipment_code')}'),
            ),
        ]),
      ),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.b});
  final Json b;

  @override
  Widget build(BuildContext context) {
    Widget step(String label, String? at, bool done, {String? by, Color color = AppColors.working}) => Expanded(
          child: Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? color : AppColors.neutral, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: done ? AppColors.ink : AppColors.muted)),
                Text(at == null ? '-' : '${Fmt.date(at)} ${Fmt.time(at)}${by == null ? '' : '  ·  $by'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
          ]),
        );
    return Row(children: [
      step('Generated', b.strOrNull('generated_at'), true, by: b.strOrNull('generated_by')),
      step('Finalized', b.strOrNull('finalized_at'), b.flag('is_finalized'), color: AppColors.info),
      if (b.str('status') == 'Voided')
        step('Voided', b.strOrNull('voided_at'), true, color: AppColors.breakdown)
      else
        step('Paid', b.strOrNull('paid_at'), b.str('status') == 'Paid' || b.strOrNull('paid_at') != null),
    ]);
  }
}

class _SnapshotSheet extends StatefulWidget {
  const _SnapshotSheet({required this.batchId, required this.item});
  final int batchId;
  final Json item;
  @override
  State<_SnapshotSheet> createState() => _SnapshotSheetState();
}

class _SnapshotSheetState extends State<_SnapshotSheet> {
  List<Json>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.getList('/equipment/payroll/batches/${widget.batchId}/rows', query: {'equipment_id': widget.item.intv('equipment_id')});
      final site = widget.item.intv('site_id');
      if (mounted) setState(() => _rows = r.where((x) => x.intv('site_id') == site).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${widget.item.str('equipment_code')} at ${widget.item.str('site_code')}: paid rows', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: _error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : _rows == null
                    ? const LoadingView()
                    : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
                        TableCard(
                          empty: 'No attendance row (monthly base only).',
                          columns: const [
                            DataColumn(label: Text('Date')), DataColumn(label: Text('Day')), DataColumn(label: Text('In - Out')),
                            DataColumn(label: Text('Work h'), numeric: true), DataColumn(label: Text('OT h'), numeric: true),
                            DataColumn(label: Text('Standby h'), numeric: true), DataColumn(label: Text('Breakdown h'), numeric: true),
                            DataColumn(label: Text('Operator')), DataColumn(label: Text('Sheet')),
                          ],
                          rows: [
                            for (final r in _rows!)
                              DataRow(cells: [
                                DataCell(Text(Fmt.dayLabel(r.str('record_date')))),
                                DataCell(StatePill(r.str('day_status'))),
                                DataCell(Text(r.strOrNull('check_in_time') == null ? '-' : '${Fmt.time(r.str('check_in_time'))} - ${Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))}')),
                                DataCell(Text(Fmt.hoursFromMinutes(r.intv('work_minutes')))),
                                DataCell(Text(r.intv('overtime_minutes') == 0 ? '' : Fmt.hoursFromMinutes(r.intv('overtime_minutes')))),
                                DataCell(Text(r.intv('standby_minutes') == 0 ? '' : Fmt.hoursFromMinutes(r.intv('standby_minutes')))),
                                DataCell(Text(r.intv('breakdown_minutes') == 0 ? '' : Fmt.hoursFromMinutes(r.intv('breakdown_minutes')))),
                                DataCell(Text(r.str('operator_name', '-'))),
                                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [Text('#${r.str('sheet_row_no')} '), PaperPill(r.str('paper_status'))])),
                              ]),
                          ],
                        ),
                      ]),
          ),
        ]),
      ),
    );
  }
}

/// One line per reason the batch would come out differently if generated now.
String _staleReason(Json r) {
  switch (r.str('code')) {
    case 'AMOUNT_CHANGED':
      return 'Amount changed: ${r.str('was')} -> ${r.str('now')}';
    case 'ITEM_ADDED':
      return 'A machine/site would be added (${r.str('net')})';
    case 'ITEM_REMOVED':
      return 'A machine/site would be removed (${r.str('was')})';
    case 'ROWS_ADDED':
      return '${r.str('count')} approved row(s) not in this batch yet';
    case 'ROWS_DROPPED':
      return '${r.str('count')} row(s) no longer payable';
    case 'ROW_CHANGED':
      return 'Row #${r.str('eq_attendance_id')}: ${r.str('reason')}';
    case 'SETTING_CHANGED':
      return 'Setting ${r.str('setting')}: ${r.str('was')} -> ${r.str('now')}';
    default:
      return r.str('message', r.str('code'));
  }
}
