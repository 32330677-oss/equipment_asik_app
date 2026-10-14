import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/file_versions.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Fuel issued to the machines, official fuel prices and manual adjustments.
class FuelAdjustmentsScreen extends StatelessWidget {
  const FuelAdjustmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Material(
          color: Colors.white,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.navy,
            indicatorColor: AppColors.gold,
            unselectedLabelColor: AppColors.muted,
            tabs: const [
              Tab(icon: Icon(Icons.local_gas_station_rounded, size: 20), text: 'Fuel issues'),
              Tab(icon: Icon(Icons.trending_up_rounded, size: 20), text: 'Fuel prices'),
              Tab(icon: Icon(Icons.tune_rounded, size: 20), text: 'Adjustments'),
            ],
          ),
        ),
        const Divider(height: 1),
        const Expanded(child: TabBarView(children: [_FuelTab(), _FuelPricesTab(), _AdjustmentsTab()])),
      ]),
    );
  }
}

// ======================================================================= fuel
class _FuelTab extends StatefulWidget {
  const _FuelTab();
  @override
  State<_FuelTab> createState() => _FuelTabState();
}

class _FuelTabState extends State<_FuelTab> with AutomaticKeepAliveClientMixin {
  final _s = Loadable<List<Json>>();
  bool _unpricedOnly = true;
  String _from = Fmt.dateOf(Fmt.now().subtract(const Duration(days: 60)));
  String _to = Fmt.today();
  PickOption? _vendor;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/fuel-issues', query: {
        if (_unpricedOnly) 'unpriced': 'true' else ...{'from': _from, 'to': _to},
        'vendor_id': _vendor?.value,
      });
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _price(Json r) async {
    final priced = r.strOrNull('price_per_liter') != null;
    final v = await promptText(context, 'Price per litre - ${r.machineName} ${Fmt.date(r.str('issue_date'))}',
        label: 'Price per litre (${r.str('liters')} L)', initial: r.strOrNull('price_per_liter'), maxLines: 1, confirm: 'Save price');
    if (v == null) return;
    final n = num.tryParse(v);
    if (n == null || n < 0) {
      if (mounted) showSnack(context, 'Enter a valid price.', error: true);
      return;
    }
    String? reason;
    if (priced) {
      if (!mounted) return;
      reason = await promptText(context, 'Why does the price change?', label: 'Reason (kept in the history)', minLength: 5);
      if (reason == null) return;
    }
    await _save(r, {'price_per_liter': n, if (reason != null) 'reason': reason});
  }

  /// Litres written wrong on the issue (before its period is closed): reason required, kept in the history.
  Future<void> _liters(Json r) async {
    final v = await promptText(context, 'Litres - ${r.machineName} ${Fmt.date(r.str('issue_date'))}',
        label: 'Litres (from the receipt)', initial: r.str('liters'), maxLines: 1, confirm: 'Next');
    if (v == null) return;
    final n = num.tryParse(v.replaceAll(',', '.'));
    if (n == null || n <= 0) {
      if (mounted) showSnack(context, 'Enter the number of litres.', error: true);
      return;
    }
    if (!mounted) return;
    final reason = await promptText(context, 'Why do the litres change?', label: 'Reason (kept in the history)', minLength: 5);
    if (reason == null) return;
    await _save(r, {'liters': n, 'reason': reason});
  }

  Future<void> _save(Json r, Map<String, dynamic> body) async {
    try {
      await Api.I.patch('/equipment/fuel-issues/${r.intv('fuel_issue_id')}', body);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'INVOICE_LOCKED' || e.code == 'PAYROLL_LOCKED') {
        showSnack(context, '${e.message} Or settle the difference with a debit / credit note (Invoices).', error: true);
      } else {
        showError(context, e);
      }
    }
  }

  Future<void> _priceAll(List<Json> rows) async {
    final v = await promptText(context, 'One price for ${rows.length} unpriced issue(s)', label: 'Price per litre', maxLines: 1, confirm: 'Apply to all');
    if (v == null) return;
    final n = num.tryParse(v);
    if (n == null || n < 0) return;
    var ok = 0;
    final errors = <String>[];
    for (final r in rows) {
      try {
        await Api.I.patch('/equipment/fuel-issues/${r.intv('fuel_issue_id')}', {'price_per_liter': n});
        ok++;
      } catch (e) {
        errors.add('${r.machineName}: ${e is ApiException ? e.message : e}');
      }
    }
    if (mounted) showSnack(context, '$ok priced${errors.isEmpty ? '.' : ', ${errors.length} failed: ${errors.first}'}', error: errors.isNotEmpty);
    _load();
  }

  Future<void> _cancel(Json r) async {
    final reason = await promptText(context, 'Cancel fuel issue', label: 'Reason', confirm: 'Cancel issue', minLength: 5,
        help: 'The issue is kept (marked cancelled). A draft invoice batch that uses it becomes out of date.');
    if (reason == null) return;
    try {
      await Api.I.patch('/equipment/fuel-issues/${r.intv('fuel_issue_id')}/cancel', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _add() async {
    PickOption? machine;
    PickOption? site;
    var date = Fmt.today();
    final liters = TextEditingController();
    final price = TextEditingController();
    final receipt = TextEditingController();
    final created = await showFormDialog<Json>(
      context,
      title: 'Record fuel issue',
      onSave: () async {
        if (machine == null || site == null) {
          throw ApiException(null, 'VALIDATION', 'Choose the machine and the site.');
        }
        return asJson(await Api.I.post('/equipment/fuel-issues', {
          'equipment_id': machine!.value, 'site_id': site!.value, 'issue_date': date,
          'liters': numOrNull(liters), 'price_per_liter': numOrNull(price), 'receipt_number': textOrNull(receipt),
        }));
      },
      body: (ctx, set) => FormGrid(children: [
        PickerField(label: 'Machine *', valueLabel: machine?.label, icon: Icons.precision_manufacturing_rounded,
            load: () => Lookups.machines(status: 'Active'), onChanged: (v) => set(() => machine = v)),
        PickerField(label: 'Site *', valueLabel: site?.label, icon: Icons.location_city_rounded, load: () => Lookups.sites(), onChanged: (v) => set(() => site = v)),
        DateField(label: 'Date', value: date, last: Fmt.today(), onChanged: (v) => set(() => date = v ?? date)),
        textField(liters, 'Litres', number: true, required: true, suffix: 'L'),
        textField(price, 'Price per litre', number: true, hint: 'can be added later'),
        textField(receipt, 'Receipt number'),
      ]),
    );
    if (created == null || !mounted) return;
    showSnack(context, 'Fuel issue recorded.');
    final attach = await confirmDialog(context, 'Attach the receipt?', 'Upload a photo or PDF of the fuel receipt now.', confirm: 'Upload');
    if (attach) await _upload(created);
    _load();
  }

  Future<void> _upload(Json r) async {
    final ok = await uploadFileVersion(context,
        basePath: '/equipment/fuel-issues/${r.intv('fuel_issue_id')}/receipt', hasFile: r.flag('has_receipt'), label: 'Receipt',
        extensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _s.data ?? <Json>[];
    final active = rows.where((r) => !r.flag('is_cancelled')).toList();
    final unpriced = active.where((r) => r.strOrNull('price_per_liter') == null).toList();
    final liters = active.fold<double>(0, (s, r) => s + r.dbl('liters'));
    final value = active.fold<double>(0, (s, r) => s + r.dbl('liters') * r.dbl('price_per_liter'));
    return PageBody(onRefresh: _load, children: [
      PageHeader(title: 'Fuel issues', subtitle: 'Fuel issued to the machines, recorded here from the receipts (it is not recorded at check-out).', actions: [
        FilterChip(
          label: const Text('Unpriced only'),
          selected: _unpricedOnly,
          onSelected: (v) { _unpricedOnly = v; _load(); },
        ),
        if (!_unpricedOnly)
          OutlinedButton.icon(
            onPressed: () async {
              final f = await pickDate(context, initial: _from);
              if (f == null || !context.mounted) return;
              final t = await pickDate(context, initial: _to);
              if (t == null) return;
              _from = f; _to = t; _load();
            },
            icon: const Icon(Icons.date_range_rounded),
            label: Text('${Fmt.date(_from)} - ${Fmt.date(_to)}'),
          ),
        PickerField(label: 'Vendor', width: 200, valueLabel: _vendor?.label, load: () => Lookups.vendors(), onChanged: (v) { _vendor = v; _load(); }),
        FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Record fuel')),
      ]),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(label: 'Issues', value: '${active.length}', icon: Icons.local_gas_station_rounded),
        KpiTile(label: 'Litres', value: Fmt.num2(liters), icon: Icons.water_drop_rounded, color: AppColors.info),
        KpiTile(label: 'Without price', value: '${unpriced.length}', icon: Icons.price_change_rounded, color: unpriced.isEmpty ? AppColors.working : AppColors.breakdown),
        if (!_unpricedOnly) KpiTile(label: 'Priced value', value: Fmt.num2(value), icon: Icons.payments_rounded, width: 200),
      ]),
      if (unpriced.length > 1) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: () => _priceAll(unpriced), icon: const Icon(Icons.done_all_rounded), label: Text('Set one price for all ${unpriced.length} unpriced')),
        ),
      ],
      const SizedBox(height: 12),
      if (_s.loading && _s.data == null)
        const LoadingView()
      else if (_s.error != null)
        ErrorView(error: _s.error!, onRetry: _load)
      else
        TableCard(
          empty: _unpricedOnly ? 'Every fuel issue has a price.' : 'No fuel issue in this period.',
          columns: const [
            DataColumn(label: Text('Date')), DataColumn(label: Text('Machine')), DataColumn(label: Text('Site')), DataColumn(label: Text('Vendor')),
            DataColumn(label: Text('Litres'), numeric: true), DataColumn(label: Text('Price / L'), numeric: true), DataColumn(label: Text('Value'), numeric: true),
            DataColumn(label: Text('Receipt')), DataColumn(label: Text('By')), DataColumn(label: Text('')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                color: r.flag('is_cancelled') ? WidgetStatePropertyAll(Colors.grey.shade100) : null,
                cells: [
                  DataCell(Text(Fmt.dayLabel(r.str('issue_date')))),
                  DataCell(Text(r.machineName, style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text(r.str('site_code'))),
                  DataCell(Text(r.str('vendor_name'))),
                  DataCell(Text(Fmt.num2(r.dblOrNull('liters')))),
                  DataCell(
                    r.flag('is_cancelled')
                        ? const Pill('Cancelled', color: AppColors.neutral)
                        : r.strOrNull('price_per_liter') == null
                            ? ActionChip(
                                avatar: const Icon(Icons.add_rounded, size: 16, color: AppColors.breakdown),
                                label: const Text('Add price', style: TextStyle(color: AppColors.breakdown, fontWeight: FontWeight.w700)),
                                onPressed: () => _price(r),
                              )
                            : Text(r.str('price_per_liter')),
                    onTap: r.flag('is_cancelled') ? null : () => _price(r),
                  ),
                  DataCell(Text(r.strOrNull('price_per_liter') == null ? '' : Fmt.num2(r.dbl('liters') * r.dbl('price_per_liter')))),
                  DataCell(r.flag('has_receipt')
                      ? IconButton(
                          tooltip: 'Receipt (all versions)',
                          icon: const Icon(Icons.receipt_long_rounded, color: AppColors.navy),
                          onPressed: () async {
                            final changed = await showFileVersions(context,
                                title: 'Receipt ${r.str('receipt_number')}',
                                basePath: '/equipment/fuel-issues/${r.intv('fuel_issue_id')}/receipt',
                                listPath: '/equipment/fuel-issues/${r.intv('fuel_issue_id')}/receipts',
                                fileName: 'fuel-receipt-${r.str('fuel_issue_id')}',
                                canUpload: !r.flag('is_cancelled'),
                                extensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
                            if (changed) _load();
                          },
                        )
                      : TextButton(onPressed: r.flag('is_cancelled') ? null : () => _upload(r), child: Text(r.strOrNull('receipt_number') == null ? 'Upload' : '${r.str('receipt_number')} ↑'))),
                  DataCell(Text(r.str('issued_by'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                  DataCell(r.flag('is_cancelled')
                      ? Tooltip(message: r.str('cancel_reason'), child: const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.muted))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Correct the litres', icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _liters(r)),
                          IconButton(tooltip: 'Cancel', icon: const Icon(Icons.block_rounded, size: 18, color: AppColors.breakdown), onPressed: () => _cancel(r)),
                        ])),
                ],
              ),
          ],
        ),
    ]);
  }
}

// ================================================================= adjustments
const _adjTypes = ['Mobilization', 'Demobilization', 'Bonus', 'Penalty', 'Damage', 'FuelCorrection', 'Other'];
const _deductionTypes = {'Penalty', 'Damage', 'FuelCorrection'};

class _AdjustmentsTab extends StatefulWidget {
  const _AdjustmentsTab();
  @override
  State<_AdjustmentsTab> createState() => _AdjustmentsTabState();
}

class _AdjustmentsTabState extends State<_AdjustmentsTab> with AutomaticKeepAliveClientMixin {
  final _s = Loadable<List<Json>>();
  String? _status = 'Active';
  PickOption? _vendor;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/adjustments', query: {'status': _status, 'vendor_id': _vendor?.value});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _cancel(Json r) async {
    final reason = await promptText(context, 'Cancel adjustment', label: 'Reason', confirm: 'Cancel adjustment', minLength: 5,
        help: r.intOrNull('in_batch_id') == null ? null : 'Invoice #${r.str('in_batch_id')} uses it: a draft then asks to be recalculated; an issued invoice follows with the same number.');
    if (reason == null) return;
    try {
      await Api.I.patch('/equipment/adjustments/${r.intv('adjustment_id')}/cancel', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _s.data ?? <Json>[];
    final byCur = <String, double>{};
    for (final r in rows.where((r) => r.str('status') == 'Active')) {
      byCur[r.str('currency')] = (byCur[r.str('currency')] ?? 0) + r.dbl('amount');
    }
    return PageBody(onRefresh: _load, children: [
      PageHeader(title: 'Adjustments', subtitle: 'Mobilization, bonuses, penalties, damages... added to the next invoice of the machine', actions: [
        Dropdown<String?>(label: 'Status', value: _status, width: 140, items: const [
          DropdownMenuItem(value: null, child: Text('All')),
          DropdownMenuItem(value: 'Active', child: Text('Active')),
          DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
        ], onChanged: (v) { _status = v; _load(); }),
        PickerField(label: 'Vendor', width: 200, valueLabel: _vendor?.label, load: () => Lookups.vendors(), onChanged: (v) { _vendor = v; _load(); }),
        FilledButton.icon(
          onPressed: () async {
            final ok = await showAdjustmentDialog(context);
            if (ok != null) _load();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('New adjustment'),
        ),
      ]),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(label: 'Adjustments', value: '${rows.length}', icon: Icons.tune_rounded),
        for (final e in byCur.entries)
          KpiTile(label: 'Net effect (${e.key})', value: Fmt.money(e.value, e.key), color: e.value < 0 ? AppColors.breakdown : AppColors.working, width: 210),
      ]),
      const SizedBox(height: 12),
      if (_s.loading && _s.data == null)
        const LoadingView()
      else if (_s.error != null)
        ErrorView(error: _s.error!, onRetry: _load)
      else
        TableCard(
          empty: 'No adjustment.',
          columns: const [
            DataColumn(label: Text('Date')), DataColumn(label: Text('Machine')), DataColumn(label: Text('Vendor')), DataColumn(label: Text('Site')),
            DataColumn(label: Text('Type')), DataColumn(label: Text('Amount'), numeric: true), DataColumn(label: Text('Reason')),
            DataColumn(label: Text('Status')), DataColumn(label: Text('By')), DataColumn(label: Text('')),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(Fmt.dayLabel(r.str('adjustment_date')))),
                DataCell(Text(r.machineName, style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(r.str('vendor_name'))),
                DataCell(Text(r.str('site_code', 'any'))),
                DataCell(Text(r.str('adjustment_type'))),
                DataCell(Text(Fmt.money(r.dbl('amount'), r.str('currency')),
                    style: TextStyle(fontWeight: FontWeight.w800, color: r.dbl('amount') < 0 ? AppColors.breakdown : AppColors.working))),
                DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(r.str('reason'), maxLines: 2, overflow: TextOverflow.ellipsis))),
                DataCell(Wrap(spacing: 4, runSpacing: 4, children: [
                  Pill(r.str('status'), color: r.str('status') == 'Active' ? AppColors.working : AppColors.neutral),
                  if (r.intOrNull('in_batch_id') != null) Pill('Batch #${r.str('in_batch_id')}', color: AppColors.info),
                ])),
                DataCell(Text(r.str('created_by'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                DataCell(r.intOrNull('correction_id') != null || r.strOrNull('correction_note_no') != null
                    // the settlement of an approved correction belongs to it: never cancelled by hand
                    ? Tooltip(
                        message: 'Settles correction #${r.str('correction_id')}${r.strOrNull('correction_note_no') == null ? '' : ' (${r.str('correction_note_no')})'}. '
                            'It cannot be cancelled; a mistake is fixed by a new correction.',
                        child: const Icon(Icons.lock_rounded, size: 18, color: AppColors.navy),
                      )
                    : r.str('status') == 'Active'
                        ? IconButton(tooltip: 'Cancel', icon: const Icon(Icons.block_rounded, size: 18, color: AppColors.breakdown), onPressed: () => _cancel(r))
                        : const SizedBox()),
              ]),
          ],
        ),
    ]);
  }
}

/// Create-adjustment dialog (also used from the machine page).
/// Returns the created adjustment or null.
Future<Json?> showAdjustmentDialog(BuildContext context, {PickOption? machine, PickOption? site, String? date, String? reason}) {
  var m = machine;
  var s = site;
  var d = date ?? Fmt.today();
  var type = 'Other';
  var deduction = false;
  final amount = TextEditingController();
  final why = TextEditingController(text: reason ?? '');
  return showFormDialog<Json>(
    context,
    title: 'New adjustment',
    saveLabel: 'Create',
    onSave: () async {
      if (m == null) throw ApiException(null, 'VALIDATION', 'Choose the machine.');
      final a = (numOrNull(amount) ?? 0).abs();
      return asJson(await Api.I.post('/equipment/adjustments', {
        'equipment_id': m!.value, 'site_id': s?.value, 'adjustment_date': d, 'adjustment_type': type,
        'amount': deduction ? -a : a, 'reason': why.text.trim(),
      }));
    },
    body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormGrid(children: [
        PickerField(label: 'Machine *', valueLabel: m?.label, icon: Icons.precision_manufacturing_rounded, load: () => Lookups.machines(), onChanged: (v) => set(() => m = v)),
        PickerField(label: 'Site (optional)', valueLabel: s?.label, icon: Icons.location_city_rounded, load: () => Lookups.sites(activeOnly: false), onChanged: (v) => set(() => s = v)),
        DateField(label: 'Date', value: d, onChanged: (v) => set(() => d = v ?? d)),
        Dropdown<String>(label: 'Type', value: type, width: null, items: [
          for (final t in _adjTypes) DropdownMenuItem(value: t, child: Text(t)),
        ], onChanged: (v) => set(() {
              type = v ?? type;
              deduction = _deductionTypes.contains(type);
            })),
      ]),
      const SizedBox(height: 14),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.add_circle_outline_rounded), label: Text('Add to vendor')),
          ButtonSegment(value: true, icon: Icon(Icons.remove_circle_outline_rounded), label: Text('Deduct from vendor')),
        ],
        selected: {deduction},
        onSelectionChanged: (v) => set(() => deduction = v.first),
      ),
      const SizedBox(height: 14),
      textField(amount, 'Amount', number: true, required: true, hint: 'in the currency of the machine contract'),
      const SizedBox(height: 12),
      textField(why, 'Reason', required: true, maxLines: 2),
    ]),
  );
}

// ================================================================= official fuel prices
/// National fuel price list used by the fuel price difference. Each price is valid until the next one.
class _FuelPricesTab extends StatefulWidget {
  const _FuelPricesTab();
  @override
  State<_FuelPricesTab> createState() => _FuelPricesTabState();
}

class _FuelPricesTabState extends State<_FuelPricesTab> with AutomaticKeepAliveClientMixin {
  final _s = Loadable<List<Json>>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/fuel-prices');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _add() async {
    var from = Fmt.today();
    var currency = 'USD';
    final price = TextEditingController();
    final note = TextEditingController();
    final r = await showFormDialog<Json>(
      context,
      title: 'New official fuel price',
      width: 440,
      onSave: () async => asJson(await Api.I.post('/equipment/fuel-prices', {
        'currency': currency, 'effective_from': from, 'price_per_liter': numOrNull(price), if (textOrNull(note) != null) 'note': textOrNull(note),
      })),
      body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Valid from this date until the next price. Used to pay the fuel price difference of the machines that have one.',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 14),
        DateField(label: 'Valid from', value: from, onChanged: (v) => set(() => from = v ?? from)),
        const SizedBox(height: 12),
        Dropdown<String>(label: 'Currency', value: currency, width: null, items: const [
          DropdownMenuItem(value: 'USD', child: Text('USD')),
          DropdownMenuItem(value: 'SYP', child: Text('SYP')),
          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
        ], onChanged: (v) => set(() => currency = v ?? currency)),
        const SizedBox(height: 12),
        textField(price, 'Official price per litre', number: true, required: true),
        const SizedBox(height: 12),
        textField(note, 'Note', hint: 'e.g. decision no. / date of the increase'),
      ]),
    );
    if (r != null) _load();
  }

  Future<void> _delete(Json p) async {
    final reason = await promptText(context, 'Delete this price?',
        label: 'Reason (required when a draft invoice uses this price)',
        required: false,
        confirm: 'Delete',
        help: '${p.str('currency')} ${p.str('price_per_liter')} from ${Fmt.date(p.str('effective_from'))}. A price used by an invoice handed over to finance cannot be deleted.');
    if (reason == null) return;
    try {
      await Api.I.delete('/equipment/fuel-prices/${p.intv('fuel_price_id')}', {if (reason.isNotEmpty) 'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _s.data ?? <Json>[];
    final today = Fmt.today();
    return PageBody(onRefresh: _load, maxWidth: 1000, children: [
      PageHeader(title: 'Official fuel prices', subtitle: 'History of the national fuel price, used for the fuel price difference', actions: [
        if (Auth.I.isAdmin || Auth.I.isAccountant) FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('New price')),
      ]),
      if (_s.loading && _s.data == null)
        const LoadingView()
      else if (_s.error != null)
        ErrorView(error: _s.error!, onRetry: _load)
      else
        TableCard(
          empty: 'No price yet. Add the official price before generating an invoice with a fuel difference.',
          columns: const [
            DataColumn(label: Text('Currency')), DataColumn(label: Text('Valid from')), DataColumn(label: Text('Until')),
            DataColumn(label: Text('Price / L'), numeric: true), DataColumn(label: Text('Note')), DataColumn(label: Text('By')), DataColumn(label: Text('')),
          ],
          rows: [
            for (final p in rows)
              DataRow(cells: [
                DataCell(Text(p.str('currency'), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(Fmt.date(p.str('effective_from')))),
                DataCell(p.strOrNull('effective_to') == null
                    ? (p.str('effective_from').compareTo(today) <= 0 ? const Pill('Current', color: AppColors.gold) : const Pill('Upcoming', color: AppColors.info))
                    : Text(Fmt.date(p.str('effective_to')))),
                DataCell(Text(p.str('price_per_liter'), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(p.str('note'))),
                DataCell(Text(p.str('created_by'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                DataCell(Auth.I.isAdmin || Auth.I.isAccountant
                    ? IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.breakdown), onPressed: () => _delete(p))
                    : const SizedBox()),
              ]),
          ],
        ),
    ]);
  }
}
