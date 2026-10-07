import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';
import 'rate_card_form.dart' show dnrUnits;

/// Short unit text for tables (trip, t, m³...).
String dnrUnitShort(String u) => const {'trip': 'trip', 't': 't', 'm3': 'm³', 'km': 'km', 'pc': 'pc', 'load': 'load'}[u] ?? u;

Color _stateColor(String? s) => switch (s) {
      'Paid' => AppColors.working,
      'Finalized' => AppColors.info,
      'Draft' => AppColors.standby,
      _ => AppColors.neutral,
    };

/// DNR register (Delivery Note Registry): every paper delivery note paid per unit (trip, ton...) to an existing vendor.
/// Admin and Accountant. Opened from the menu, or from a machine page with [machine] (filtered on that machine).
class DeliveryNotesScreen extends StatefulWidget {
  const DeliveryNotesScreen({super.key, this.machine});
  final Json? machine;

  /// From a machine page: the register of that machine in its own page.
  static Future<void> openForMachine(BuildContext context, Json machine) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('Delivery notes (DNR) - ${machine.str('equipment_code')}')),
            body: DeliveryNotesScreen(machine: machine),
          ),
        ),
      );

  @override
  State<DeliveryNotesScreen> createState() => _DeliveryNotesScreenState();
}

class _DeliveryNotesScreenState extends State<DeliveryNotesScreen> {
  final _s = Loadable<List<Json>>();
  late String _from;
  late String _to;
  PickOption? _vendor;
  PickOption? _machine;
  PickOption? _site;
  String? _status = 'Active';
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    final n = Fmt.now();
    _from = Fmt.dateOf(DateTime(n.year, n.month - 1, 1));
    _to = Fmt.today();
    final m = widget.machine;
    if (m != null) _machine = PickOption(m.intv('equipment_id'), m.str('equipment_code'));
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/delivery-notes', query: {
        'from': _from, 'to': _to, 'vendor_id': _vendor?.value, 'equipment_id': _machine?.value, 'site_id': _site?.value, 'status': _status, 'q': _q.text.trim(),
      });
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _edit([Json? note]) async {
    final r = await showDeliveryNoteDialog(context, note: note, machine: widget.machine);
    if (r != null) _load();
  }

  Future<void> _cancel(Json n) async {
    final reason = await promptText(context, 'Cancel delivery note ${n.str('dn_number')}?',
        label: 'Reason (kept in the history)', minLength: 3, confirm: 'Cancel the note',
        help: 'A cancelled note is kept but never paid. Its number can be used again.');
    if (reason == null) return;
    try {
      await Api.I.patch('/equipment/delivery-notes/${n.intv('delivery_note_id')}/cancel', {'reason': reason});
      if (!mounted) return;
      showSnack(context, 'Delivery note cancelled.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final active = rows.where((r) => r.str('status') == 'Active').toList();
    final totals = <String, double>{};
    for (final r in active) {
      totals[r.str('currency')] = (totals[r.str('currency')] ?? 0) + r.dbl('amount');
    }
    final notBilled = active.where((r) => r.intOrNull('in_batch_id') == null).length;
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(
          title: widget.machine == null ? 'Delivery notes (DNR)' : 'Delivery notes of ${widget.machine!.str('equipment_code')}',
          subtitle: 'Paid per unit (trip, ton, m³...) at the DNR price of the vendor. Each note is paid once, in the payroll of its date.',
          actions: [
            DateField(label: 'From', value: _from, width: 150, onChanged: (v) { _from = v ?? _from; _load(); }),
            DateField(label: 'To', value: _to, width: 150, onChanged: (v) { _to = v ?? _to; _load(); }),
            if (widget.machine == null) ...[
              PickerField(label: 'Vendor', width: 190, valueLabel: _vendor?.label, load: () => Lookups.vendors(), onChanged: (v) { _vendor = v; _load(); }),
              PickerField(label: 'Machine', width: 190, valueLabel: _machine?.label, load: () => Lookups.machines(vendorId: _vendor?.value as int?), onChanged: (v) { _machine = v; _load(); }),
            ],
            PickerField(label: 'Site', width: 170, valueLabel: _site?.label, load: () => Lookups.sites(activeOnly: false), onChanged: (v) { _site = v; _load(); }),
            Dropdown<String?>(label: 'Status', value: _status, width: 130, items: const [
              DropdownMenuItem(value: 'Active', child: Text('Active')),
              DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
              DropdownMenuItem(value: null, child: Text('All')),
            ], onChanged: (v) { _status = v; _load(); }),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _q,
                decoration: const InputDecoration(labelText: 'Search no., item, driver', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                onSubmitted: (_) => _load(),
              ),
            ),
            FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('New delivery note')),
          ],
        ),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'Delivery notes', value: '${active.length}', icon: Icons.receipt_rounded),
          KpiTile(label: 'Not in a payroll yet', value: '$notBilled', color: notBilled == 0 ? AppColors.working : AppColors.standby, icon: Icons.pending_actions_rounded),
          for (final e in totals.entries)
            KpiTile(label: 'Total (${e.key})', value: Fmt.money(e.value, e.key), color: AppColors.navy, icon: Icons.local_shipping_rounded, width: 220),
        ]),
        const SizedBox(height: 14),
        if (_s.loading && _s.data == null)
          const LoadingView()
        else if (_s.error != null)
          ErrorView(error: _s.error!, onRetry: _load)
        else
          TableCard(
            empty: 'No delivery note for these filters. Add the DNR prices on the machine page (Rate cards > New rate card > DNR), then record the notes here.',
            columns: const [
              DataColumn(label: Text('DN no.')), DataColumn(label: Text('Date')), DataColumn(label: Text('Machine')), DataColumn(label: Text('Vendor')),
              DataColumn(label: Text('Site')), DataColumn(label: Text('Item')), DataColumn(label: Text('Qty'), numeric: true),
              DataColumn(label: Text('Unit price'), numeric: true), DataColumn(label: Text('Amount'), numeric: true), DataColumn(label: Text('Payroll')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(r.str('dn_number'), style: TextStyle(fontWeight: FontWeight.w800, decoration: r.str('status') == 'Cancelled' ? TextDecoration.lineThrough : null))),
                  DataCell(Text(Fmt.date(r.str('note_date')))),
                  DataCell(Text(r.str('equipment_code'))),
                  DataCell(Text(r.str('vendor_name'))),
                  DataCell(Text(r.str('site_code'))),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text([
                      r.str('item_name'),
                      if (r.strOrNull('material') != null) r.str('material'),
                      if (r.strOrNull('from_location') != null || r.strOrNull('to_location') != null) '${r.str('from_location', '?')} > ${r.str('to_location', '?')}',
                    ].join('  ·  '), overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(Text('${Fmt.num2(r.dblOrNull('quantity'))} ${dnrUnitShort(r.str('unit'))}')),
                  DataCell(Text(Fmt.num2(r.dblOrNull('unit_price')))),
                  DataCell(Text(Fmt.money2(r.strOrNull('amount'), r.str('currency')), style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(r.str('status') == 'Cancelled'
                      ? const Pill('Cancelled', color: AppColors.neutral, outlined: true)
                      : r.intOrNull('in_batch_id') == null
                          ? const Pill('Not billed yet', color: AppColors.muted, outlined: true)
                          : Pill('#${r.str('in_batch_id')} ${r.str('batch_state')}', color: _stateColor(r.strOrNull('batch_state')))),
                  DataCell(r.str('status') == 'Cancelled' || r.str('batch_state') == 'Finalized' || r.str('batch_state') == 'Paid'
                      ? const SizedBox()
                      : PopupMenuButton<String>(
                          onSelected: (v) => v == 'edit' ? _edit(r) : _cancel(r),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Correct'))),
                            PopupMenuItem(value: 'cancel', child: ListTile(leading: Icon(Icons.block_rounded, color: AppColors.breakdown), title: Text('Cancel'))),
                          ],
                        )),
                ]),
            ],
          ),
      ],
    );
  }
}

/// Create ([note] == null) or correct a delivery note. Returns the saved note (null when cancelled).
Future<Json?> showDeliveryNoteDialog(BuildContext context, {Json? note, Json? machine}) async {
  final editing = note != null;
  final Json n = note ?? <String, dynamic>{};
  PickOption? m = editing
      ? PickOption(n.intv('equipment_id'), n.str('equipment_code'))
      : machine == null
          ? null
          : PickOption(machine.intv('equipment_id'), machine.str('equipment_code'));
  PickOption? site = editing ? PickOption(n.intv('site_id'), n.str('site_code')) : null;
  var date = editing ? n.str('note_date') : Fmt.today();
  Json? price = editing ? {'dnr_rate_id': n.intv('dnr_rate_id'), 'item_name': n.str('item_name'), 'unit': n.str('unit'), 'unit_price': n.str('unit_price'), 'currency': n.str('currency')} : null;
  final number = TextEditingController(text: n.str('dn_number'));
  final qty = TextEditingController(text: n.str('quantity'));
  final from = TextEditingController(text: n.str('from_location'));
  final to = TextEditingController(text: n.str('to_location'));
  final material = TextEditingController(text: n.str('material'));
  final driver = TextEditingController(text: n.str('driver_name'));
  final remark = TextEditingController(text: n.str('note'));
  List<Json> warnings = [];

  Future<List<PickOption>> prices() async {
    if (m == null) throw ApiException(null, 'VALIDATION', 'Choose the machine first.');
    final list = await Api.I.getList('/equipment/dnr-rates', query: {'equipment_id': m!.value, 'status': 'Active', 'on': date});
    if (list.isEmpty) {
      throw ApiException(null, 'NO_DNR_PRICE', 'This machine has no DNR price on $date. Add one on the machine page: Rate cards > New rate card > DNR (per unit).');
    }
    return [
      for (final r in list)
        PickOption(r, '${r.str('item_name')}  ·  ${Fmt.money2(r.strOrNull('unit_price'), r.str('currency'))} / ${dnrUnits[r.str('unit')]?.split(' ').first ?? r.str('unit')}',
            '${r.str('applies_to') == 'machine' ? 'this machine' : 'every machine of ${r.str('vendor_name')}'}  ·  contract ${r.str('contract_number')}'),
    ];
  }

  Map<String, dynamic> body() => {
        if (!editing) 'equipment_id': m?.value,
        'site_id': site?.value,
        'dnr_rate_id': price?.intv('dnr_rate_id'),
        'dn_number': number.text.trim(),
        'note_date': date,
        'quantity': numOrNull(qty),
        'from_location': textOrNull(from),
        'to_location': textOrNull(to),
        'material': textOrNull(material),
        'driver_name': textOrNull(driver),
        'note': textOrNull(remark),
      };

  final saved = await showFormDialog<Json>(
    context,
    title: editing ? 'Correct delivery note ${n.str('dn_number')}' : 'New delivery note (DNR)',
    width: 620,
    onSave: () async {
      if (m == null || site == null || price == null) throw ApiException(null, 'VALIDATION', 'Choose the machine, the site and the price item.');
      final path = editing ? '/equipment/delivery-notes/${n.intv('delivery_note_id')}' : '/equipment/delivery-notes';
      Json env;
      try {
        env = await Api.I.request(editing ? 'PATCH' : 'POST', path, body: body());
      } on ApiException catch (e) {
        // changing quantity / price / date / site of a note asks why (kept in the history)
        final fields = e.details?.obj('fields') ?? <String, dynamic>{};
        if (!editing || e.code != 'VALIDATION_ERROR' || !fields.containsKey('reason') || !context.mounted) rethrow;
        final reason = await promptText(context, 'Why does this delivery note change?', label: 'Reason (kept in the history)', minLength: 5);
        if (reason == null) throw ApiException(null, 'CANCELLED', 'Not saved.');
        env = await Api.I.request('PATCH', path, body: {...body(), 'reason': reason});
      }
      warnings = asJsonList(env['warnings']);
      return asJson(env['data']);
    },
    body: (ctx, set) {
      final q = numOrNull(qty);
      final p = price == null ? null : double.tryParse(price!.str('unit_price'));
      final amount = q == null || p == null ? null : q * p;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormGrid(children: [
          PickerField(
            label: 'Machine *',
            icon: Icons.local_shipping_rounded,
            valueLabel: m?.label,
            enabled: !editing && machine == null,
            clearable: false,
            load: () => Lookups.machines(status: 'Active'),
            onChanged: (v) => set(() { m = v; price = null; }),
          ),
          PickerField(label: 'Site *', icon: Icons.location_city_rounded, valueLabel: site?.label, clearable: false, load: () => Lookups.sites(), onChanged: (v) => set(() => site = v)),
          textField(number, 'Delivery note number', required: true, hint: 'as printed on the paper'),
          DateField(label: 'Date *', value: date, last: Fmt.today(), onChanged: (v) => set(() { date = v ?? date; })),
          PickerField(
            label: 'Price item *',
            icon: Icons.sell_rounded,
            valueLabel: price == null ? null : '${price!.str('item_name')}  ·  ${Fmt.money2(price!.strOrNull('unit_price'), price!.str('currency'))} / ${dnrUnits[price!.str('unit')]?.split(' ').first ?? price!.str('unit')}',
            clearable: false,
            load: prices,
            onChanged: (v) => set(() => price = v == null ? null : asJson(v.value)),
          ),
          TextFormField(
            controller: qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Quantity *', suffixText: price == null ? null : dnrUnitShort(price!.str('unit'))),
            onChanged: (_) => set(() {}),
            validator: (v) {
              final x = double.tryParse((v ?? '').trim());
              if (x == null || x <= 0) return 'Enter a quantity above 0';
              return null;
            },
          ),
          textField(from, 'From (loading place)'),
          textField(to, 'To (delivery place)'),
          textField(material, 'Material / load'),
          textField(driver, 'Driver'),
        ]),
        const SizedBox(height: 12),
        textField(remark, 'Note', maxLines: 2),
        if (amount != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Amount: ${Fmt.num2(q)} x ${Fmt.num2(p)} = ${Fmt.money(amount, price!.str('currency'))}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
          ),
        if (editing && n.str('unit_price') != (price?.str('unit_price') ?? n.str('unit_price')))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('The note takes the price of the newly chosen item.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ),
      ]);
    },
  );
  if (saved != null && context.mounted) {
    final w = warningsText({'warnings': warnings});
    showSnack(context, w == null ? 'Delivery note saved.' : 'Delivery note saved. $w');
  }
  return saved;
}
