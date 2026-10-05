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
  final notes = TextEditingController(text: v?.str('notes'));
  return showFormDialog<Json>(
    context,
    title: v == null ? 'New vendor' : 'Edit ${v.str('vendor_name')}',
    onSave: () async {
      final body = {
        'vendor_name': name.text.trim(), 'contact_person': textOrNull(contact), 'phone_number': textOrNull(phone), 'email': textOrNull(email),
        'address': textOrNull(address), 'tax_number': textOrNull(tax), 'notes': textOrNull(notes),
      }..removeWhere((k, x) => x == null);
      return asJson(v == null ? await Api.I.post('/equipment/vendors', body) : await Api.I.put('/equipment/vendors/${v.intv('vendor_id')}', body));
    },
    body: (ctx, set) => FormGrid(children: [
      textField(name, 'Company name', required: true),
      textField(contact, 'Contact person'),
      textField(phone, 'Phone'),
      textField(email, 'Email'),
      textField(address, 'Address'),
      textField(tax, 'Tax number'),
      textField(notes, 'Notes', maxLines: 2),
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
      if (mounted) setState(() { _v = v; _contracts = c; _error = null; });
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
    final now = DateTime.now();
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
                            InfoRow('Tax number', v.str('tax_number'), width: 110),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _contractsCard(),
                  const SizedBox(height: 14),
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
                  label: Text('${m.str('equipment_code')}  ${m.str('type_name')}${m.strOrNull('plate_number') == null ? '' : '  ·  ${m.str('plate_number')}'}'),
                  onPressed: () async {
                    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MachineDetailScreen(id: m.intv('equipment_id'))));
                    _load();
                  },
                ),
            ]),
    );
  }
}
