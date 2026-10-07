import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';
import 'delivery_notes_screen.dart';
import 'rate_card_form.dart';

Color machineStatusColor(String s) => s == 'Active' ? AppColors.working : s == 'Released' ? AppColors.info : AppColors.neutral;

String rateText(Json r) {
  final cur = r.str('currency');
  switch (r.str('billing_mode')) {
    case 'Hourly':
      return '${Fmt.money2(r.strOrNull('hourly_rate'), cur)} / h';
    case 'Daily':
      return '${Fmt.money2(r.strOrNull('daily_rate'), cur)} / day';
    case 'Monthly':
      return '${Fmt.money2(r.strOrNull('monthly_rate'), cur)} / month';
  }
  return '-';
}

/// Fleet: every rented machine with its vendor, current site and price.
class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key});
  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  final _s = Loadable<List<Json>>();
  int _total = 0;
  final _q = TextEditingController();
  PickOption? _vendor;
  String? _status = 'Active';
  String? _deployed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      final r = await Api.I.request('GET', '/equipment/machines', query: {
        'q': _q.text.trim(), 'vendor_id': _vendor?.value, 'status': _status, 'deployed': _deployed, 'page_size': 200,
      });
      _s.data = asJsonList(r['data']);
      _total = asJson(r['meta']).intv('total');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _open(Json m) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MachineDetailScreen(id: m.intv('equipment_id'))));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final deployed = rows.where((r) => r.strOrNull('site_code') != null).length;
    // a machine paid only per delivery note (DNR) has a price even without a time rate card
    final noRate = rows.where((r) => r.strOrNull('rate_card_id') == null && r.intv('dnr_rates') == 0 && r.str('status') == 'Active').length;
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Machines', subtitle: 'Rented machines, where they work and how they are priced', actions: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(labelText: 'Search code, plate, model', prefixIcon: Icon(Icons.search_rounded, size: 20)),
              onSubmitted: (_) => _load(),
            ),
          ),
          PickerField(label: 'Vendor', width: 200, valueLabel: _vendor?.label, load: () => Lookups.vendors(), onChanged: (v) { _vendor = v; _load(); }),
          Dropdown<String?>(label: 'Status', value: _status, width: 130, items: const [
            DropdownMenuItem(value: null, child: Text('All')),
            DropdownMenuItem(value: 'Active', child: Text('Active')),
            DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
            DropdownMenuItem(value: 'Released', child: Text('Released')),
          ], onChanged: (v) { _status = v; _load(); }),
          Dropdown<String?>(label: 'Deployed', value: _deployed, width: 140, items: const [
            DropdownMenuItem(value: null, child: Text('Any')),
            DropdownMenuItem(value: 'true', child: Text('On a site')),
            DropdownMenuItem(value: 'false', child: Text('Idle')),
          ], onChanged: (v) { _deployed = v; _load(); }),
          if (Auth.I.isAdmin || Auth.I.isAccountant)
            FilledButton.icon(
              onPressed: () async {
                final m = await showMachineDialog(context);
                if (m != null && mounted) _open(m);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New machine'),
            ),
        ]),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'Machines', value: '$_total', icon: Icons.precision_manufacturing_rounded),
          KpiTile(label: 'On a site today', value: '$deployed', color: AppColors.working, icon: Icons.location_on_rounded),
          KpiTile(label: 'Idle', value: '${rows.length - deployed}', color: AppColors.muted, icon: Icons.pause_circle_rounded),
          KpiTile(label: 'Active without price', value: '$noRate', color: noRate == 0 ? AppColors.working : AppColors.breakdown, icon: Icons.price_change_rounded),
        ]),
        const SizedBox(height: 14),
        if (_s.loading && _s.data == null)
          const LoadingView()
        else if (_s.error != null)
          ErrorView(error: _s.error!, onRetry: _load)
        else
          TableCard(
            empty: 'No machine for these filters.',
            columns: const [
              DataColumn(label: Text('Code')), DataColumn(label: Text('Type')), DataColumn(label: Text('Vendor')),
              DataColumn(label: Text('Make / model')), DataColumn(label: Text('Plate')), DataColumn(label: Text('Status')),
              DataColumn(label: Text('Site today')), DataColumn(label: Text('Price today')),
            ],
            rows: [
              for (final r in rows)
                DataRow(onSelectChanged: (_) => _open(r), cells: [
                  DataCell(Text(r.str('equipment_code'), style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text(r.str('type_name'))),
                  DataCell(Text(r.str('vendor_name'))),
                  DataCell(Text([r.str('make'), r.str('model')].where((x) => x.isNotEmpty).join(' '))),
                  DataCell(Text(r.str('plate_number', '-'))),
                  DataCell(Pill(r.str('status'), color: machineStatusColor(r.str('status')))),
                  DataCell(r.strOrNull('site_code') == null
                      ? const Text('-', style: TextStyle(color: AppColors.muted))
                      : Text(r.str('deployments_today', r.str('site_code')), style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(r.strOrNull('rate_card_id') == null
                      ? (r.intv('dnr_rates') > 0
                          ? const Pill('DNR (per unit)', color: AppColors.info, icon: Icons.local_shipping_rounded)
                          : Pill('No price', color: r.str('status') == 'Active' ? AppColors.breakdown : AppColors.neutral, icon: Icons.warning_amber_rounded))
                      : Text(r.intv('dnr_rates') > 0 ? '${rateText(r)}  + DNR' : rateText(r))),
                ]),
            ],
          ),
      ],
    );
  }
}

/// Create (machine == null) or edit a machine. Returns the saved machine.
Future<Json?> showMachineDialog(BuildContext context, {Json? machine, PickOption? vendor}) async {
  final m = machine;
  var v = m == null ? vendor : PickOption(m.intv('vendor_id'), m.str('vendor_name'));
  var t = m == null ? null : PickOption(m.intv('type_id'), m.str('type_name'));
  final make = TextEditingController(text: m?.str('make'));
  final model = TextEditingController(text: m?.str('model'));
  final plate = TextEditingController(text: m?.str('plate_number'));
  final serial = TextEditingController(text: m?.str('serial_number'));
  final year = TextEditingController(text: m?.str('manufacture_year'));
  final capacity = TextEditingController(text: m?.str('capacity'));
  final notes = TextEditingController(text: m?.str('notes'));

  Future<List<PickOption>> typesWithNew() async {
    final list = await Lookups.types();
    return [...list, PickOption('__new', '+ New type...', 'Excavator, loader, crane...')];
  }

  return showFormDialog<Json>(
    context,
    title: m == null ? 'New machine' : 'Edit ${m.str('equipment_code')}',
    onSave: () async {
      if (v == null || t == null) throw ApiException(null, 'VALIDATION', 'Vendor and type are required.');
      final body = {
        'vendor_id': v!.value, 'type_id': t!.value, 'make': textOrNull(make), 'model': textOrNull(model), 'plate_number': textOrNull(plate),
        'serial_number': textOrNull(serial), 'manufacture_year': numOrNull(year)?.toInt(), 'capacity': textOrNull(capacity), 'notes': textOrNull(notes),
      }..removeWhere((k, x) => x == null);
      return asJson(m == null ? await Api.I.post('/equipment/machines', body) : await Api.I.put('/equipment/machines/${m.intv('equipment_id')}', body));
    },
    body: (ctx, set) => FormGrid(children: [
      PickerField(label: 'Vendor *', valueLabel: v?.label, icon: Icons.business_rounded, clearable: false, load: () => Lookups.vendors(activeOnly: true), onChanged: (x) => set(() => v = x)),
      PickerField(
        label: 'Type *',
        valueLabel: t?.label,
        icon: Icons.category_rounded,
        clearable: false,
        load: typesWithNew,
        onChanged: (x) async {
          if (x?.value != '__new') {
            set(() => t = x);
            return;
          }
          final name = await promptText(ctx, 'New machine type', label: 'Type name (English)', maxLines: 1, confirm: 'Create');
          if (name == null) return;
          try {
            final created = asJson(await Api.I.post('/equipment/types', {'type_name': name, 'meter_unit': 'Hours'}));
            set(() => t = PickOption(created.intv('type_id'), created.str('type_name')));
          } catch (e) {
            if (ctx.mounted) showError(ctx, e);
          }
        },
      ),
      textField(make, 'Make'),
      textField(model, 'Model'),
      textField(plate, 'Plate number'),
      textField(serial, 'Serial number'),
      textField(year, 'Year', number: true, decimal: false),
      textField(capacity, 'Capacity', hint: 'e.g. 20 t, 1.2 m³'),
      textField(notes, 'Notes', maxLines: 2),
    ]),
  );
}

// ================================================================ machine detail
class MachineDetailScreen extends StatefulWidget {
  const MachineDetailScreen({super.key, required this.id});
  final int id;
  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  Json? _m;
  Object? _error;
  Uint8List? _photo;
  List<Json> _cards = [];
  List<Json> _dnr = [];

  /// Admin and Accountant manage machines, deployments, rate cards and fuel terms.
  bool get _admin => Auth.I.isAdmin || Auth.I.isAccountant;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await Api.I.getObj('/equipment/machines/${widget.id}');
      final cards = await Api.I.getList('/equipment/machines/${widget.id}/rate-cards');
      final dnr = _admin ? await Api.I.getList('/equipment/machines/${widget.id}/dnr-rates') : <Json>[];
      Uint8List? photo;
      if (m.flag('has_photo')) {
        try {
          photo = await Api.I.getBytes('/equipment/machines/${widget.id}/photo');
        } catch (_) {}
      }
      if (mounted) setState(() { _m = m; _cards = cards; _dnr = dnr; _photo = photo; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _do(Future<dynamic> Function() fn, String ok) async {
    try {
      await fn();
      if (!mounted) return;
      showSnack(context, ok);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _uploadPhoto() async {
    final f = await pickOneFile(label: 'Photo', extensions: ['jpg', 'jpeg', 'png', 'webp']);
    if (f == null) return;
    _do(() => Api.I.upload('/equipment/machines/${widget.id}/photo', [f]), 'Photo saved.');
  }

  Future<void> _status() async {
    final m = _m!;
    final p = await pickFromList(context, 'Machine status', [
      PickOption('Active', 'Active', 'Can be deployed and recorded'),
      PickOption('Inactive', 'Inactive', 'Temporarily out of use'),
      PickOption('Released', 'Released', 'Returned to the vendor'),
    ]);
    if (p == null || p.value == m.str('status') || !mounted) return;
    final reason = await promptText(context, 'Set ${m.str('equipment_code')} to ${p.label}', label: 'Reason', required: false);
    if (reason == null) return;
    _do(() => Api.I.patch('/equipment/machines/${widget.id}/status', {'status': p.value, 'reason': reason}), 'Status changed.');
  }

  // ------------------------------------------------------------- deployments
  Future<void> _deploy() async {
    PickOption? site;
    var shift = 'Day';
    var from = Fmt.today();
    String? to;
    final notes = TextEditingController();
    final m = _m!;
    final r = await showFormDialog<Map<String, dynamic>>(
      context,
      title: 'Deploy ${m.str('equipment_code')} to a site',
      saveLabel: 'Deploy',
      onSave: () async {
        if (site == null) throw ApiException(null, 'VALIDATION', 'Choose the site.');
        return asJson((await Api.I.request('POST', '/equipment/deployments', body: {
          'equipment_id': widget.id, 'site_id': site!.value, 'shift_type': shift, 'assigned_date': from,
          if (to != null) 'unassigned_date': to, if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
        })));
      },
      body: (ctx, set) => FormGrid(children: [
        PickerField(label: 'Site *', valueLabel: site?.label, icon: Icons.location_city_rounded, load: () => Lookups.sites(), onChanged: (x) => set(() => site = x)),
        Dropdown<String>(label: 'Shift', value: shift, width: null, items: const [
          DropdownMenuItem(value: 'Day', child: Text('Day')),
          DropdownMenuItem(value: 'Night', child: Text('Night')),
        ], onChanged: (x) => set(() => shift = x ?? shift)),
        DateField(label: 'First day *', value: from, onChanged: (x) => set(() => from = x ?? from)),
        DateField(label: 'Last day (open)', value: to, clearable: true, onChanged: (x) => set(() => to = x)),
        textField(notes, 'Notes'),
      ]),
    );
    if (r == null || !mounted) return;
    final w = (r['warnings'] as List?) ?? const [];
    showSnack(context, w.contains('NO_RATE_CARD_ON_START_DATE') ? 'Deployed. Warning: the machine has no rate card on the first day.' : 'Deployed.',
        error: w.isNotEmpty);
    _load();
  }

  Future<void> _end(Json d) async {
    var date = Fmt.today();
    final reason = TextEditingController();
    final ok = await showFormDialog<bool>(
      context,
      title: 'End deployment at ${d.str('site_code')}',
      saveLabel: 'End deployment',
      width: 420,
      onSave: () async {
        await Api.I.patch('/equipment/deployments/${d.intv('eq_assignment_id')}/end', {'unassigned_date': date, 'reason': textOrNull(reason)});
        return true;
      },
      body: (ctx, set) => Column(children: [
        DateField(label: 'Last day on the site', value: date, onChanged: (x) => set(() => date = x ?? date)),
        const SizedBox(height: 12),
        textField(reason, 'Reason'),
      ]),
    );
    if (ok == true && mounted) {
      showSnack(context, 'Deployment ended.');
      _load();
    }
  }

  /// The first day was entered wrong (machine arrived earlier / later): reason required, refused inside a closed period
  /// and when it would leave recorded days outside the deployment.
  Future<void> _changeStart(Json d) async {
    var date = d.str('assigned_date');
    final reason = TextEditingController();
    final ok = await showFormDialog<bool>(
      context,
      title: 'Correct the first day at ${d.str('site_code')}',
      saveLabel: 'Save',
      width: 440,
      onSave: () async {
        await Api.I.patch('/equipment/deployments/${d.intv('eq_assignment_id')}/start', {'assigned_date': date, 'reason': reason.text.trim()});
        return true;
      },
      body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Use this when the first day was entered wrong. Days already paid by a finalized payroll cannot move: use an official Correction.',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        DateField(label: 'Real first day on the site', value: date, onChanged: (x) => set(() => date = x ?? date)),
        const SizedBox(height: 12),
        TextFormField(
          controller: reason,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Reason *', hintText: 'e.g. gate log shows the 17th'),
          validator: (v) => (v ?? '').trim().length < 5 ? 'Write at least 5 characters' : null,
        ),
      ]),
    );
    if (ok == true && mounted) {
      showSnack(context, 'First day corrected.');
      _load();
    }
  }

  Future<void> _transfer(Json d) async {
    PickOption? site;
    var shift = 'Day';
    var first = Fmt.today();
    final m = _m!;
    final ok = await showFormDialog<bool>(
      context,
      title: 'Transfer ${m.str('equipment_code')} from ${d.str('site_code')}',
      saveLabel: 'Transfer',
      onSave: () async {
        if (site == null) throw ApiException(null, 'VALIDATION', 'Choose the target site.');
        await Api.I.post('/equipment/deployments/${d.intv('eq_assignment_id')}/transfer', {'target_site_id': site!.value, 'target_shift_type': shift, 'first_day_at_target': first});
        return true;
      },
      body: (ctx, set) => FormGrid(children: [
        PickerField(label: 'Target site *', valueLabel: site?.label, icon: Icons.location_city_rounded, load: () => Lookups.sites(), onChanged: (x) => set(() => site = x)),
        Dropdown<String>(label: 'Shift', value: shift, width: null, items: const [
          DropdownMenuItem(value: 'Day', child: Text('Day')),
          DropdownMenuItem(value: 'Night', child: Text('Night')),
        ], onChanged: (x) => set(() => shift = x ?? shift)),
        DateField(label: 'First day at the new site', value: first, onChanged: (x) => set(() => first = x ?? first)),
      ]),
    );
    if (ok == true && mounted) {
      showSnack(context, 'Transferred.');
      _load();
    }
  }

  // ------------------------------------------------------------- rate cards
  Future<void> _closeCard(Json c) async {
    final d = await pickDate(context, initial: Fmt.today());
    if (d == null) return;
    _do(() => Api.I.post('/equipment/rate-cards/${c.intv('rate_card_id')}/close', {'effective_to': d}), 'Rate card closed on $d.');
  }

  Future<void> _statement() async {
    final now = Fmt.now();
    final from = await pickDate(context, initial: Fmt.dateOf(DateTime(now.year, now.month, 1)));
    if (from == null || !mounted) return;
    final to = await pickDate(context, initial: Fmt.today());
    if (to == null || !mounted) return;
    PdfViewScreen.open(context,
        title: 'Statement ${_m!.str('equipment_code')}',
        fileName: 'statement-${_m!.str('equipment_code')}-$from-$to.pdf',
        load: () => Api.I.getBytes('/equipment/statements/machine/${widget.id}.pdf', query: {'from': from, 'to': to}));
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(
        title: Text(m == null ? 'Machine' : '${m.str('equipment_code')}  ${m.str('type_name')}'),
        actions: [
          if (m != null) ...[
            TextButton.icon(onPressed: _statement, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Statement')),
            if (_admin)
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () async {
                  final r = await showMachineDialog(context, machine: m);
                  if (r != null) _load();
                },
              ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : m == null
              ? const LoadingView()
              : PageBody(onRefresh: _load, maxWidth: 1200, children: [
                  const SizedBox(height: 16),
                  _header(m),
                  const SizedBox(height: 14),
                  _deployments(m),
                  const SizedBox(height: 14),
                  _rateCards(m),
                  if (_admin) ...[const SizedBox(height: 14), _dnrPrices(m)],
                  const SizedBox(height: 14),
                  _fuelTerms(m),
                  const SizedBox(height: 14),
                  _recent(m),
                ]),
    );
  }

  Widget _header(Json m) {
    final open = m.objOrNull('open_session');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.start, children: [
          InkWell(
            onTap: _admin ? _uploadPhoto : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 200,
              height: 150,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              clipBehavior: Clip.antiAlias,
              child: _photo != null
                  ? Image.memory(_photo!, fit: BoxFit.cover)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.precision_manufacturing_rounded, size: 46, color: AppColors.neutral),
                      if (_admin) const Text('Add photo', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(m.str('equipment_code'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.navy))),
                const SizedBox(width: 10),
                InkWell(onTap: _admin ? _status : null, child: Pill(m.str('status'), color: machineStatusColor(m.str('status')), icon: _admin ? Icons.expand_more_rounded : null)),
              ]),
              const SizedBox(height: 4),
              Text('${m.str('type_name')}  ·  ${[m.str('make'), m.str('model')].where((x) => x.isNotEmpty).join(' ')}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              InfoRow('Vendor', '${m.str('vendor_name')} (${m.str('vendor_code')})', width: 120),
              InfoRow('Plate / serial', '${m.str('plate_number', '-')}  /  ${m.str('serial_number', '-')}', width: 120),
              InfoRow('Year / capacity', '${m.str('manufacture_year', '-')}  /  ${m.str('capacity', '-')}', width: 120),
              if (m.strOrNull('notes') != null) InfoRow('Notes', m.str('notes'), width: 120),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fact(Icons.location_on_rounded, 'Today', m.strOrNull('site_code') == null ? 'Not deployed' : '${m.str('site_code')} ${m.str('site_name')}',
                  m.strOrNull('site_code') == null ? AppColors.muted : AppColors.working),
              _fact(
                  Icons.sell_rounded,
                  'Price today',
                  m.strOrNull('rate_card_id') == null
                      ? (m.intv('dnr_rates') > 0 ? 'Per delivery note (DNR)' : 'No rate card')
                      : '${rateText(m)}${m.intv('dnr_rates') > 0 ? '  + DNR' : ''}',
                  m.strOrNull('rate_card_id') == null && m.intv('dnr_rates') == 0 ? AppColors.breakdown : AppColors.ink),
              if (open != null)
                _fact(Icons.play_circle_rounded, 'Open session', 'since ${Fmt.date(open.str('check_in_time'))} ${Fmt.time(open.str('check_in_time'))}', AppColors.standby),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _fact(IconData icon, String label, String value, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color == AppColors.muted ? AppColors.ink : color)),
            ]),
          ),
        ]),
      );

  Widget _deployments(Json m) {
    final deps = m.list('deployments');
    final today = Fmt.today();
    bool current(Json d) => d.str('assigned_date').compareTo(today) <= 0 && (d.strOrNull('unassigned_date') == null || d.str('unassigned_date').compareTo(today) >= 0);
    bool future(Json d) => d.str('assigned_date').compareTo(today) > 0;
    bool cancelled(Json d) => d.strOrNull('unassigned_date') != null && d.str('unassigned_date').compareTo(d.str('assigned_date')) < 0;
    return SectionCard(
      title: 'Deployments',
      trailing: _admin && m.str('status') == 'Active'
          ? FilledButton.tonalIcon(onPressed: _deploy, icon: const Icon(Icons.add_location_alt_rounded), label: const Text('Deploy'))
          : null,
      child: deps.isEmpty
          ? const EmptyView(text: 'Never deployed.', icon: Icons.location_off_rounded)
          : Column(children: [
              for (final d in deps)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: current(d) ? AppColors.working.withValues(alpha: 0.06) : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: current(d) ? AppColors.working.withValues(alpha: 0.35) : AppColors.line),
                  ),
                  child: Row(children: [
                    Icon(current(d) ? Icons.location_on_rounded : Icons.history_rounded, color: current(d) ? AppColors.working : AppColors.neutral),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text('${d.str('site_code')}  ${d.str('site_name')}', style: const TextStyle(fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          if (d.str('shift_type') == 'Night') const Pill('Night', color: AppColors.navy),
                          if (current(d)) const Pill('Now', color: AppColors.working),
                          if (future(d)) const Pill('Planned', color: AppColors.info),
                          if (cancelled(d)) const Pill('Cancelled', color: AppColors.neutral),
                        ]),
                        Text('${Fmt.date(d.str('assigned_date'))}  →  ${d.strOrNull('unassigned_date') == null ? 'open' : Fmt.date(d.str('unassigned_date'))}'
                            '',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                    if (_admin && (current(d) || future(d)))
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'end') _end(d);
                          if (v == 'transfer') _transfer(d);
                          if (v == 'start') _changeStart(d);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'start', child: ListTile(leading: Icon(Icons.edit_calendar_rounded), title: Text('Correct the first day'))),
                          if (current(d)) const PopupMenuItem(value: 'transfer', child: ListTile(leading: Icon(Icons.swap_horiz_rounded), title: Text('Transfer to another site'))),
                          const PopupMenuItem(value: 'end', child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('End deployment'))),
                        ],
                      ),
                  ]),
                ),
            ]),
    );
  }

  Widget _rateCards(Json m) {
    final today = Fmt.today();
    return SectionCard(
      title: 'Rate cards',
      trailing: _admin
          ? FilledButton.tonalIcon(
              onPressed: () async {
                final ok = await RateCardFormScreen.open(context, machine: m, copyFrom: _cards.isEmpty ? null : _cards.first);
                if (ok == true) _load();
              },
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('New rate card'),
            )
          : null,
      child: _cards.isEmpty
          ? const EmptyView(text: 'No rate card: this machine cannot be paid yet.', icon: Icons.price_change_rounded)
          : Column(children: [
              for (final c in _cards)
                Builder(builder: (context) {
                  final active = c.str('effective_from').compareTo(today) <= 0 && (c.strOrNull('effective_to') == null || c.str('effective_to').compareTo(today) >= 0);
                  final locked = c.flag('used_in_finalized_payroll');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: active ? AppColors.gold : AppColors.line, width: active ? 1.5 : 1),
                      color: active ? AppColors.gold.withValues(alpha: 0.05) : Colors.white,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(rateText(c), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy)),
                        ),
                        if (active) const Pill('Current', color: AppColors.gold),
                        if (locked) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('Used in payroll', color: AppColors.info, icon: Icons.lock_rounded)),
                        if (_admin)
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit' || v == 'copy' || v == 'revise') {
                                final ok = await RateCardFormScreen.open(context, machine: m, card: v == 'edit' ? c : null, copyFrom: v == 'copy' ? c : null, revise: v == 'revise' ? c : null);
                                if (ok == true) _load();
                              }
                              if (v == 'close') _closeCard(c);
                            },
                            itemBuilder: (_) => [
                              if (c.strOrNull('effective_to') == null || c.str('effective_to').compareTo(today) >= 0)
                                const PopupMenuItem(value: 'revise', child: ListTile(leading: Icon(Icons.event_repeat_rounded), title: Text('Change from a date'))),
                              if (!locked) const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Correct (no history)'))),
                              const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('New card from this one'))),
                              const PopupMenuItem(value: 'close', child: ListTile(leading: Icon(Icons.event_busy_rounded), title: Text('Close on a date'))),
                            ],
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text('${Fmt.date(c.str('effective_from'))} → ${c.strOrNull('effective_to') == null ? 'open' : Fmt.date(c.str('effective_to'))}  ·  contract ${c.str('contract_number')}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 14, runSpacing: 4, children: [
                        kv(c.str('billing_mode') == 'Monthly' ? 'Hours per day' : 'Std h/day', c.str('standard_hours_per_day')),
                        if (c.strOrNull('min_billable_hours_per_day') != null && c.str('billing_mode') != 'Monthly') kv('Min h/day', c.str('min_billable_hours_per_day')),
                        if (c.str('billing_mode') == 'Monthly')
                          kv('Overtime', c.strOrNull('overtime_rate') != null ? '${c.str('overtime_rate')} / h' : 'month hourly price')
                        else
                          kv('Overtime', c.flag('overtime_enabled') ? (c.strOrNull('overtime_rate') != null ? c.str('overtime_rate') : '×${c.str('overtime_multiplier')}') : 'no'),
                        kv('Standby', '${c.str('standby_billable_pct')}%'),
                        kv('Breakdown', '${c.str('breakdown_billable_pct')}%'),
                        kv('Breaks', c.str('break_policy')),
                        if (c.str('billing_mode') == 'Daily') kv('Partial day', c.str('daily_partial_rule')),
                        kv('Fuel', c.str('fuel_policy').replaceAll('CompanySupplies', 'We supply, ').replaceAll('VendorSupplies', 'Vendor')),
                      ]),
                    ]),
                  );
                }),
            ]),
    );
  }

  // ------------------------------------------------------------- DNR prices (per unit, from delivery notes)
  Future<void> _dnrAction(Json r, String action) async {
    final id = r.intv('dnr_rate_id');
    if (action == 'close') {
      final d = await pickDate(context, initial: Fmt.today());
      if (d == null) return;
      _do(() => Api.I.patch('/equipment/dnr-rates/$id/close', {'effective_to': d}), 'DNR price ends on $d.');
    } else if (action == 'price') {
      final v = await promptText(context, 'Correct the unit price', label: 'Unit price', initial: r.str('unit_price'), maxLines: 1,
          help: 'Only while no delivery note uses it. Otherwise close it and add a new price from the next day.');
      final n = v == null ? null : num.tryParse(v.replaceAll(',', '.'));
      if (n == null) return;
      _do(() => Api.I.put('/equipment/dnr-rates/$id', {'unit_price': n}), 'Price corrected.');
    } else if (action == 'cancel') {
      final reason = await promptText(context, 'Cancel this DNR price?', label: 'Reason', minLength: 3, confirm: 'Cancel the price');
      if (reason == null) return;
      _do(() => Api.I.patch('/equipment/dnr-rates/$id/cancel', {'reason': reason}), 'DNR price cancelled.');
    }
  }

  Widget _dnrPrices(Json m) {
    final today = Fmt.today();
    final active = _dnr.where((r) => r.str('status') == 'Active').toList();
    return SectionCard(
      title: 'DNR prices (per unit)',
      trailing: Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => DeliveryNotesScreen.openForMachine(context, m).then((_) => _load()),
          icon: const Icon(Icons.receipt_rounded),
          label: const Text('Delivery notes'),
        ),
        FilledButton.tonalIcon(
          onPressed: () async {
            final ok = await RateCardFormScreen.open(context, machine: m, copyFrom: <String, dynamic>{'billing_mode': 'DNR', if (_cards.isNotEmpty) ...{
              'vendor_contract_id': _cards.first.intv('vendor_contract_id'), 'contract_number': _cards.first.str('contract_number'), 'currency': _cards.first.str('currency')}});
            if (ok == true) _load();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('New DNR price'),
        ),
      ]),
      child: active.isEmpty
          ? const EmptyView(
              text: 'No DNR price. Use it when the vendor is paid per trip, per ton or per load from delivery notes. '
                  'It can be added next to the time rate card: both are paid.',
              icon: Icons.local_shipping_rounded)
          : Column(children: [
              for (final r in active)
                Builder(builder: (context) {
                  final current = r.str('effective_from').compareTo(today) <= 0 && (r.strOrNull('effective_to') == null || r.str('effective_to').compareTo(today) >= 0);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: current ? AppColors.info : AppColors.line),
                      color: current ? AppColors.info.withValues(alpha: 0.04) : Colors.white,
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r.str('item_name')}  ·  ${Fmt.money2(r.strOrNull('unit_price'), r.str('currency'))} / ${dnrUnits[r.str('unit')]?.split(' ').first ?? r.str('unit')}',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
                          const SizedBox(height: 3),
                          Text(
                              '${Fmt.date(r.str('effective_from'))} → ${r.strOrNull('effective_to') == null ? 'open' : Fmt.date(r.str('effective_to'))}  ·  '
                              '${r.str('applies_to') == 'machine' ? 'this machine only' : 'every machine of the vendor'}  ·  contract ${r.str('contract_number')}  ·  '
                              '${r.intv('notes_count')} delivery note(s)',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ]),
                      ),
                      if (current) const Pill('Current', color: AppColors.info),
                      PopupMenuButton<String>(
                        onSelected: (v) => _dnrAction(r, v),
                        itemBuilder: (_) => [
                          if (r.intv('notes_count') == 0) const PopupMenuItem(value: 'price', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Correct the price'))),
                          const PopupMenuItem(value: 'close', child: ListTile(leading: Icon(Icons.event_busy_rounded), title: Text('Close on a date'))),
                          if (r.intv('notes_count') == 0) const PopupMenuItem(value: 'cancel', child: ListTile(leading: Icon(Icons.block_rounded), title: Text('Cancel'))),
                        ],
                      ),
                    ]),
                  );
                }),
            ]),
    );
  }

  // ------------------------------------------------------------- fuel price difference terms
  Future<void> _newFuelTerms(Json m) async {
    final last = m.list('fuel_terms').isEmpty ? null : m.list('fuel_terms').first;
    var from = Fmt.today();
    final base = TextEditingController(text: last?.str('base_price_per_liter') ?? '');
    final lph = TextEditingController(text: last?.str('liters_per_hour') ?? '');
    final note = TextEditingController();
    final r = await showFormDialog<Json>(
      context,
      title: last == null ? 'Fuel price difference for ${m.str('equipment_code')}' : 'New fuel terms from a date',
      width: 480,
      onSave: () async => asJson(await Api.I.post('/equipment/machines/${widget.id}/fuel-terms', {
        'effective_from': from, 'base_price_per_liter': numOrNull(base), 'liters_per_hour': numOrNull(lph), if (textOrNull(note) != null) 'note': textOrNull(note),
      })),
      body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          last == null
              ? 'The company pays the vendor the increase of the official fuel price: (official price - base price) x litres per hour x working hours (normal + overtime).'
              : 'The current terms are closed the day before. Old invoices keep the values they used.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        DateField(label: 'From', value: from, onChanged: (v) => set(() => from = v ?? from)),
        const SizedBox(height: 12),
        textField(base, 'Base fuel price per litre', number: true, required: true, hint: 'price agreed when the machine joined'),
        const SizedBox(height: 12),
        textField(lph, 'Consumption (litres per working hour)', number: true, required: true, suffix: 'L/h'),
        const SizedBox(height: 12),
        textField(note, 'Note'),
      ]),
    );
    if (r != null && mounted) {
      showSnack(context, 'Fuel terms saved.');
      _load();
    }
  }

  Future<void> _endFuelTerms(Json t) async {
    final d = await pickDate(context, initial: Fmt.today());
    if (d == null) return;
    _do(() => Api.I.patch('/equipment/fuel-terms/${t.intv('fuel_terms_id')}/end', {'effective_to': d}), 'Fuel difference stops after $d.');
  }

  /// The first day was entered wrong (e.g. today instead of the day the machine joined): reason required.
  /// Refused by the server when the days involved are inside a finalized payroll, or overlap earlier terms.
  Future<void> _changeFuelTermsStart(Json t) async {
    var date = t.str('effective_from');
    final reason = TextEditingController();
    final ok = await showFormDialog<bool>(
      context,
      title: 'Correct the first day of these fuel terms',
      saveLabel: 'Save',
      width: 440,
      onSave: () async {
        await Api.I.patch('/equipment/fuel-terms/${t.intv('fuel_terms_id')}/start', {'effective_from': date, 'reason': reason.text.trim()});
        return true;
      },
      body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Use this when the first day was entered wrong, e.g. while entering past months. Days already paid by a finalized payroll cannot move.',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        DateField(label: 'Real first day of the fuel difference', value: date, onChanged: (x) => set(() => date = x ?? date)),
        const SizedBox(height: 12),
        TextFormField(
          controller: reason,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Reason *', hintText: 'e.g. compensated since the machine joined'),
          validator: (v) => (v ?? '').trim().length < 5 ? 'Write at least 5 characters' : null,
        ),
      ]),
    );
    if (ok == true && mounted) {
      showSnack(context, 'First day corrected.');
      _load();
    }
  }

  Widget _fuelTerms(Json m) {
    final terms = m.list('fuel_terms');
    final today = Fmt.today();
    return SectionCard(
      title: 'Fuel price difference',
      trailing: _admin
          ? FilledButton.tonalIcon(
              onPressed: () => _newFuelTerms(m),
              icon: const Icon(Icons.local_gas_station_rounded),
              label: Text(terms.isEmpty ? 'Set up' : 'New terms'),
            )
          : null,
      child: terms.isEmpty
          ? const EmptyView(text: 'No fuel price difference for this machine.', icon: Icons.local_gas_station_rounded)
          : Column(children: [
              for (final t in terms)
                Builder(builder: (context) {
                  final active = t.str('effective_from').compareTo(today) <= 0 && (t.strOrNull('effective_to') == null || t.str('effective_to').compareTo(today) >= 0);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.local_gas_station_rounded, color: active ? AppColors.gold : AppColors.neutral),
                    title: Text('Base ${t.str('base_price_per_liter')} / L  ·  ${t.str('liters_per_hour')} L per hour', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${Fmt.date(t.str('effective_from'))} → ${t.strOrNull('effective_to') == null ? 'open' : Fmt.date(t.str('effective_to'))}'
                        '${t.strOrNull('note') == null ? '' : '  ·  ${t.str('note')}'}'),
                    trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (active) const Pill('Current', color: AppColors.gold),
                      if (_admin)
                        IconButton(tooltip: 'Correct the first day', icon: const Icon(Icons.edit_calendar_rounded), onPressed: () => _changeFuelTermsStart(t)),
                      if (_admin && t.strOrNull('effective_to') == null)
                        IconButton(tooltip: 'Stop from a date', icon: const Icon(Icons.event_busy_rounded), onPressed: () => _endFuelTerms(t)),
                    ]),
                  );
                }),
            ]),
    );
  }

  Widget _recent(Json m) {
    final rows = m.list('recent_attendance');
    return SectionCard(
      title: 'Last recorded days',
      child: rows.isEmpty
          ? const EmptyView(text: 'No attendance yet.', icon: Icons.event_note_rounded)
          : Column(children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: StatePill(r.str('day_status')),
                  title: Text('${Fmt.dayLabel(r.str('record_date'))}  ·  ${r.str('site_code')}'),
                  subtitle: Text(r.strOrNull('check_in_time') == null
                      ? '-'
                      : '${Fmt.time(r.str('check_in_time'))} - ${Fmt.timeOn(r.strOrNull('check_out_time'), r.str('record_date'))}  ·  ${Fmt.duration(r.intOrNull('working_minutes'))} work'),
                  trailing: Wrap(spacing: 6, children: [WorkflowPill(r.str('status')), PaperPill(r.str('paper_status'))]),
                ),
            ]),
    );
  }
}
