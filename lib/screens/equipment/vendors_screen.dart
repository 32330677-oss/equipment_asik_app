import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/file_versions.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';
import 'machines_screen.dart';

/// Contracting companies that rent machines to us.
class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});
  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  final _s = Loadable<List<Json>>();
  final _q = TextEditingController();
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/vendors', query: {'q': _q.text.trim(), 'status': _status});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _open(Json v) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => VendorDetailScreen(id: v.intv('vendor_id'))));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final active = rows.where((v) => v.str('status') == 'Active').length;
    final machines = rows.fold<int>(0, (s, v) => s + v.intv('machines'));
    final deployed = rows.fold<int>(0, (s, v) => s + v.intv('deployed_now'));
    return PageBody(onRefresh: _load, children: [
      PageHeader(title: 'Vendors', subtitle: 'Companies renting machines to us, their contracts and drivers', actions: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(labelText: 'Search name or code', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            onSubmitted: (_) => _load(),
          ),
        ),
        Dropdown<String?>(label: 'Status', value: _status, width: 130, items: const [
          DropdownMenuItem(value: null, child: Text('All')),
          DropdownMenuItem(value: 'Active', child: Text('Active')),
          DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
        ], onChanged: (v) { _status = v; _load(); }),
        if (Auth.I.isAdmin || Auth.I.isAccountant)
          FilledButton.icon(
            onPressed: () async {
              final v = await showVendorDialog(context);
              if (v != null && mounted) _open(v);
            },
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('New vendor'),
          ),
      ]),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(label: 'Active vendors', value: '$active', icon: Icons.business_rounded),
        KpiTile(label: 'Machines', value: '$machines', icon: Icons.precision_manufacturing_rounded, color: AppColors.info),
        KpiTile(label: 'On site today', value: '$deployed', icon: Icons.location_on_rounded, color: AppColors.working),
      ]),
      const SizedBox(height: 14),
      if (_s.loading && _s.data == null)
        const LoadingView()
      else if (_s.error != null)
        ErrorView(error: _s.error!, onRetry: _load)
      else if (rows.isEmpty)
        const Card(child: EmptyView(text: 'No vendor yet.', icon: Icons.business_rounded))
      else
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 700 ? 2 : 1;
          final w = (c.maxWidth - 12 * (cols - 1)) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final v in rows) SizedBox(width: w, child: _VendorCard(v: v, onTap: () => _open(v))),
          ]);
        }),
    ]);
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.v, required this.onTap});
  final Json v;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = v.str('status') != 'Active';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: inactive ? AppColors.line : AppColors.navy,
                child: Text(v.str('vendor_name').isEmpty ? '?' : v.str('vendor_name')[0].toUpperCase(),
                    style: TextStyle(color: inactive ? AppColors.muted : Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.str('vendor_name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${v.str('vendor_code')}${v.strOrNull('contact_person') == null ? '' : '  ·  ${v.str('contact_person')}'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              if (v.str('vendor_type') == 'Individual') const Padding(padding: EdgeInsets.only(right: 6), child: Pill('Individual', color: AppColors.info)),
              if (inactive) const Pill('Inactive', color: AppColors.neutral),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _stat('${v.intv('machines')}', 'machines'),
              _stat('${v.intv('deployed_now')}', 'on site', color: AppColors.working),
              _stat('${v.intv('active_contracts')}', 'contracts', color: v.intv('active_contracts') == 0 ? AppColors.breakdown : AppColors.info),
            ]),
            if (v.strOrNull('phone_number') != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.phone_rounded, size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(v.str('phone_number'), style: const TextStyle(fontSize: 12.5)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _stat(String n, String label, {Color color = AppColors.navy}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}

/// Create or edit a vendor. Returns the saved vendor.
Future<Json?> showVendorDialog(BuildContext context, {Json? vendor}) {
  final v = vendor;
  final name = TextEditingController(text: v?.str('vendor_name'));
  final contact = TextEditingController(text: v?.str('contact_person'));
  final phone = TextEditingController(text: v?.str('phone_number'));
  final email = TextEditingController(text: v?.str('email'));
  final address = TextEditingController(text: v?.str('address'));
  final tax = TextEditingController(text: v?.str('tax_number'));
  final nationalId = TextEditingController(text: v?.str('national_id'));
  final notes = TextEditingController(text: v?.str('notes'));
  // a person renting us a machine without a company is an Individual: identified by the ID card, not a tax number
  var type = v?.strOrNull('vendor_type') ?? 'Company';
  return showFormDialog<Json>(
    context,
    title: v == null ? 'New vendor' : 'Edit ${v.str('vendor_name')}',
    onSave: () async {
      final body = {
        'vendor_name': name.text.trim(), 'vendor_type': type, 'national_id': textOrNull(nationalId), 'contact_person': textOrNull(contact), 'phone_number': textOrNull(phone), 'email': textOrNull(email),
        'address': textOrNull(address), 'tax_number': textOrNull(tax), 'notes': textOrNull(notes),
      }..removeWhere((k, x) => x == null);
      return asJson(v == null ? await Api.I.post('/equipment/vendors', body) : await Api.I.put('/equipment/vendors/${v.intv('vendor_id')}', body));
    },
    body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Company', icon: Icon(Icons.business_rounded), label: Text('Company')),
          ButtonSegment(value: 'Individual', icon: Icon(Icons.person_rounded), label: Text('Individual')),
        ],
        selected: {type},
        onSelectionChanged: (x) => set(() => type = x.first),
      ),
      const SizedBox(height: 4),
      Text(type == 'Individual' ? 'One person renting us a machine, without a company: the ID number is printed on vouchers and invoices.' : 'A company: the tax number is printed on vouchers.',
          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      const SizedBox(height: 12),
      FormGrid(children: [
        textField(name, type == 'Individual' ? 'Full name' : 'Company name', required: true),
        if (type == 'Company') textField(contact, 'Contact person'),
        textField(phone, 'Phone'),
        textField(email, 'Email'),
        textField(address, 'Address'),
        if (type == 'Individual') textField(nationalId, 'National ID number') else textField(tax, 'Tax number'),
        textField(notes, 'Notes', maxLines: 2),
      ]),
    ]),
  );
}

// ================================================================ vendor detail
class VendorDetailScreen extends StatefulWidget {
  const VendorDetailScreen({super.key, required this.id});
  final int id;
  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  Json? _v;
  List<Json> _contracts = [];
  List<Json> _opening = [];
  Object? _error;

  /// Contracts: Admin only. Vendor details and machines: Admin and Accountant.
  bool get _admin => Auth.I.isAdmin;
  bool get _canEdit => Auth.I.isAdmin || Auth.I.isAccountant;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await Api.I.getObj('/equipment/vendors/${widget.id}');
      final c = await Api.I.getList('/equipment/vendors/${widget.id}/contracts');
      final o = _canEdit ? await Api.I.getList('/equipment/opening-balances', query: {'vendor_id': widget.id}) : <Json>[];
      if (mounted) setState(() { _v = v; _contracts = c; _opening = o; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggleStatus() async {
    final v = _v!;
    final next = v.str('status') == 'Active' ? 'Inactive' : 'Active';
    final reason = await promptText(context, 'Set ${v.str('vendor_name')} $next', label: 'Reason', required: false, confirm: next == 'Active' ? 'Activate' : 'Deactivate');
    if (reason == null) return;
    try {
      await Api.I.patch('/equipment/vendors/${widget.id}/status', {'status': next, 'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _contract({Json? c}) async {
    final number = TextEditingController(text: c?.str('contract_number'));
    var start = c?.strOrNull('start_date') ?? Fmt.today();
    var end = c?.strOrNull('end_date');
    var currency = c?.str('currency') ?? 'USD';
    var status = c?.str('status') ?? 'Active';
    final terms = TextEditingController(text: c?.str('payment_terms'));
    final notes = TextEditingController(text: c?.str('notes'));
    final r = await showFormDialog<Json>(
      context,
      title: c == null ? 'New contract' : 'Edit contract ${c.str('contract_number')}',
      onSave: () async {
        final body = {
          'contract_number': number.text.trim(), 'start_date': start, 'end_date': end, 'currency': currency, 'status': status,
          'payment_terms': textOrNull(terms), 'notes': textOrNull(notes),
        }..removeWhere((k, x) => x == null);
        return asJson(c == null
            ? await Api.I.post('/equipment/vendors/${widget.id}/contracts', body)
            : await Api.I.put('/equipment/contracts/${c.intv('vendor_contract_id')}', body));
      },
      body: (ctx, set) => FormGrid(children: [
        textField(number, 'Contract number', required: true),
        Dropdown<String>(label: 'Currency', value: currency, width: null, items: [
          for (final cur in {'USD', 'SYP', 'EUR', currency}) DropdownMenuItem(value: cur, child: Text(cur)),
        ], onChanged: (x) => set(() => currency = x ?? currency)),
        DateField(label: 'Start *', value: start, onChanged: (x) => set(() => start = x ?? start)),
        DateField(label: 'End (open)', value: end, clearable: true, onChanged: (x) => set(() => end = x)),
        Dropdown<String>(label: 'Status', value: status, width: null, items: const [
          DropdownMenuItem(value: 'Draft', child: Text('Draft')),
          DropdownMenuItem(value: 'Active', child: Text('Active')),
          DropdownMenuItem(value: 'Expired', child: Text('Expired')),
          DropdownMenuItem(value: 'Terminated', child: Text('Terminated')),
        ], onChanged: (x) => set(() => status = x ?? status)),
        textField(terms, 'Payment terms', hint: 'e.g. 30 days after statement'),
        textField(notes, 'Notes', maxLines: 2),
      ]),
    );
    if (r != null && mounted) {
      showSnack(context, 'Contract saved.');
      if (c == null) {
        final up = await confirmDialog(context, 'Attach the signed contract?', 'Upload the scanned contract (PDF or photo).', confirm: 'Upload');
        if (up) await _uploadDoc(r);
      }
      _load();
    }
  }

  Future<void> _uploadDoc(Json c) async {
    final ok = await uploadFileVersion(context, basePath: '/equipment/contracts/${c.intv('vendor_contract_id')}/document', hasFile: c.flag('has_document'), label: 'Contract');
    if (ok) _load();
  }

  Future<void> _statement() async {
    final now = Fmt.now();
    final from = await pickDate(context, initial: Fmt.dateOf(DateTime(now.year, now.month, 1)));
    if (from == null || !mounted) return;
    final to = await pickDate(context, initial: Fmt.today());
    if (to == null || !mounted) return;
    PdfViewScreen.open(context,
        title: 'Statement ${_v!.str('vendor_name')}',
        fileName: 'statement-${_v!.str('vendor_code')}-$from-$to.pdf',
        load: () => Api.I.getBytes('/equipment/statements/vendor/${widget.id}.pdf', query: {'from': from, 'to': to}));
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Scaffold(
      appBar: AppBar(
        title: Text(v == null ? 'Vendor' : v.str('vendor_name')),
        actions: [
          if (v != null) ...[
            TextButton.icon(onPressed: _statement, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Statement')),
            if (_canEdit)
              PopupMenuButton<String>(
                onSelected: (x) async {
                  if (x == 'edit') {
                    final r = await showVendorDialog(context, vendor: v);
                    if (r != null) _load();
                  }
                  if (x == 'status') _toggleStatus();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit details'))),
                  PopupMenuItem(
                    value: 'status',
                    child: ListTile(
                      leading: Icon(v.str('status') == 'Active' ? Icons.block_rounded : Icons.check_circle_rounded),
                      title: Text(v.str('status') == 'Active' ? 'Deactivate' : 'Activate'),
                    ),
                  ),
                ],
              ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : v == null
              ? const LoadingView()
              : PageBody(onRefresh: _load, maxWidth: 1200, children: [
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(spacing: 30, runSpacing: 12, children: [
                        SizedBox(
                          width: 360,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(v.str('vendor_name'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy))),
                              const SizedBox(width: 10),
                              Pill(v.str('status'), color: v.str('status') == 'Active' ? AppColors.working : AppColors.neutral),
                            ]),
                            Text(v.str('vendor_code'), style: const TextStyle(color: AppColors.muted)),
                          ]),
                        ),
                        SizedBox(
                          width: 420,
                          child: Column(children: [
                            InfoRow('Contact', v.str('contact_person'), width: 110),
                            InfoRow('Phone', v.str('phone_number'), width: 110),
                            InfoRow('Email', v.str('email'), width: 110),
                            InfoRow('Address', v.str('address'), width: 110),
                            InfoRow('Type', v.str('vendor_type') == 'Individual' ? 'Individual (person)' : 'Company', width: 110),
                            if (v.str('vendor_type') == 'Individual')
                              InfoRow('National ID', v.str('national_id'), width: 110)
                            else
                              InfoRow('Tax number', v.str('tax_number'), width: 110),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _contractsCard(),
                  const SizedBox(height: 14),
                  if (_canEdit) ...[_openingCard(), const SizedBox(height: 14)],
                  _machinesCard(v),
                ]),
    );
  }

  Widget _contractsCard() {
    Color statusColor(String s) => s == 'Active' ? AppColors.working : s == 'Draft' ? AppColors.info : AppColors.neutral;
    return SectionCard(
      title: 'Contracts',
      trailing: _admin ? FilledButton.tonalIcon(onPressed: () => _contract(), icon: const Icon(Icons.note_add_rounded), label: const Text('New contract')) : null,
      child: _contracts.isEmpty
          ? const EmptyView(text: 'No contract: add one before creating rate cards.', icon: Icons.description_rounded)
          : Column(children: [
              for (final c in _contracts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: statusColor(c.str('status')).withValues(alpha: 0.12), child: Icon(Icons.description_rounded, color: statusColor(c.str('status')))),
                  title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(c.str('contract_number'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Pill(c.str('status'), color: statusColor(c.str('status'))),
                    Pill(c.str('currency'), color: AppColors.navy),
                  ]),
                  subtitle: Text('${Fmt.date(c.str('start_date'))} → ${c.strOrNull('end_date') == null ? 'open' : Fmt.date(c.str('end_date'))}'
                      '  ·  ${c.intv('rate_cards')} rate card(s)${c.strOrNull('payment_terms') == null ? '' : '  ·  ${c.str('payment_terms')}'}'),
                  trailing: Wrap(spacing: 4, children: [
                    if (c.flag('has_document'))
                      IconButton(
                        tooltip: 'Contract document (all versions)',
                        icon: const Icon(Icons.attach_file_rounded, color: AppColors.navy),
                        onPressed: () async {
                          final changed = await showFileVersions(context,
                              title: 'Contract ${c.str('contract_number')}',
                              basePath: '/equipment/contracts/${c.intv('vendor_contract_id')}/document',
                              listPath: '/equipment/contracts/${c.intv('vendor_contract_id')}/documents',
                              fileName: 'contract-${c.str('contract_number')}',
                              canUpload: _admin);
                          if (changed) _load();
                        },
                      ),
                    if (_admin)
                      PopupMenuButton<String>(
                        onSelected: (x) {
                          if (x == 'edit') _contract(c: c);
                          if (x == 'doc') _uploadDoc(c);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'))),
                          PopupMenuItem(value: 'doc', child: ListTile(leading: const Icon(Icons.upload_file_rounded), title: Text(c.flag('has_document') ? 'Replace document' : 'Upload document'))),
                        ],
                      ),
                  ]),
                ),
            ]),
    );
  }

  // ------------------------------------------------------------- opening balances (money owed from before the system)
  Future<void> _openingBalance({Json? o}) async {
    final currencies = {for (final c in _contracts) c.str('currency')}.toList();
    if (currencies.isEmpty) {
      showSnack(context, 'Add a contract first: it gives the currency.', error: true);
      return;
    }
    final machines = _v!.list('machines');
    final amount = TextEditingController(text: o?.str('amount'));
    final description = TextEditingController(text: o?.str('description'));
    final reference = TextEditingController(text: o?.str('reference'));
    final note = TextEditingController(text: o?.str('note'));
    var currency = o?.str('currency') ?? currencies.first;
    var asOf = o?.strOrNull('as_of_date') ?? Fmt.today();
    var from = o?.strOrNull('period_from');
    var to = o?.strOrNull('period_to');
    int? machine = o?.intv('equipment_id') == 0 ? null : o?.intv('equipment_id');
    final r = await showFormDialog<Json>(
      context,
      title: o == null ? 'Opening balance - ${_v!.str('vendor_name')}' : 'Edit opening balance',
      width: 600,
      onSave: () async {
        final n = numOrNull(amount);
        if (n == null || n <= 0) throw ApiException(null, 'VALIDATION', 'Type the amount still owed.');
        final body = <String, dynamic>{
          'amount': n, 'currency': currency, 'as_of_date': asOf, 'period_from': from, 'period_to': to, 'equipment_id': machine,
          'description': description.text.trim(), 'reference': textOrNull(reference), 'note': textOrNull(note),
        };
        return asJson(o == null
            ? await Api.I.post('/equipment/vendors/${widget.id}/opening-balances', body..removeWhere((k, x) => x == null))
            : await Api.I.put('/equipment/opening-balances/${o.intv('opening_balance_id')}', body));
      },
      body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Money still owed to this vendor from BEFORE the system (after the payments already made). '
            'Tick "Add previous balances" on the next New payroll: it is added on its own line, paid with normal payment vouchers, '
            'and the invoice of the new period is not changed.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        FormGrid(children: [
          textField(amount, 'Amount still owed', number: true, required: true),
          Dropdown<String>(label: 'Currency', value: currency, width: null, items: [
            for (final c in currencies) DropdownMenuItem(value: c, child: Text(c)),
          ], onChanged: (x) => set(() => currency = x ?? currency)),
          DateField(label: 'Balance date *', value: asOf, onChanged: (x) => set(() => asOf = x ?? asOf)),
          Dropdown<int?>(label: 'Machine (optional)', value: machine, width: null, items: [
            const DropdownMenuItem(value: null, child: Text('Whole vendor')),
            for (final m in machines) DropdownMenuItem(value: m.intv('equipment_id'), child: Text('${m.str('equipment_code')}  ${m.machineType}')),
          ], onChanged: (x) => set(() => machine = x)),
          DateField(label: 'Old period from', value: from, clearable: true, onChanged: (x) => set(() => from = x)),
          DateField(label: 'Old period to', value: to, clearable: true, onChanged: (x) => set(() => to = x)),
        ]),
        const SizedBox(height: 12),
        textField(description, 'Description (printed on the statement)', required: true, hint: 'e.g. Rent June - September 2026 not paid'),
        const SizedBox(height: 12),
        FormGrid(children: [
          textField(reference, 'Old invoice / statement no.'),
          textField(note, 'Note'),
        ]),
      ]),
    );
    if (r != null && mounted) {
      showSnack(context, 'Opening balance saved.');
      _load();
    }
  }

  Future<void> _cancelOpening(Json o) async {
    final reason = await promptText(context, 'Cancel opening balance', label: 'Why? (kept in the history)', minLength: 5, confirm: 'Cancel it');
    if (reason == null) return;
    try {
      await Api.I.patch('/equipment/opening-balances/${o.intv('opening_balance_id')}/cancel', {'reason': reason});
      if (mounted) showSnack(context, 'Opening balance cancelled.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _openingCard() {
    Color stateColor(String s) => s == 'Open' ? AppColors.breakdown : s == 'Carried' ? AppColors.working : AppColors.neutral;
    String stateText(Json o) => switch (o.str('state')) {
          'Open' => 'Waiting for the next payroll',
          'Carried' => 'In batch #${o.str('carried_to_batch_id')} (${o.str('carried_to_batch_state')})',
          _ => 'Cancelled',
        };
    final open = <String, double>{};
    for (final o in _opening.where((o) => o.str('state') == 'Open')) {
      open[o.str('currency')] = (open[o.str('currency')] ?? 0) + o.dbl('amount');
    }
    return SectionCard(
      title: 'Opening balances (before the system)',
      trailing: FilledButton.tonalIcon(onPressed: () => _openingBalance(), icon: const Icon(Icons.account_balance_wallet_rounded), label: const Text('Add opening balance')),
      child: _opening.isEmpty
          ? const EmptyView(text: 'Nothing owed from before the system.', icon: Icons.account_balance_wallet_rounded)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (open.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NoticeBox(
                    color: AppColors.edited,
                    icon: Icons.info_outline_rounded,
                    text: 'Still to carry: ${open.entries.map((e) => Fmt.money(e.value, e.key)).join(' + ')}. '
                        'Tick "Add previous balances" on the next New payroll of this vendor.',
                  ),
                ),
              for (final o in _opening)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: stateColor(o.str('state')).withValues(alpha: 0.12), child: Icon(Icons.history_rounded, color: stateColor(o.str('state')))),
                  title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(Fmt.money2(o.strOrNull('amount'), o.str('currency')), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Pill(stateText(o), color: stateColor(o.str('state'))),
                    if (o.strOrNull('equipment_code') != null) Pill(o.str('equipment_code'), color: AppColors.navy),
                  ]),
                  subtitle: Text('${o.str('description')}  ·  balance on ${Fmt.date(o.str('as_of_date'))}'
                      '${o.strOrNull('period_from') == null ? '' : '  ·  period ${Fmt.date(o.str('period_from'))} - ${Fmt.date(o.str('period_to'))}'}'
                      '${o.strOrNull('reference') == null ? '' : '  ·  ${o.str('reference')}'}'
                      '${o.str('state') == 'Cancelled' ? '  ·  cancelled: ${o.str('cancel_reason')}' : ''}'),
                  trailing: o.str('state') == 'Open'
                      ? PopupMenuButton<String>(
                          onSelected: (x) {
                            if (x == 'edit') _openingBalance(o: o);
                            if (x == 'cancel') _cancelOpening(o);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'))),
                            PopupMenuItem(value: 'cancel', child: ListTile(leading: Icon(Icons.block_rounded), title: Text('Cancel'))),
                          ],
                        )
                      : null,
                ),
            ]),
    );
  }

  Widget _machinesCard(Json v) {
    final machines = v.list('machines');
    return SectionCard(
      title: 'Machines (${machines.length})',
      trailing: _canEdit && v.str('status') == 'Active'
          ? FilledButton.tonalIcon(
              onPressed: () async {
                final m = await showMachineDialog(context, vendor: PickOption(widget.id, v.str('vendor_name')));
                if (m == null || !mounted) return;
                await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MachineDetailScreen(id: m.intv('equipment_id'))));
                _load();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add machine'),
            )
          : null,
      child: machines.isEmpty
          ? const EmptyView(text: 'No machine.', icon: Icons.precision_manufacturing_rounded)
          : Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in machines)
                ActionChip(
                  avatar: Icon(Icons.precision_manufacturing_rounded, size: 18, color: machineStatusColor(m.str('status'))),
                  label: Text('${m.str('equipment_code')}  ${m.machineType}${m.strOrNull('plate_number') == null ? '' : '  ·  ${m.str('plate_number')}'}'),
                  onPressed: () async {
                    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MachineDetailScreen(id: m.intv('equipment_id'))));
                    _load();
                  },
                ),
            ]),
    );
  }
}
