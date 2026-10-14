import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/file_save.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_content.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';
import 'attendance_review_screen.dart' show AttendanceDetailSheet;
import 'invoice_finance.dart';

// Invoices (decisions of 13-14 Oct 2026). The app records attendance and issues invoices per vendor and machine, for
// any period; it records no payment. An invoice is a Draft (no number, reserves its period), then Issued (VI / MI
// numbers, kept up to date with the same numbers while in the office), then Handed over to finance (locked). The Admin
// may withdraw it from finance (signed acknowledgement) and re-issue it with a new number, or cancel it.

/// Shown with the blockers but never stop the generation.
const _infoOnly = {'IN_OTHER_BATCH', 'SCAN_MISSING', 'MONTHLY_DAYS_WITHOUT_ROWS'};

/// Information only (never blocks)? The server says it per blocker ('blocking'); older servers fall back to the list.
bool _isInfo(Json b) => b.containsKey('blocking') ? !b.flag('blocking') : _infoOnly.contains(b.str('code'));

const _blockerHelp = {
  'NOT_APPROVED': 'Approve or reject them here (Admin), or open a row to fix it.',
  'OPEN_SESSION': 'The supervisor must check the machine out (or open the row and fix the times).',
  'UNACK_ANOMALY': 'Open the row and acknowledge the anomaly.',
  'PAPER_NOT_MATCHED': 'Upload the signed sheet and reconcile it in Paper sheets.',
  'NO_RATE_CARD': 'Add a rate card (or a DNR price for per-unit work) for these dates on the machine page.',
  'FUEL_UNPRICED': 'Enter the price per litre in Fuel & adjustments.',
  'STANDBY_HOURS_NOT_SET': 'Monthly machine standby: open the row and set the standby hours to pay.',
  'IN_OTHER_BATCH': 'Already in another invoice; they are skipped. Each day is invoiced once.',
  'FUEL_PRICE_MISSING': 'Add the official fuel price for these dates in Fuel & adjustments > Fuel prices.',
  'SCAN_MISSING': 'Information only: upload these signed sheets (Paper sheets) before the invoice is handed over to finance.',
  'MONTHLY_DAYS_WITHOUT_ROWS': 'Each of these days is deducted as a full absence; extra hours of other days cover it only if the Admin decides so. '
      'If the machine worked, the supervisor must record the day; if it did not, record it as Absent, Standby, Breakdown or Holiday. '
      'Or create the draft anyway with a reason.',
};

/// Accepting blockers is a decision kept on the invoice: ask why (at least 5 characters).
Future<String?> askAcceptReason(BuildContext context) => promptText(context, 'Why create the invoice with open problems?',
    label: 'Reason (kept on the invoice and shown to whoever issues it)',
    minLength: 5,
    confirm: 'Create anyway',
    help: 'Rows with problems are left out of this invoice; they can be invoiced later. '
        'Monthly days without a row are deducted as a full absence.');

/// Human labels of the manual changes an invoice pays (shown before it is issued).
const _reviewKinds = {
  'edited_after_approval': 'Row edited after approval',
  'late_entry': 'Late entry',
  'standby_hours': 'Standby hours decided',
  'adjustment': 'Manual adjustment',
  'fuel_changed': 'Fuel issue changed',
  'rate_card_changed': 'Rate card changed',
  'delivery_note_changed': 'Delivery note changed',
  'accepted_blockers': 'Created with open problems',
  'monthly_exception': 'Exception typed for the month (monthly machine)',
  'monthly_offset': 'Extra hours used to cover missing hours (Admin decision)',
  'monthly_offset_not_used': 'Extra hours NOT used to cover missing hours',
};

bool get _office => Auth.I.isAdmin || Auth.I.isAccountant;

Future<void> _openInvoice(BuildContext context, int id) => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => BatchScreen(id: id)));

Future<void> _openNote(BuildContext context, int id) => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => NoteScreen(id: id)));

/// "already in VI-2026-00012 (issued) 2026-10-01 to 2026-10-15" for one conflict of the overlap check.
String _conflictText(Json c) => '${c.strOrNull('invoice_no') ?? 'draft #${c.str('eq_batch_id')}'} '
    '(${(invoiceStateLabels[c.str('state')] ?? c.str('state')).toLowerCase()})  ${Fmt.date(c.str('start_date'))} – ${Fmt.date(c.str('end_date'))}'
    '${c.strOrNull('site_code') == null ? '' : '  at ${c.str('site_code')}'}';

/// The period asked overlaps invoices of the same machines: which ones (with a link) and what is still free.
Future<void> showOverlapDialog(BuildContext context, List<Json> overlaps, {void Function(String from, String to)? onUse}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('There is already an invoice in this period'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('A machine is never in two invoices on the same day. Choose a free period, or open the invoice that already covers it.',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            for (final m in overlaps) ...[
              const SizedBox(height: 12),
              Text(m.str('label', m.str('equipment_code')), style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final c in m.list('conflicts'))
                Row(children: [
                  Icon(invoiceStateIcon(c.str('state')), size: 18, color: invoiceStateColor(c.str('state'))),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_conflictText(c), style: const TextStyle(fontSize: 13))),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openInvoice(context, c.intv('eq_batch_id'));
                    },
                    child: const Text('Open'),
                  ),
                ]),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Free:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                if (m.list('free').isEmpty) const Text('nothing in this period', style: TextStyle(fontSize: 13)),
                for (final f in m.list('free'))
                  onUse == null
                      ? Pill('${Fmt.date(f.str('from'))} – ${Fmt.date(f.str('to'))}', color: AppColors.working)
                      : ActionChip(
                          avatar: const Icon(Icons.event_available_rounded, size: 16, color: AppColors.working),
                          label: Text('${Fmt.date(f.str('from'))} – ${Fmt.date(f.str('to'))}'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            onUse!(f.str('from'), f.str('to'));
                          },
                        ),
              ]),
            ],
          ]),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

// =================================================================== register
/// Invoice register: per vendor, its invoices (newest period first) with their machine invoices and the debit / credit
/// notes that belong to each, then the vendor's general notes. Filters find an old invoice quickly.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final _s = Loadable<List<Json>>();
  String _state = '';
  PickOption? _vendor;
  PickOption? _machine;
  String? _from;
  String? _to;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/payroll/register', query: {
        if (_state.isNotEmpty) 'state': _state,
        if (_vendor != null) 'vendor_id': _vendor!.value,
        if (_machine != null) 'equipment_id': _machine!.value,
        if (_from != null) 'from': _from,
        if (_to != null) 'to': _to,
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
      });
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _new() async {
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const NewPayrollScreen()));
    await _load();
    if (id != null && mounted) {
      await _openInvoice(context, id);
      _load();
    }
  }

  Future<void> _newNote() async {
    final n = await editNote(context, vendorId: _vendor?.value as int?, vendorName: _vendor?.label);
    if (n == null || !mounted) return;
    await _openNote(context, n.intv('note_id'));
    _load();
  }

  Future<void> _open(int id) async {
    await _openInvoice(context, id);
    _load();
  }

  Future<void> _openN(int id) async {
    await _openNote(context, id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _s.data ?? <Json>[];
    final all = [for (final g in groups) ...g.list('invoices')];
    int count(String st) => all.where((i) => i.str('state') == st).length;
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Invoices', subtitle: 'Per vendor and machine, for any period, from approved attendance', actions: [
          if (Auth.I.isAdmin)
            TextButton.icon(
              onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const HandoversScreen())),
              icon: const Icon(Icons.history_edu_rounded),
              label: const Text('Hand-over sheets'),
            ),
          if (Auth.I.isAdmin)
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const HandoverScreen()));
                _load();
              },
              icon: const Icon(Icons.outbox_rounded),
              label: const Text('Hand over to finance'),
            ),
          if (_office) OutlinedButton.icon(onPressed: _newNote, icon: const Icon(Icons.post_add_rounded), label: const Text('New debit / credit note')),
          if (_office) FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('New invoice')),
        ]),
        SectionCard(
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PickerField(label: 'Vendor (all)', width: 230, icon: Icons.business_rounded, valueLabel: _vendor?.label, load: () => Lookups.vendors(),
                onChanged: (v) { setState(() { _vendor = v; _machine = null; }); _load(); }),
            PickerField(label: 'Machine (all)', width: 230, icon: Icons.precision_manufacturing_rounded, valueLabel: _machine?.label,
                load: () => Lookups.machines(vendorId: _vendor?.value as int?), onChanged: (v) { setState(() => _machine = v); _load(); }),
            DateField(label: 'From', value: _from, width: 165, clearable: true, onChanged: (v) { setState(() => _from = v); _load(); }),
            DateField(label: 'To', value: _to, width: 165, clearable: true, onChanged: (v) { setState(() => _to = v); _load(); }),
            Dropdown<String>(label: 'State', value: _state, width: 190, items: const [
              DropdownMenuItem(value: '', child: Text('All')),
              DropdownMenuItem(value: 'Active', child: Text('Valid (not cancelled)')),
              DropdownMenuItem(value: 'Draft', child: Text('Draft')),
              DropdownMenuItem(value: 'Issued', child: Text('Issued (in the office)')),
              DropdownMenuItem(value: 'HandedOver', child: Text('Handed over')),
              DropdownMenuItem(value: 'Returned', child: Text('Withdrawn from finance')),
              DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
              DropdownMenuItem(value: 'Replaced', child: Text('Re-issued (old number)')),
            ], onChanged: (v) { setState(() => _state = v ?? ''); _load(); }),
            SizedBox(
              width: 230,
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  labelText: 'Search: number or machine',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded, size: 18), onPressed: _load),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'Drafts', value: '${count('draft')}', color: AppColors.standby, icon: Icons.edit_note_rounded),
          KpiTile(label: 'Issued, in the office', value: '${count('issued')}', color: AppColors.info, icon: Icons.receipt_long_rounded, width: 200),
          KpiTile(label: 'Handed over', value: '${count('handed_over')}', color: AppColors.working, icon: Icons.lock_rounded),
          if (count('returned') > 0) KpiTile(label: 'Withdrawn from finance', value: '${count('returned')}', color: AppColors.edited, icon: Icons.undo_rounded, width: 220),
        ]),
        const SizedBox(height: 14),
        if (_s.loading && _s.data == null)
          const LoadingView()
        else if (_s.error != null)
          ErrorView(error: _s.error!, onRetry: _load)
        else if (groups.isEmpty)
          const Card(child: EmptyView(text: 'No invoice here. Use "New invoice" to create one, or change the filters.', icon: Icons.receipt_long_rounded))
        else
          for (final g in groups) _vendorCard(g, expanded: groups.length <= 3 || _vendor != null),
      ],
    );
  }

  Widget _vendorCard(Json g, {required bool expanded}) {
    final invoices = g.list('invoices');
    final general = g.list('general_notes');
    final notes = invoices.fold<int>(0, (a, i) => a + i.list('notes').length) + general.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('vendor-${g.str('vendor_id')}'),
          initiallyExpanded: expanded,
          leading: const Icon(Icons.business_rounded, color: AppColors.navy),
          title: Text(g.str('vendor_name'), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${invoices.length} invoice(s)${notes == 0 ? '' : '  ·  $notes note(s)'}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          children: [
            for (final inv in invoices) _invoiceRow(inv),
            if (general.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text('Notes not linked to an invoice', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              for (final n in general) _noteRow(n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _invoiceRow(Json inv) {
    final st = inv.str('state');
    final cur = inv.str('currency');
    final dead = st == 'cancelled' || st == 'replaced';
    final mis = inv.list('machine_invoices');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          onTap: () => _open(inv.intv('eq_batch_id')),
          leading: Icon(invoiceStateIcon(st), color: invoiceStateColor(st)),
          title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(inv.strOrNull('vendor_invoice_no') ?? 'Draft #${inv.str('eq_batch_id')}',
                style: TextStyle(fontWeight: FontWeight.w800, decoration: dead ? TextDecoration.lineThrough : null)),
            invoiceStatePill(st),
            Text('${Fmt.date(inv.str('start_date'))} – ${Fmt.date(inv.str('end_date'))}', style: const TextStyle(fontSize: 13)),
          ]),
          subtitle: Text([
            '${inv.str('machines')} machine(s)',
            if (mis.isNotEmpty) mis.map((m) => '${m.str('invoice_no')} ${m.str('equipment_code')}').join(', '),
            if (inv.strOrNull('handover_no') != null) '${inv.str('handover_no')} on ${Fmt.date(inv.str('handed_on'))}',
          ].join('  ·  '), style: const TextStyle(fontSize: 12.5)),
          trailing: Text(Fmt.money2(inv.strOrNull('net'), cur),
              style: TextStyle(fontWeight: FontWeight.w800, color: dead ? AppColors.muted : AppColors.navy)),
        ),
        for (final n in inv.list('notes')) Padding(padding: const EdgeInsets.only(left: 40), child: _noteRow(n)),
      ]),
    );
  }

  Widget _noteRow(Json n) {
    final st = noteState(n.str('status'));
    return ListTile(
      dense: true,
      onTap: () => _openN(n.intv('note_id')),
      leading: Icon(n.str('kind') == 'Credit' ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, color: AppColors.gold),
      title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(n.str('note_no', 'Draft note'),
            style: TextStyle(fontWeight: FontWeight.w700, decoration: st == 'cancelled' ? TextDecoration.lineThrough : null)),
        invoiceStatePill(st),
        Text('${noteKindText(n.str('kind'))}${n.strOrNull('equipment_code') == null ? '' : '  ·  ${n.str('equipment_code')}'}', style: const TextStyle(fontSize: 12.5)),
      ]),
      subtitle: Text(n.str('reason'), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(noteAmountText(n), style: TextStyle(fontWeight: FontWeight.w700, color: n.str('kind') == 'Credit' ? AppColors.breakdown : AppColors.working)),
    );
  }
}

String _scopeText(Json b) {
  final chosen = b.list('scope_machines');
  final count = chosen.isNotEmpty ? chosen.length : b.intv('scope_machine_count');
  final parts = <String>[
    if (b.strOrNull('scope_vendor_name') != null) b.str('scope_vendor_name'),
    if (b.strOrNull('scope_equipment_code') != null) b.str('scope_equipment_code'),
    if (chosen.isNotEmpty) chosen.map((m) => m.str('equipment_code')).join(', ') else if (count > 0) '$count machines',
    if (b.strOrNull('scope_site_code') != null) b.str('scope_site_code'),
  ];
  return parts.isEmpty ? 'All vendors' : parts.join(' · ');
}

// =================================================================== new invoice
class NewPayrollScreen extends StatefulWidget {
  const NewPayrollScreen({super.key});
  @override
  State<NewPayrollScreen> createState() => _NewPayrollScreenState();
}

class _NewPayrollScreenState extends State<NewPayrollScreen> {
  late String _from;
  late String _to;
  PickOption? _vendor;
  PickOption? _site;
  String? _currency;

  bool _busy = false;
  List<Json>? _blockers;
  Json? _preview;
  Object? _previewError;

  // machines of the vendor: what an invoice would take now, and the invoices already covering part of the period
  List<Json>? _coverage;
  bool _coverageLoading = false;
  final Set<int> _selected = {};
  /// machines taken out of another DRAFT ("Take it"): that draft is deleted or recalculated without them
  final Set<int> _take = {};

  // terms of the month of the monthly machines chosen
  List<Json>? _terms;

  /// Admin decision on the preview: monthly machines and months whose extra hours cover their missing hours
  final Set<String> _offsets = {};
  bool _termsLoading = false;

  @override
  void initState() {
    super.initState();
    final now = Fmt.now();
    _from = Fmt.dateOf(DateTime(now.year, now.month - 1, 1));
    _to = Fmt.dateOf(DateTime(now.year, now.month, 0));
  }

  /// Every machine of the vendor chosen: the invoice is the whole vendor (no list); otherwise the machines chosen by hand.
  List<int>? get _machineList {
    final cov = _coverage;
    if (_vendor == null || cov == null) return null;
    if (cov.isNotEmpty && cov.every((c) => _selected.contains(c.intv('equipment_id')))) return null;
    return (_selected.toList()..sort());
  }

  Map<String, dynamic> get _scope => {
        'start_date': _from,
        'end_date': _to,
        if (_vendor != null) 'vendor_id': _vendor!.value,
        if (_machineList != null) 'equipment_ids': _machineList,
        if (_site != null) 'site_id': _site!.value,
        if (_currency != null) 'currency': _currency,
        if (_take.isNotEmpty) 'take_from_drafts': true,
        if (_offsets.isNotEmpty) 'offsets': _offsets.toList()..sort(),
      };

  /// GET routes take the machines as "1,2,3".
  Map<String, dynamic> get _query => {
        ..._scope..remove('take_from_drafts')..remove('offsets'),
        if (_machineList != null) 'equipment_ids': _machineList!.join(','),
      };

  void _changed(VoidCallback fn, {bool reloadMachines = false}) {
    setState(() {
      fn();
      _acceptReason = null;
      _blockers = null;
      _preview = null;
      _previewError = null;
    });
    if (reloadMachines) _loadCoverage();
  }

  void _usePeriod(String from, String to) => _changed(() { _from = from; _to = to; }, reloadMachines: true);

  Future<void> _loadCoverage() async {
    if (_vendor == null) {
      setState(() { _coverage = null; _selected.clear(); _take.clear(); _terms = null; });
      return;
    }
    setState(() => _coverageLoading = true);
    try {
      final rows = await Api.I.getList('/equipment/payroll/coverage',
          query: {'vendor_id': _vendor!.value, 'start_date': _from, 'end_date': _to, if (_site != null) 'site_id': _site!.value});
      if (!mounted) return;
      setState(() {
        _coverage = rows;
        _take.clear();
        _selected
          ..clear()
          ..addAll(rows.where((c) => c.flag('is_ready')).map((c) => c.intv('equipment_id')));
      });
      await _loadTerms();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _coverageLoading = false);
    }
  }

  /// Terms of the month of the monthly machines chosen (D, hourly price), before the preview.
  Future<void> _loadTerms() async {
    final cov = _coverage ?? <Json>[];
    final monthly = cov.where((c) => c.str('billing_mode') == 'Monthly' && _selected.contains(c.intv('equipment_id'))).map((c) => c.intv('equipment_id')).toList();
    if (_vendor == null || monthly.isEmpty) {
      if (mounted) setState(() => _terms = null);
      return;
    }
    setState(() => _termsLoading = true);
    try {
      final rows = await Api.I.getList('/equipment/payroll/monthly-terms', query: {'start_date': _from, 'end_date': _to, 'vendor_id': _vendor!.value, 'equipment_ids': monthly.join(',')});
      if (mounted) setState(() => _terms = rows);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _termsLoading = false);
    }
  }

  void _toggle(int id, bool on, {bool take = false}) {
    _changed(() {
      if (on) {
        _selected.add(id);
        if (take) _take.add(id);
      } else {
        _selected.remove(id);
        _take.remove(id);
      }
    });
    _loadTerms();
  }

  Future<void> _takeFromDraft(Json c) async {
    final drafts = c.list('overlaps').map((o) => '#${o.str('eq_batch_id')}').toSet().join(', ');
    final ok = await confirmDialog(context, 'Take ${c.str('label')} into this invoice?',
        'Draft $drafts is deleted, or recalculated without this machine, when you create this one. Drafts have no number yet.', confirm: 'Take it');
    if (ok) _toggle(c.intv('equipment_id'), true, take: true);
  }

  Future<void> _check() async {
    if (_coverage != null && _selected.isEmpty) {
      showSnack(context, 'Choose at least one machine.', error: true);
      return;
    }
    setState(() { _busy = true; _previewError = null; });
    try {
      _blockers = asJsonList(await Api.I.get('/equipment/payroll/blockers', query: _query));
      try {
        _preview = asJson(await Api.I.post('/equipment/payroll/preview', _scope..remove('take_from_drafts')));
      } catch (e) {
        _preview = null;
        _previewError = e;
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  bool get _hasBlocking => (_blockers ?? []).any((b) => !_isInfo(b));

  String? _acceptReason;

  Future<void> _generate({bool accept = false, String? currency}) async {
    if (_hasBlocking && !accept) {
      final why = await askAcceptReason(context);
      if (why == null) return;
      _acceptReason = why;
      accept = true;
    }
    setState(() => _busy = true);
    try {
      final body = {
        ..._scope, 'accept_blockers': accept, if (accept && _acceptReason != null) 'accept_reason': _acceptReason, if (currency != null) 'currency': currency,
      };
      final r = await Api.I.request('POST', '/equipment/payroll/generate', body: body);
      final b = asJson(r['data']);
      final warnings = asJsonList(r['warnings']);
      if (!mounted) return;
      final moved = warnings.where((w) => w.str('code') == 'DRAFT_VOIDED' || w.str('code') == 'DRAFT_RECALCULATED').toList();
      final other = warnings.length - moved.length;
      showSnack(context, 'Draft invoice #${b.str('eq_batch_id')} created'
          '${moved.isEmpty ? '' : '. ${moved.map((w) => w.str('message')).join(' ')}'}'
          '${other <= 0 ? '' : ' ($other warning(s))'}.');
      Navigator.pop(context, b.intv('eq_batch_id'));
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'MIXED_CURRENCY') {
        final cur = (e.details?['currencies'] as List?)?.map((x) => '$x').toList() ?? <String>[];
        final p = await pickFromList(context, 'Several currencies: choose the invoice currency', [for (final c in cur) PickOption(c, c)]);
        if (p != null) await _generate(accept: accept, currency: p.value as String);
        return;
      }
      if (e.code == 'BLOCKERS_PRESENT') {
        setState(() => _blockers = asJsonList(e.details?['blockers']));
        final why = await askAcceptReason(context);
        if (why == null) return;
        _acceptReason = why;
        await _generate(accept: true, currency: currency);
        return;
      }
      if (e.code == 'PERIOD_OVERLAP') {
        await showOverlapDialog(context, e.details == null ? <Json>[] : e.details!.list('overlaps'), onUse: _usePeriod);
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
    final overlaps = p == null ? <Json>[] : p.list('overlaps').where((m) => !_take.contains(m.intv('equipment_id'))).toList();
    var step = 1;
    return Scaffold(
      appBar: AppBar(title: const Text('New invoice')),
      body: PageBody(maxWidth: 1300, children: [
        const SizedBox(height: 16),
        SectionCard(
          title: '${step++}. Period and vendor',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              DateField(label: 'From', value: _from, width: 170, onChanged: (v) => _changed(() => _from = v!, reloadMachines: true)),
              DateField(label: 'To', value: _to, width: 170, onChanged: (v) => _changed(() => _to = v!, reloadMachines: true)),
              PickerField(label: 'Vendor (all)', width: 240, icon: Icons.business_rounded, valueLabel: _vendor?.label, load: () => Lookups.vendors(),
                  onChanged: (v) => _changed(() => _vendor = v, reloadMachines: true)),
              PickerField(label: 'Site (all)', width: 220, icon: Icons.location_city_rounded, valueLabel: _site?.label, load: () => Lookups.sites(activeOnly: false),
                  onChanged: (v) => _changed(() => _site = v, reloadMachines: true)),
              Dropdown<String?>(label: 'Currency', value: _currency, width: 130, items: const [
                DropdownMenuItem(value: null, child: Text('Auto')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
                DropdownMenuItem(value: 'SYP', child: Text('SYP')),
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
              ], onChanged: (v) => _changed(() => _currency = v)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in _quickRanges())
                ActionChip(label: Text(q.$1), onPressed: () => _usePeriod(q.$2, q.$3)),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  _vendor == null
                      ? 'Choose a vendor to pick its machines one by one; without a vendor the invoice takes every vendor (one vendor invoice each).'
                      : 'Any period is allowed, as long as the machines have no other invoice on the same days.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          ]),
        ),
        if (_vendor != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: '${step++}. Machines',
            trailing: Wrap(spacing: 8, children: [
              TextButton(
                onPressed: _coverage == null
                    ? null
                    : () {
                        _changed(() => _selected.addAll(_coverage!.where((c) => c.flag('is_ready')).map((c) => c.intv('equipment_id'))));
                        _loadTerms();
                      },
                child: const Text('Select all ready'),
              ),
              TextButton(onPressed: () { _changed(() { _selected.clear(); _take.clear(); }); _loadTerms(); }, child: const Text('Clear')),
            ]),
            child: _coverageLoading && _coverage == null
                ? const LoadingView()
                : (_coverage ?? []).isEmpty
                    ? const EmptyView(text: 'No machine of this vendor in this period.', icon: Icons.precision_manufacturing_rounded)
                    : Column(children: [for (final c in _coverage!) _machineRow(c)]),
          ),
        ],
        if (_terms != null && _terms!.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: '${step++}. Monthly machines: normal month or exception',
            trailing: _termsLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Monthly machines are billed as a normal month (the card\'s monthly price, whatever the number of working days). '
                  'When a month is billed differently for one machine, type an exception here BEFORE the preview: the amount of the month, '
                  'the days it is divided by, or the hourly price used for deductions and overtime. It is kept on the machine and the month.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final t in _terms!)
                _MonthTermsTile(
                  key: ValueKey('${t.str('equipment_id')}-${t.str('month')}'),
                  row: t,
                  onSaved: (row) {
                    _changed(() {
                      final i = _terms!.indexWhere((x) => x.intv('equipment_id') == row.intv('equipment_id') && x.str('month') == row.str('month'));
                      if (i >= 0) _terms![i] = row;
                    });
                  },
                ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy || (_coverage != null && _selected.isEmpty) ? null : _check,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.calculate_rounded),
            label: const Text('Calculate preview'),
          ),
        ),
        if (_blockers != null) ...[
          const SizedBox(height: 14),
          _BlockersCard(blockers: _blockers!, onChanged: _check),
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
            title: '$step. Preview',
            trailing: FilledButton.icon(
              onPressed: _busy || (items.isEmpty && _take.isEmpty) ? null : () => _generate(),
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Create draft invoice'),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (overlaps.isNotEmpty)
                NoticeBox(
                  color: AppColors.breakdown,
                  icon: Icons.event_busy_rounded,
                  title: 'Some machines already have an invoice in this period',
                  text: overlaps.map((m) => '${m.str('label')}: ${m.list('conflicts').map(_conflictText).join(', ')}').join('\n'),
                  action: TextButton(onPressed: () => showOverlapDialog(context, overlaps, onUse: _usePeriod), child: const Text('Details')),
                ),
              if (_take.isNotEmpty)
                NoticeBox(
                  color: AppColors.standby,
                  icon: Icons.move_down_rounded,
                  text: '${_take.length} machine(s) are in another draft: the preview shows what is free now; on "Create" they move into this invoice.',
                ),
              if (items.isEmpty) const EmptyView(text: 'Nothing to invoice in this scope and period.', icon: Icons.money_off_rounded),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final t in totals) ...[
                  KpiTile(label: 'Machines / vendors', value: '${t.str('machines')} / ${t.str('vendors')}', icon: Icons.precision_manufacturing_rounded),
                  KpiTile(label: 'Work hours', value: t.str('work_hours'), icon: Icons.timer_rounded, color: AppColors.working),
                  KpiTile(label: 'Gross (${t.str('currency')})', value: Fmt.money2(t.strOrNull('gross'), t.str('currency')), width: 200),
                  KpiTile(label: 'Deductions', value: Fmt.money2(t.strOrNull('deductions'), t.str('currency')), color: AppColors.breakdown, width: 200),
                  KpiTile(label: 'Net', value: Fmt.money2(t.strOrNull('net'), t.str('currency')), color: AppColors.navy, width: 220, icon: Icons.account_balance_wallet_rounded),
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
              for (final it in items)
                _ItemTile(
                  item: it,
                  preview: true,
                  offsetKeys: _offsets,
                  onOffset: Auth.I.isAdmin && !_busy
                      ? (key, on) {
                          setState(() => on ? _offsets.add(key) : _offsets.remove(key));
                          _check();
                        }
                      : null,
                  offsetNote: Auth.I.isAdmin ? null : 'Only the Admin decides this (on the draft or the issued invoice).',
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// One machine of the vendor: ready (selectable), already invoiced on some days (with links and the free parts),
  /// or in another draft ("Take it").
  Widget _machineRow(Json c) {
    final id = c.intv('equipment_id');
    final selected = _selected.contains(id);
    final ready = c.flag('is_ready');
    final overlaps = c.list('overlaps');
    final onlyDrafts = overlaps.isNotEmpty && overlaps.every((o) => o.str('state') == 'draft');
    final taken = _take.contains(id);
    final r = c.obj('ready');
    final readyText = [
      if (r.intv('rows') > 0) '${r.intv('rows')} day(s)',
      if (r.intv('monthly_days') > 0) '${r.intv('monthly_days')} monthly day(s)',
      if (r.intv('fuel') > 0) '${r.intv('fuel')} fuel',
      if (r.intv('adjustments') > 0) '${r.intv('adjustments')} adjustment(s)',
      if (r.intv('dnr') > 0) '${r.intv('dnr')} delivery note(s)',
    ].join(', ');
    final blockers = c.obj('blockers');
    final mode = const {'Hourly': 'Hourly', 'Daily': 'Daily', 'Monthly': 'Monthly'}[c.str('billing_mode')] ?? (c.strOrNull('billing_mode') ?? 'DNR / no card');
    final selectable = ready || taken;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(value: selected, onChanged: selectable ? (v) => _toggle(id, v ?? false) : null),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.str('label')}${c.strOrNull('plate') == null ? '' : '  ·  ${c.str('plate')}'}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: selectable ? AppColors.ink : AppColors.muted)),
              Text([
                mode,
                if (overlaps.isEmpty) (ready ? 'ready: $readyText' : 'nothing to invoice') else if (readyText.isNotEmpty) 'to invoice: $readyText',
                if (blockers.isNotEmpty) 'problems: ${blockers.entries.map((e) => '${e.key.replaceAll('_', ' ')} ${e.value}').join(', ')}',
              ].join('  ·  '), style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
          if (onlyDrafts && !taken)
            TextButton.icon(onPressed: () => _takeFromDraft(c), icon: const Icon(Icons.move_down_rounded, size: 18), label: const Text('Take it'))
          else if (taken)
            const Pill('Taken from draft', color: AppColors.standby),
        ]),
        if (overlaps.isNotEmpty && !taken)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final o in overlaps)
                Row(children: [
                  Icon(invoiceStateIcon(o.str('state')), size: 16, color: invoiceStateColor(o.str('state'))),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Already in ${_conflictText(o)}', style: const TextStyle(fontSize: 12.5))),
                  TextButton(onPressed: () => _openInvoice(context, o.intv('eq_batch_id')), child: const Text('Open')),
                ]),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Free:', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                if (c.list('free').isEmpty) const Text('nothing in this period', style: TextStyle(fontSize: 12.5)),
                for (final f in c.list('free'))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.event_available_rounded, size: 16, color: AppColors.working),
                    label: Text('${Fmt.date(f.str('from'))} – ${Fmt.date(f.str('to'))}'),
                    onPressed: () => _usePeriod(f.str('from'), f.str('to')),
                  ),
              ]),
            ]),
          ),
      ]),
    );
  }

  List<(String, String, String)> _quickRanges() {
    final n = Fmt.now();
    return [
      ('Last month', Fmt.dateOf(DateTime(n.year, n.month - 1, 1)), Fmt.dateOf(DateTime(n.year, n.month, 0))),
      ('This month', Fmt.dateOf(DateTime(n.year, n.month, 1)), Fmt.dateOf(DateTime(n.year, n.month + 1, 0))),
      ('1st half', Fmt.dateOf(DateTime(n.year, n.month, 1)), Fmt.dateOf(DateTime(n.year, n.month, 15))),
      ('2nd half', Fmt.dateOf(DateTime(n.year, n.month, 16)), Fmt.dateOf(DateTime(n.year, n.month + 1, 0))),
    ];
  }
}

/// What blocks an invoice, with the rows listed. Rows not approved yet are approved or rejected right here (Admin), or
/// opened to be fixed; any other row opens too. [onChanged] runs after a change (the caller checks again).
class _BlockersCard extends StatefulWidget {
  const _BlockersCard({required this.blockers, required this.onChanged, this.title = 'Problems in this scope'});
  final List<Json> blockers;
  final VoidCallback onChanged;
  final String title;
  @override
  State<_BlockersCard> createState() => _BlockersCardState();
}

class _BlockersCardState extends State<_BlockersCard> {
  bool _busy = false;

  Future<void> _run(Future<dynamic> Function() fn, String verb) async {
    setState(() => _busy = true);
    try {
      final r = asJson(await fn());
      if (!mounted) return;
      final done = (r[verb] is List) ? (r[verb] as List).length : 0;
      final skipped = r.list('skipped');
      showSnack(context, '$done row(s) $verb${skipped.isEmpty ? '' : '; ${skipped.length} skipped: ${skipped.map((s) => s.str('message', s.str('reason'))).toSet().join('; ')}'}.',
          error: skipped.isNotEmpty && done == 0);
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _approve(List<int> ids) => _run(() => Api.I.post('/equipment/admin/attendance/approve', {'ids': ids}), 'approved');

  Future<void> _reject(List<int> ids) async {
    final why = await promptText(context, ids.length == 1 ? 'Reject this row?' : 'Reject ${ids.length} rows?',
        label: 'Why? (the supervisor sees it and fixes the row)', minLength: 3, confirm: 'Reject');
    if (why == null) return;
    _run(() => Api.I.post('/equipment/admin/attendance/reject', {'ids': ids, 'notes': why}), 'rejected');
  }

  Future<void> _open(int id) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AttendanceDetailSheet(id: id),
    );
    widget.onChanged();
  }

  String _rowText(Json i) => [
        if (i.strOrNull('sheet_code') != null) '${i.str('sheet_code')} rows to ${i.str('needed_row')}, uploaded to ${i.str('scanned_row')}',
        i.str('equipment_code'),
        if (i.strOrNull('site_code') != null) i.str('site_code'),
        Fmt.date(i.strOrNull('record_date') ?? i.strOrNull('issue_date')),
      ].join(' · ');

  Widget _notApproved(Json b) {
    final items = b.list('items');
    final submitted = items.where((i) => i.str('status') == 'Submitted').map((i) => i.intv('eq_attendance_id')).toList();
    final admin = Auth.I.isAdmin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (admin && submitted.length > 1)
        Wrap(spacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _approve(submitted),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text('Approve all submitted (${submitted.length})'),
          ),
        ]),
      for (final i in items.take(100))
        Row(children: [
          Expanded(child: Text(_rowText(i), style: const TextStyle(fontSize: 13))),
          StatePillText(i.str('status')),
          IconButton(tooltip: 'Open the row', onPressed: _busy || i.intOrNull('eq_attendance_id') == null ? null : () => _open(i.intv('eq_attendance_id')), icon: const Icon(Icons.open_in_new_rounded, size: 18)),
          if (admin && i.str('status') == 'Submitted') ...[
            IconButton(tooltip: 'Approve', onPressed: _busy ? null : () => _approve([i.intv('eq_attendance_id')]), icon: const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.working)),
            IconButton(tooltip: 'Reject (with a reason)', onPressed: _busy ? null : () => _reject([i.intv('eq_attendance_id')]), icon: const Icon(Icons.cancel_rounded, size: 20, color: AppColors.breakdown)),
          ],
        ]),
      if (items.length > 100) Text('+${items.length - 100} more (Attendance review)', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      if (items.any((i) => i.str('status') == 'Draft'))
        const Text('Draft rows: the supervisor has not submitted them yet (or open one and fix it).', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final blockers = widget.blockers;
    if (blockers.isEmpty) {
      return const Card(
        color: Color(0xFFE8F5EE),
        child: ListTile(
          leading: Icon(Icons.verified_rounded, color: AppColors.working),
          title: Text('No blockers', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Every row of this scope is approved, closed and reconciled.'),
        ),
      );
    }
    return SectionCard(
      title: widget.title,
      trailing: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(children: [
        for (final b in blockers)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: b.str('code') == 'NOT_APPROVED',
              leading: Icon(_isInfo(b) ? Icons.info_outline_rounded : Icons.block_rounded, color: _isInfo(b) ? AppColors.info : AppColors.breakdown),
              title: Text('${b.str('message')}  (${b.str('count')})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(_blockerHelp[b.str('code')] ?? '', style: const TextStyle(fontSize: 12.5)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              children: [
                if (b.str('code') == 'NOT_APPROVED')
                  _notApproved(b)
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final i in b.list('items').take(60))
                      i.intOrNull('eq_attendance_id') == null
                          ? Pill(_rowText(i), color: AppColors.ink, outlined: true)
                          : InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _busy ? null : () => _open(i.intv('eq_attendance_id')),
                              child: Pill(_rowText(i), color: AppColors.navy, outlined: true, icon: Icons.open_in_new_rounded),
                            ),
                    if (b.list('items').length > 60) Pill('+${b.list('items').length - 60} more'),
                  ]),
              ],
            ),
          ),
      ]),
    );
  }
}

/// Status of an attendance row as a small pill (Submitted / Draft / Rejected).
class StatePillText extends StatelessWidget {
  const StatePillText(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Pill(status, color: switch (status) { 'Rejected' => AppColors.breakdown, 'Draft' => AppColors.neutral, _ => AppColors.standby });
}

/// One monthly machine x month on New payroll (12 Oct 2026): a NORMAL month by default (the card's monthly price divided
/// by the working days of the month), or an EXCEPTION typed for this machine and month: the amount of the month, the days
/// it is divided by and / or the hourly price. Saved when a field is left; ↺ goes back to a normal month. Locked only
/// while an invoice handed over to finance bills the month (14 Oct 2026); drafts and issued invoices follow the change.
class _MonthTermsTile extends StatefulWidget {
  const _MonthTermsTile({super.key, required this.row, required this.onSaved});
  final Json row;
  final ValueChanged<Json> onSaved;
  @override
  State<_MonthTermsTile> createState() => _MonthTermsTileState();
}

class _MonthTermsTileState extends State<_MonthTermsTile> {
  late final TextEditingController _amount;
  late final TextEditingController _days;
  late final TextEditingController _hourly;
  bool _hourlyTyped = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _days = TextEditingController();
    _hourly = TextEditingController();
    _fill();
  }

  void _fill() {
    final r = widget.row;
    _amount.text = _fmt(r.dblOrNull('amount') ?? r.dbl('monthly_rate'));
    _days.text = r.str('divisor');
    _hourly.text = _fmt(r.dbl('hourly'));
    _hourlyTyped = r.str('hourly_source') == 'manual';
  }

  @override
  void didUpdateWidget(covariant _MonthTermsTile old) {
    super.didUpdateWidget(old);
    if (old.row != widget.row) _fill();
  }

  @override
  void dispose() {
    _amount.dispose();
    _days.dispose();
    _hourly.dispose();
    super.dispose();
  }

  static String _fmt(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 4).replaceFirst(RegExp(r'\.?0+$'), '');
  static double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Hourly price follows the amount and the days (until a price is typed by hand).
  void _recalc() {
    if (_hourlyTyped) return;
    final a = _num(_amount);
    final d = int.tryParse(_days.text.trim());
    final hpd = widget.row.dbl('hours_per_day');
    if (a == null || d == null || d < 1 || hpd <= 0) return;
    setState(() => _hourly.text = _fmt(((a / d / hpd) * 10000).round() / 10000));
  }

  Future<void> _save({bool reset = false}) async {
    final r = widget.row;
    final a = _num(_amount);
    final d = int.tryParse(_days.text.trim());
    final h = _num(_hourly);
    final amountChanged = a != null && (a - (r.dblOrNull('amount') ?? r.dbl('monthly_rate'))).abs() > 0.004;
    final daysChanged = d != null && d != r.intv('divisor');
    final hourlyChanged = _hourlyTyped && h != null && (h - r.dbl('hourly')).abs() > 0.00005;
    if (!reset && !amountChanged && !daysChanged && !hourlyChanged) return;
    setState(() => _saving = true);
    try {
      final keepAmount = amountChanged || r.str('amount_source') == 'manual';
      final keepDays = daysChanged || r.str('divisor_source') == 'manual';
      final row = asJson(await Api.I.put('/equipment/payroll/monthly-terms', {
        'equipment_id': r.intv('equipment_id'),
        'month': r.str('month'),
        // the amount equal to the card's price is not an exception
        'monthly_amount': reset || !keepAmount || (a != null && (a - r.dbl('monthly_rate')).abs() < 0.005) ? null : a,
        // the days equal to the calendar are not an exception
        'working_days': reset || !keepDays || d == r.intv('calendar_days') ? null : d,
        'hourly_rate': reset ? null : (_hourlyTyped ? h : null),
      }));
      if (!mounted) return;
      widget.onSaved(row);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(_fill);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, String helper, {bool decimal = true, ValueChanged<String>? onChanged, bool enabled = true}) => SizedBox(
        width: 170,
        child: Focus(
          onFocusChange: (f) { if (!f && enabled) _save(); },
          child: TextField(
            controller: c,
            enabled: enabled && !_saving,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            onChanged: onChanged,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: label, isDense: true, helperText: helper, helperMaxLines: 2),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final cur = r.str('currency');
    final locked = r.flag('locked');
    final exception = r.flag('is_exception');
    final ot = !r.flag('overtime_enabled')
        ? 'off (extra hours not paid, kept to cover missing hours)'
        : r.dblOrNull('overtime_rate') != null
            ? 'paid at ${r.dbl('overtime_rate').toStringAsFixed(2)}'
            : 'paid at the hourly price';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: exception ? AppColors.edited.withValues(alpha: 0.06) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: exception ? AppColors.edited.withValues(alpha: 0.4) : AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${r.str('label')}  ·  ${Fmt.monthLabel(r.str('month'))}', style: const TextStyle(fontWeight: FontWeight.w800))),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: exception ? const Pill('Exception for this month', color: AppColors.edited) : const Pill('Normal month', color: AppColors.working),
          ),
          if (locked) Pill('${r.str('locked_state') == 'returned' ? 'Withdrawn' : 'Handed over'} #${r.str('locked_by_batch_id')}', color: AppColors.navy, icon: Icons.lock_rounded),
        ]),
        const SizedBox(height: 4),
        Text('Card: ${Fmt.money2(r.strOrNull('monthly_rate'), cur)} per month · ${r.str('hours_per_day')} h per working day · '
            '${r.str('calendar_days')} working days in ${Fmt.monthLabel(r.str('month'))} · overtime $ot',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _field(_amount, 'Amount of the month ($cur)', r.str('amount_source') == 'manual' ? 'typed for this month' : 'the card\'s price',
              enabled: !locked, onChanged: (_) => _recalc()),
          _field(_days, 'Divided by (days)', r.str('divisor_source') == 'manual' ? 'typed (calendar ${r.str('calendar_days')})' : 'working days of the month',
              decimal: false, enabled: !locked, onChanged: (_) => _recalc()),
          _field(_hourly, 'Hourly price', r.str('hourly_source') == 'manual' ? 'typed' : 'amount / days / hours',
              enabled: !locked, onChanged: (_) => _hourlyTyped = true),
          IconButton(
            tooltip: 'Back to a normal month',
            onPressed: locked || _saving || !exception ? null : () => _save(reset: true),
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          if (_saving) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 6),
        Text(
          r.intOrNull('deployed_working_days') == null
              ? 'Nothing of this month is left to bill in this period.'
              : 'On site ${r.str('deployed_working_days')} working day(s) · ${r.dbl('required_hours').toStringAsFixed(0)} h due · '
                  'done so far ${r.dbl('billable_hours_so_far').toStringAsFixed(2)} h → about ${Fmt.money2(r.strOrNull('estimated_amount'), cur)}'
                  '${r.obj('already_billed').isEmpty ? '' : '  (part of the month: ${r.obj('already_billed').str('base_days')} base day(s) already billed)'}',
          style: const TextStyle(fontSize: 12.5),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            locked
                ? (r.str('locked_state') == 'returned'
                    ? 'Invoice #${r.str('locked_by_batch_id')} bills this month and is withdrawn from finance: only the Admin changes it now.'
                    : 'Invoice #${r.str('locked_by_batch_id')} bills this month and is handed over to finance: withdraw it first (Admin), or make a debit / credit note.')
                : 'Examples: the vendor is paid the 27th day → amount = price x 27 / 26, divided by 27. A special price agreed for one month → type the amount. '
                    'Leave everything as it is for a normal month.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
      ]),
    );
  }
}

/// One machine line of a preview / batch with its calculation lines.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, this.preview = false, this.onRows, this.onPdf, this.onExcel, this.onFuelPdf, this.onNote,
      this.offsetKeys = const <String>{}, this.onOffset, this.offsetNote});
  final Json item;
  final bool preview;
  /// monthly machines: months ("<equipment_id>|YYYY-MM") whose extra hours cover missing hours (Admin decision)
  final Set<String> offsetKeys;
  /// the Admin may change the decision here (null: shown read-only with offsetNote)
  final void Function(String key, bool on)? onOffset;
  final String? offsetNote;
  final VoidCallback? onRows;
  final VoidCallback? onPdf;
  /// the machine's payment certificate (Excel)
  final VoidCallback? onExcel;
  /// a debit / credit note for this machine, linked to the invoice
  final VoidCallback? onNote;
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
                Text('${item.str('equipment_code')}  ${item.machineType}', style: const TextStyle(fontWeight: FontWeight.w800)),
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
              if (item.str('billing_mode') == 'DNR') ...[
                kv('Delivery notes', '${item.list('lines').where((l) => l.str('line_type') == 'DeliveryNote').length}'),
                kv('Shifts', item.str('worked_days')),
              ] else ...[
                kv('Shifts', '${item.str('worked_days')}/${item.str('days_recorded')}'),
                kv('Work h', item.str('work_hours')),
              ],
              if (item.dbl('overtime_hours') > 0) kv('OT h', item.str('overtime_hours')),
              if (item.dbl('standby_hours') > 0) kv('Standby h', item.str('standby_hours')),
              if (item.dbl('breakdown_hours') > 0) kv('Breakdown h', item.str('breakdown_hours')),
              if (item.dbl('topup_hours') > 0) kv('Min. top-up h', item.str('topup_hours')),
              if ((item.dblOrNull('fuel_difference') ?? 0) != 0) kv('Fuel price difference', Fmt.money(item.dbl('fuel_difference'), cur)),
            ]),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            for (final mo in (item.list('monthly_calc').isNotEmpty ? item.list('monthly_calc') : item.obj('rate_snapshot').list('monthly_calc'))) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Text(_monthText(mo, item.str('currency')), style: const TextStyle(fontSize: 12.5)),
              ),
              if (mo.dbl('offset_possible_hours') > 0 || mo.dbl('offset_hours') != 0 || offsetKeys.contains('${item.str('equipment_id')}|${mo.str('month')}'))
                _OffsetBox(
                  mo: mo,
                  on: offsetKeys.contains('${item.str('equipment_id')}|${mo.str('month')}'),
                  note: offsetNote,
                  onChanged: onOffset == null ? null : (v) => onOffset!('${item.str('equipment_id')}|${mo.str('month')}', v),
                ),
            ],
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
                      _Td(['FuelPriceDifference', 'Fuel', 'HoursShortfall', 'BreakdownDeduction', 'AbsenceDeduction', 'ExtraHoursOffset', 'Overtime'].contains(l.str('line_type'))
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
            if (onRows != null || onPdf != null || onExcel != null || onFuelPdf != null || onNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, children: [
                  if (onRows != null) TextButton.icon(onPressed: onRows, icon: const Icon(Icons.list_alt_rounded, size: 18), label: const Text('Days')),
                  if (onPdf != null) TextButton.icon(onPressed: onPdf, icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Machine invoice')),
                  if (onFuelPdf != null) TextButton.icon(onPressed: onFuelPdf, icon: const Icon(Icons.local_gas_station_rounded, size: 18), label: const Text('Fuel difference statement')),
                  if (onExcel != null) TextButton.icon(onPressed: onExcel, icon: const Icon(Icons.grid_on_rounded, size: 18), label: const Text('Excel certificate')),
                  if (onNote != null) TextButton.icon(onPressed: onNote, icon: const Icon(Icons.post_add_rounded, size: 18), label: const Text('Debit / credit note')),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// "<equipment_id>|YYYY-MM" of the months whose extra hours cover missing hours (a list of strings in the batch).
Set<String> _offsetKeysOf(Json b) => b['offset_months'] is List ? (b['offset_months'] as List).map((x) => '$x').toSet() : <String>{};

/// The Admin's decision for one monthly machine and month: do its extra hours cover its missing hours? (12 Oct 2026)
class _OffsetBox extends StatelessWidget {
  const _OffsetBox({required this.mo, required this.on, this.onChanged, this.note});
  final Json mo;
  final bool on;
  final ValueChanged<bool>? onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    String hh(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
    final missing = mo.dbl('month_missing_hours');
    final extra = mo.dbl('month_extra_hours');
    final possible = mo.dbl('offset_possible_hours');
    final ot = mo.flag('overtime_paid');
    final explain = 'This month: ${hh(missing)} h missing, ${hh(extra)} h extra'
        '${possible > 0 ? ' (${hh(possible)} h can cover missing hours now)' : ''}. '
        'On: each extra hour covers one missing hour (paid back at the hourly price), and is not paid as overtime. '
        'Off: the missing hours stay deducted and the extra hours are ${ot ? 'paid as overtime' : 'not paid (overtime off) but kept: they can still cover missing hours in a later invoice of this month'}. '
        'Breakdowns are never covered.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      decoration: BoxDecoration(
        color: (on ? AppColors.working : AppColors.info).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (on ? AppColors.working : AppColors.info).withValues(alpha: 0.35)),
      ),
      child: onChanged != null
          ? SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: onChanged,
              title: Text('${Fmt.monthLabel(mo.str('month'))}: use the extra hours to cover the missing hours?', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: Text(explain, style: const TextStyle(fontSize: 12.5)),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${Fmt.monthLabel(mo.str('month'))}: extra hours ${on ? 'COVER the missing hours (Admin decision)' : 'do NOT cover the missing hours'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('$explain${note == null ? '' : '\n$note'}', style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
    );
  }
}

/// One month of a monthly machine (rules of 12 Oct 2026), in plain words: the terms (normal month or exception), what
/// is deducted, the extra hours and what was done with them.
String _monthText(Json mo, String cur) {
  final d = mo.strOrNull('divisor') ?? mo.str('working_days');
  final h = mo.dbl('hourly_price');
  String hh(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  final exception = [
    if (mo.str('amount_source') == 'manual') 'amount ${Fmt.money(mo.dbl('amount'), cur)} (typed)',
    if (mo.str('divisor_source', 'calendar') != 'calendar') 'divided by $d days (typed)',
    if (mo.str('hourly_source') == 'manual') 'hourly price typed',
  ];
  final deducted = [
    if (mo.dbl('absence_deducted_hours') != 0) 'absent ${mo.intv('absent_days')} day(s) −${hh(mo.dbl('absence_deducted_hours'))} h',
    if (mo.dbl('missing_hours') != 0) 'days below the hours due −${hh(mo.dbl('missing_hours'))} h',
    if (mo.dbl('breakdown_deducted_hours') != 0) 'breakdown −${hh(mo.dbl('breakdown_deducted_hours'))} h',
  ];
  final extra = mo.dbl('month_extra_hours');
  final used = [
    if (mo.dbl('offset_hours') != 0) '${hh(mo.dbl('offset_hours'))} h cover missing hours',
    if (mo.dbl('overtime_hours') != 0) '${hh(mo.dbl('overtime_hours'))} h paid as overtime x ${(mo.dblOrNull('overtime_price') ?? h).toStringAsFixed(2)}',
    if (mo.dbl('unpaid_extra_hours') > 0) '${hh(mo.dbl('unpaid_extra_hours'))} h kept unpaid (overtime off) — they can still cover missing hours later this month',
  ];
  final before = mo.obj('used_before');
  return '${Fmt.monthLabel(mo.str('month'))}: ${exception.isEmpty ? 'normal month' : 'EXCEPTION: ${exception.join(', ')}'} · '
      '${mo.str('deployed_working_days')} working day(s) on site, divided by $d → hourly price ${h.toStringAsFixed(3)} · ${mo.str('hours_per_day')} h due each day\n'
      'Deducted: ${deducted.isEmpty ? 'nothing' : deducted.join(', ')}\n'
      'Extra hours this month: ${hh(extra)} h${used.isEmpty ? '' : ' → ${used.join('; ')}'}'
      '${before.isEmpty || (before.dbl('offset_hours') == 0 && before.dbl('overtime_hours') == 0) ? '' : '\nEarlier invoices of this month already used ${hh(before.dbl('offset_hours'))} h as cover and ${hh(before.dbl('overtime_hours'))} h as overtime'}';
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
    'HoursShortfall': 'Missing hours (days below the hours due)',
    'SecondShift': 'Second shift the same day',
    'DeliveryNote': 'Delivery note (DNR)',
    'ExtraHoursOffset': 'Extra hours covering missing hours (Admin decision)',
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

// =================================================================== invoice detail
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.id});
  final int id;
  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  /// The batch shown: an issued invoice brought up to date gets a new internal id (same numbers).
  late int _id = widget.id;
  Json? _b;
  Object? _error;
  bool _busy = false;
  bool _refreshing = false;
  /// Why the invoice could not be brought up to date by itself (rows not approved, month linked...).
  ApiException? _refreshError;
  /// Rows of the period not approved yet (from an issue / refresh refusal): approved or rejected right here.
  List<Json>? _blockers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var b = await Api.I.getObj('/equipment/payroll/batches/$_id');
      // an old calculation (opened from an old link, or replaced while printing): show the current one
      if (b.str('state') == 'superseded') {
        final chain = await Api.I.getList('/equipment/payroll/batches/$_id/versions');
        final cur = chain.lastWhere((v) => v.str('state') != 'superseded', orElse: () => b);
        if (cur.intv('eq_batch_id') != _id) {
          _id = cur.intv('eq_batch_id');
          b = await Api.I.getObj('/equipment/payroll/batches/$_id');
        }
      }
      // an issued invoice still in the office is kept up to date silently, with the same numbers (the audit keeps it)
      if (b.flag('needs_refresh') && b.obj('actions').flag('refresh') && !_refreshing) {
        _refreshing = true;
        try {
          b = asJson(await Api.I.post('/equipment/payroll/batches/$_id/refresh'));
          _id = b.intv('eq_batch_id', _id);
          _refreshError = null;
          _blockers = null;
        } on ApiException catch (e) {
          _refreshError = e;
          if (e.code == 'ROWS_NOT_APPROVED') _blockers = e.details?.list('blockers');
        } finally {
          _refreshing = false;
        }
      } else if (!b.flag('needs_refresh')) {
        _refreshError = null;
      }
      if (mounted) setState(() { _b = b; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Runs an action; a result that is another batch (new calculation, re-issue) becomes the one shown.
  Future<void> _act(Future<dynamic> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (!mounted) return;
      if (r is Map && asJson(r).intOrNull('eq_batch_id') != null) _id = asJson(r).intv('eq_batch_id');
      showSnack(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ROWS_NOT_APPROVED') setState(() => _blockers = e.details?.list('blockers'));
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _no => _b?.strOrNull('vendor_invoice_no') ?? 'Draft #$_id';

  // ------------------------------------------------------------- draft
  /// Shows the manual changes this invoice pays; true when the person confirms they checked them.
  Future<bool> _reviewChanges(List<Json> items) async {
    var checked = false;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Check ${items.length} manual change(s) before issuing'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('This invoice pays changes made by hand. Check them before the invoice gets its number.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final i in items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_note_rounded, color: AppColors.edited),
                      title: Text('${_reviewKinds[i.str('kind')] ?? i.str('kind')}: ${i.str('ref')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        if (i.strOrNull('by') != null) 'by ${i.str('by')}',
                        if (i.strOrNull('reason') != null) i.str('reason'),
                      ].join('  ·  ')),
                    ),
                ]),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: checked,
                onChanged: (v) => set(() => checked = v ?? false),
                title: const Text('I checked these changes'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: checked ? () => Navigator.pop(ctx, true) : null, child: const Text('Issue')),
          ],
        ),
      ),
    );
    return r ?? false;
  }

  /// Draft -> Issued: official numbers (VI for the vendor, MI per machine, FD per fuel difference).
  Future<void> _issue() async {
    var ack = false;
    try {
      final summary = await Api.I.getObj('/equipment/payroll/batches/$_id/review-summary');
      if (!mounted) return;
      final items = summary.list('items');
      if (items.isNotEmpty) {
        ack = await _reviewChanges(items);
        if (!ack) return;
      }
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!ack) {
      if (!mounted) return;
      final ok = await confirmDialog(context, 'Issue this invoice?',
          'It gets its official numbers (VI for the vendor, MI for each machine). It stays in the office: a change to its days is '
          'brought into it with the same number until it is handed over to finance.', confirm: 'Issue');
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await Api.I.patch('/equipment/payroll/batches/$_id/finalize', {'acknowledge_changes': ack});
      _blockers = null;
      await _load();
      if (mounted) showSnack(context, 'Invoice issued: $_no');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ROWS_NOT_APPROVED') {
        setState(() => _blockers = e.details?.list('blockers'));
        showSnack(context, e.message, error: true);
      } else if (e.code == 'CHANGES_NOT_ACKNOWLEDGED') {
        final items = e.details == null ? <Json>[] : e.details!.list('items');
        setState(() => _busy = false);
        if (items.isNotEmpty && await _reviewChanges(items)) {
          await _act(() => Api.I.patch('/equipment/payroll/batches/$_id/finalize', {'acknowledge_changes': true}), 'Invoice issued.');
        }
      } else {
        if (e.code == 'BATCH_STALE') await _load();
        if (mounted) showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Draft: a new calculation with the current data.
  Future<void> _recalculate() async {
    Future<dynamic> run(bool accept, String? reason) => Api.I.post('/equipment/payroll/batches/$_id/supersede', {'accept_blockers': accept, if (reason != null) 'reason': reason});
    setState(() => _busy = true);
    try {
      final r = asJson(await run(false, null));
      _id = r.intv('eq_batch_id', _id);
      if (mounted) showSnack(context, 'Draft recalculated.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'BLOCKERS_PRESENT') {
        final why = await askAcceptReason(context);
        if (why == null) return;
        await _act(() => run(true, why), 'Draft recalculated.');
      } else if (e.code == 'PERIOD_OVERLAP') {
        await showOverlapDialog(context, e.details == null ? <Json>[] : e.details!.list('overlaps'));
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDraft() async {
    final ok = await confirmDialog(context, 'Delete this draft?', 'It has no number. Its period becomes free for another invoice.', confirm: 'Delete', danger: true);
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Api.I.patch('/equipment/payroll/batches/$_id/void', {});
      if (!mounted) return;
      showSnack(context, 'Draft deleted.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  // ------------------------------------------------------------- issued / handed over / withdrawn
  Future<void> _cancel() async {
    final reason = await promptText(context, 'Cancel invoice $_no?',
        label: 'Why? (kept in the history)', minLength: 3, confirm: 'Cancel invoice',
        help: 'Its numbers stay cancelled and are never used again. Its days become free for a new invoice.');
    if (reason == null) return;
    _act(() => Api.I.patch('/equipment/payroll/batches/$_id/void', {'reason': reason}), 'Invoice cancelled.');
  }

  Future<void> _handOver() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => HandoverScreen(batchIds: {_id})));
    await _load();
  }

  Future<void> _withdraw() async {
    final body = await withdrawDialog(context, title: 'Withdraw $_no from finance', currency: _b?.str('currency'));
    if (body == null) return;
    setState(() => _busy = true);
    try {
      final r = await Api.I.request('POST', '/equipment/payroll/batches/$_id/withdraw', body: body);
      await _load();
      if (!mounted) return;
      showSnack(context, 'Withdrawn from finance. Print the acknowledgement for signature.');
      final wid = asJson(r).intOrNull('withdrawal_id');
      if (wid != null) openWithdrawalPdf(context, wid, _b?.obj('withdrawal').str('withdrawal_no', 'withdrawal') ?? 'withdrawal');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reissue() async {
    final reason = await promptText(context, 'Re-issue $_no with a new number?',
        label: 'Why? (kept in the history, not printed)', minLength: 3, confirm: 'Re-issue',
        help: 'The invoice is recalculated with the current data and gets NEW numbers. The old numbers stay cancelled. '
            'Nothing on the new invoice mentions the old one; the link is shown here only.');
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final b = asJson(await Api.I.post('/equipment/payroll/batches/$_id/reissue', {'reason': reason}));
      _id = b.intv('eq_batch_id', _id);
      await _load();
      if (mounted) showSnack(context, 'Re-issued: $_no');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ROWS_NOT_APPROVED') setState(() => _blockers = e.details?.list('blockers'));
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------- notes
  Future<void> _newNote({Json? item}) async {
    final b = _b!;
    final vendors = <int, String>{for (final i in b.list('items')) i.intv('vendor_id'): i.str('vendor_name')};
    int? vendorId = item?.intv('vendor_id');
    String? vendorName = item?.str('vendor_name');
    if (vendorId == null) {
      if (vendors.length == 1) {
        vendorId = vendors.keys.first;
        vendorName = vendors.values.first;
      } else {
        final p = await pickFromList(context, 'Note for which vendor?', [for (final e in vendors.entries) PickOption(e.key, e.value)]);
        if (p == null) return;
        vendorId = p.value as int;
        vendorName = p.label;
      }
    }
    if (!mounted) return;
    final n = await editNote(context,
        vendorId: vendorId,
        vendorName: vendorName,
        refBatchId: _id,
        refLabel: b.list('invoices').where((x) => x.str('kind') == 'Vendor' && x.intv('vendor_id') == vendorId).map((x) => x.str('invoice_no')).firstOrNull ?? _no,
        currency: b.str('currency'),
        equipmentId: item?.intv('equipment_id'),
        equipmentLabel: item == null ? null : item.machineName);
    if (n == null || !mounted) return;
    await _openNote(context, n.intv('note_id'));
    _load();
  }

  // ------------------------------------------------------------- documents
  /// Vendor and machine invoices go to the vendor: the office chooses what is printed (explanations, internal details);
  /// the money lines and totals always stay.
  Future<void> _pdf(String view, {int? vendorId, int? equipmentId, String suffix = ''}) async {
    Set<String> hide = {};
    if (view == 'vendor' || view == 'machine') {
      final r = await askPdfContent(context);
      if (r == null || !mounted) return;
      hide = r;
    }
    final id = _id;
    await PdfViewScreen.open(context,
        title: view == 'summary' ? 'Summary $_no' : suffix,
        fileName: '${suffix.isEmpty ? 'invoice-$id-$view' : suffix}.pdf',
        load: () => Api.I.getBytes('/equipment/payroll/batches/$id/export.pdf',
            query: {'view': view, 'vendor_id': vendorId, 'equipment_id': equipmentId, if (hide.isNotEmpty) 'hide': (hide.toList()..sort()).join(',')}));
  }

  Future<(int, String)?> _pickVendor(String title) async {
    final items = _b!.list('items');
    final vendors = <int, String>{for (final i in items) i.intv('vendor_id'): i.str('vendor_name')};
    if (vendors.isEmpty) return null;
    if (vendors.length == 1) return (vendors.keys.first, vendors.values.first);
    final p = await pickFromList(context, title, [for (final e in vendors.entries) PickOption(e.key, e.value)]);
    return p == null ? null : (p.value as int, p.label);
  }

  String _vendorNo(int vendorId) =>
      _b!.list('invoices').where((x) => x.str('kind') == 'Vendor' && x.intv('vendor_id') == vendorId && !x.flag('cancelled') && x.str('status') == 'Issued').map((x) => x.str('invoice_no')).firstOrNull ??
      'draft-$_id';

  Future<void> _vendorPdf() async {
    final v = await _pickVendor('Vendor invoice');
    if (v != null) _pdf('vendor', vendorId: v.$1, suffix: _vendorNo(v.$1));
  }

  Future<void> _download(String path, String fileName, {Map<String, dynamic>? query}) async {
    try {
      final bytes = await Api.I.getBytes(path, query: query);
      final msg = await FileSave.save(bytes, fileName);
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// The vendor invoice as an Excel payment certificate (the company's format, with the logo): one sheet per machine.
  Future<void> _certificate({int? vendorId, int? equipmentId, String? code}) async {
    var vid = vendorId;
    if (vid == null) {
      final v = await _pickVendor('Excel certificate for which vendor?');
      if (v == null) return;
      vid = v.$1;
    }
    await _download('/equipment/payroll/batches/$_id/certificate.xlsx', '${_vendorNo(vid)}${code == null ? '' : '-$code'}.xlsx',
        query: {'vendor_id': vid, if (equipmentId != null) 'equipment_id': equipmentId});
  }

  /// Admin: extra hours of a monthly machine cover its missing hours (or not). Draft: recalculated; issued: brought
  /// up to date with the same numbers.
  Future<void> _setOffset(String key, bool on) async {
    final now = _offsetKeysOf(_b!);
    on ? now.add(key) : now.remove(key);
    await _act(() => Api.I.patch('/equipment/payroll/batches/$_id/offsets', {'offsets': now.toList()..sort()}),
        on ? 'Extra hours now cover the missing hours.' : 'Extra hours no longer cover the missing hours.');
  }

  Future<void> _rows(Json item, bool editable) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SnapshotSheet(batchId: _id, item: item, editable: editable),
    );
    if (editable) await _load(); // a change is brought into the invoice (draft: shown as "recalculate")
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    return Scaffold(
      appBar: AppBar(title: Text(b == null ? 'Invoice' : (b.str('state') == 'draft' ? 'Draft invoice #$_id' : 'Invoice $_no'))),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : b == null
              ? const LoadingView()
              : _body(b),
    );
  }

  Widget _stateNotice(Json b) {
    final st = b.str('state');
    final ho = b.obj('handover');
    final wd = b.obj('withdrawal');
    switch (st) {
      case 'draft':
        return const NoticeBox(
          color: AppColors.standby,
          icon: Icons.edit_note_rounded,
          title: 'Draft: no number yet',
          text: 'It reserves this period for its machines. Issue it once the period has ended and every row is approved.',
        );
      case 'issued':
        return const NoticeBox(
          color: AppColors.info,
          icon: Icons.receipt_long_rounded,
          title: 'Issued, still in the office',
          text: 'A change to its days is brought into it automatically, with the same number. Hand it over to finance when it is ready.',
        );
      case 'handed_over':
        return NoticeBox(
          color: AppColors.working,
          icon: Icons.lock_rounded,
          title: 'Handed over to finance${ho.isEmpty ? '' : ': ${ho.str('handover_no')} on ${Fmt.date(ho.str('handed_on'))}, received by ${ho.str('receiver_name')}'}',
          text: 'Locked for everybody. To change it, the Admin withdraws it from finance (signed acknowledgement), or makes a debit / credit note.',
          action: ho.isEmpty
              ? null
              : TextButton(onPressed: () => openHandoverPdf(context, ho.intv('handover_id'), ho.str('handover_no')), child: const Text('Sheet')),
        );
      case 'returned':
        return NoticeBox(
          color: AppColors.edited,
          icon: Icons.undo_rounded,
          title: 'Withdrawn from finance${wd.isEmpty ? '' : ': ${wd.str('withdrawal_no')} on ${Fmt.date(wd.str('withdrawn_on'))}'}',
          text: [
            if (wd.isNotEmpty) 'Given back by ${wd.str('finance_person')}: ${wd.str('reason')}',
            if (wd.isNotEmpty) wd.flag('was_paid') ? 'Finance had paid it${wd.strOrNull('paid_amount') == null ? '' : ' (${Fmt.money2(wd.strOrNull('paid_amount'), b.str('currency'))})'}.' : 'It was not paid.',
            b.flag('stale')
                ? 'It changed since: re-issue it with a new number.'
                : 'The Admin can change its days, then re-issue it with a new number, cancel it, or hand it over again unchanged.',
          ].join('\n'),
          action: wd.isEmpty
              ? null
              : TextButton(onPressed: () => openWithdrawalPdf(context, wd.intv('withdrawal_id'), wd.str('withdrawal_no')), child: const Text('Acknowledgement')),
        );
      case 'cancelled':
        return NoticeBox(
          color: AppColors.breakdown,
          icon: Icons.block_rounded,
          title: 'Cancelled',
          text: '${b.strOrNull('void_reason') ?? 'Draft deleted.'} Its numbers are never used again.',
        );
      case 'replaced':
        final r = b.obj('replaced_by');
        return NoticeBox(
          color: AppColors.neutral,
          icon: Icons.history_rounded,
          title: 'Re-issued with a new number${r.strOrNull('invoice_no') == null ? '' : ': ${r.str('invoice_no')}'}',
          text: 'This number is cancelled and never used again.',
          action: r.isEmpty ? null : TextButton(onPressed: () => _openInvoice(context, r.intv('eq_batch_id')), child: const Text('Open')),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _body(Json b) {
    final cur = b.str('currency');
    final st = b.str('state');
    final a = b.obj('actions');
    final draft = st == 'draft';
    final hasFuelDiff = b.list('items').any((i) => (i.dblOrNull('fuel_difference') ?? 0) != 0);
    final vendorInvoices = b.list('invoices').where((i) => i.str('kind') == 'Vendor' && !i.flag('cancelled') && i.str('status') == 'Issued').toList();
    final cancelled = b.list('invoices').where((i) => i.flag('cancelled')).toList();
    final replaces = b.obj('replaces');
    // days editable from the invoice: office on a draft or an issued invoice; Admin on one withdrawn from finance
    final rowsEditable = (_office && (st == 'draft' || st == 'issued')) || (Auth.I.isAdmin && st == 'returned');
    final offsetsEditable = Auth.I.isAdmin && (st == 'draft' || st == 'issued') && !_busy;
    final notes = b.list('notes');
    return PageBody(onRefresh: _load, maxWidth: 1200, children: [
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(draft ? 'Draft #$_id' : _no, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text('${Fmt.date(b.str('start_date'))}  to  ${Fmt.date(b.str('end_date'))}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${_scopeText(b)}  ·  $cur', style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
              invoiceStatePill(st),
            ]),
            const SizedBox(height: 12),
            _stateNotice(b),
            if (replaces.isNotEmpty)
              NoticeBox(
                color: AppColors.neutral,
                icon: Icons.link_rounded,
                text: 'Re-issue of ${replaces.str('invoice_no', '#${replaces.str('eq_batch_id')}')} (withdrawn from finance). Shown here only, never printed.',
                action: TextButton(onPressed: () => _openInvoice(context, replaces.intv('eq_batch_id')), child: const Text('Open')),
              ),
            if (draft && b.flag('stale'))
              NoticeBox(
                color: AppColors.standby,
                icon: Icons.warning_amber_rounded,
                title: '${b.list('stale_reasons').length} change(s) since this draft was calculated',
                text: '${b.list('stale_reasons').take(6).map(_staleReason).join('\n')}\nRecalculate it before issuing.',
              ),
            if (_refreshError != null && st == 'issued')
              NoticeBox(
                color: AppColors.breakdown,
                icon: Icons.sync_problem_rounded,
                title: 'This invoice could not be brought up to date',
                text: _refreshError!.message,
              ),
            if (b.strOrNull('accept_blockers_reason') != null)
              NoticeBox(color: AppColors.standby, icon: Icons.rule_rounded, title: 'Created with open problems', text: b.str('accept_blockers_reason')),
            Wrap(spacing: 12, runSpacing: 12, children: [
              KpiTile(label: 'Machines', value: b.str('total_equipment'), icon: Icons.precision_manufacturing_rounded),
              KpiTile(label: 'Gross', value: Fmt.money2(b.strOrNull('total_gross'), cur), width: 200),
              KpiTile(label: 'Deductions', value: Fmt.money2(b.strOrNull('total_deductions'), cur), color: AppColors.breakdown, width: 200),
              KpiTile(label: 'Net', value: Fmt.money2(b.strOrNull('total_net'), cur), color: AppColors.navy, width: 220, icon: Icons.account_balance_wallet_rounded),
            ]),
            const SizedBox(height: 14),
            _Timeline(b: b),
            if (vendorInvoices.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Vendor invoices:', style: TextStyle(color: AppColors.muted)),
                for (final v in vendorInvoices)
                  ActionChip(
                    avatar: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: Text('${v.str('invoice_no')}  ·  ${Fmt.money2(v.strOrNull('amount'), cur)}'),
                    onPressed: () => _pdf('vendor', vendorId: v.intv('vendor_id'), suffix: v.str('invoice_no')),
                  ),
              ]),
            ],
            if (cancelled.isNotEmpty && st != 'cancelled' && st != 'replaced')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Cancelled numbers (never reused): ${cancelled.map((i) => i.str('invoice_no')).join(', ')}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (a.flag('issue'))
                FilledButton.icon(onPressed: _busy || b.flag('stale') ? null : _issue, icon: const Icon(Icons.verified_rounded), label: const Text('Issue')),
              if (a.flag('recalculate'))
                b.flag('stale')
                    ? FilledButton.icon(
                        onPressed: _busy ? null : _recalculate,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Recalculate'),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.standby, foregroundColor: AppColors.ink),
                      )
                    : OutlinedButton.icon(onPressed: _busy ? null : _recalculate, icon: const Icon(Icons.refresh_rounded), label: const Text('Recalculate')),
              if (a.flag('hand_over'))
                FilledButton.icon(
                  onPressed: _busy ? null : _handOver,
                  icon: const Icon(Icons.outbox_rounded),
                  label: const Text('Hand over to finance'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.working),
                ),
              if (a.flag('reissue'))
                FilledButton.icon(onPressed: _busy ? null : _reissue, icon: const Icon(Icons.autorenew_rounded), label: const Text('Re-issue (new number)')),
              if (a.flag('withdraw'))
                OutlinedButton.icon(onPressed: _busy ? null : _withdraw, icon: const Icon(Icons.undo_rounded), label: const Text('Withdraw from finance')),
              if (a.flag('notes'))
                OutlinedButton.icon(onPressed: _busy ? null : () => _newNote(), icon: const Icon(Icons.post_add_rounded), label: const Text('Debit / credit note')),
              if (a.flag('delete_draft'))
                OutlinedButton.icon(
                  onPressed: _busy ? null : _deleteDraft,
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.breakdown),
                  label: const Text('Delete draft', style: TextStyle(color: AppColors.breakdown)),
                ),
              if (a.flag('cancel'))
                OutlinedButton.icon(
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.block_rounded, color: AppColors.breakdown),
                  label: const Text('Cancel invoice', style: TextStyle(color: AppColors.breakdown)),
                ),
            ]),
          ]),
        ),
      ),
      if (_blockers != null && _blockers!.isNotEmpty) ...[
        const SizedBox(height: 14),
        _BlockersCard(
          blockers: _blockers!,
          title: 'Fix these rows first',
          onChanged: () async {
            setState(() => _blockers = null);
            await _load();
          },
        ),
      ],
      const SizedBox(height: 14),
      SectionCard(
        title: 'Documents',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: _vendorPdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Vendor invoice (PDF)')),
          FilledButton.tonalIcon(onPressed: () => _certificate(), icon: const Icon(Icons.grid_on_rounded), label: const Text('Excel certificate')),
          OutlinedButton.icon(onPressed: () => _pdf('summary'), icon: const Icon(Icons.summarize_rounded), label: const Text('Summary (PDF)')),
          OutlinedButton.icon(
            onPressed: () => _download('/equipment/payroll/batches/$_id/export.xlsx', '${draft ? 'draft-$_id' : _no.split(',').first.trim()}-data.xlsx'),
            icon: const Icon(Icons.table_view_rounded),
            label: const Text('Data (Excel)'),
          ),
          if (hasFuelDiff)
            OutlinedButton.icon(onPressed: () => _pdf('fueldiff', suffix: 'fuel-difference-$_id'), icon: const Icon(Icons.local_gas_station_rounded), label: const Text('Fuel difference statements')),
        ]),
      ),
      if (notes.isNotEmpty || a.flag('notes')) ...[
        const SizedBox(height: 14),
        SectionCard(
          title: 'Debit / credit notes of this invoice (${notes.length})',
          trailing: a.flag('notes') ? TextButton.icon(onPressed: () => _newNote(), icon: const Icon(Icons.add_rounded), label: const Text('New')) : null,
          child: notes.isEmpty
              ? const Text('None. A note is a separate document (DN- / CN-); it is listed with this invoice in the app only.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5))
              : Column(children: [
                  for (final n in notes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () async {
                        await _openNote(context, n.intv('note_id'));
                        _load();
                      },
                      leading: Icon(n.str('kind') == 'Credit' ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, color: AppColors.gold),
                      title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(n.str('note_no', 'Draft note'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        invoiceStatePill(noteState(n.str('status'))),
                        if (n.strOrNull('equipment_code') != null) Text(n.str('equipment_code'), style: const TextStyle(fontSize: 12.5)),
                      ]),
                      subtitle: Text(n.str('reason'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(noteAmountText(n), style: TextStyle(fontWeight: FontWeight.w700, color: n.str('kind') == 'Credit' ? AppColors.breakdown : AppColors.working)),
                    ),
                ]),
        ),
      ],
      const SizedBox(height: 14),
      SectionCard(
        title: 'Machines (${b.list('items').length})',
        child: Column(children: [
          for (final it in b.list('items'))
            _ItemTile(
              item: {...it, 'currency': cur},
              offsetKeys: _offsetKeysOf(b),
              onOffset: offsetsEditable ? _setOffset : null,
              offsetNote: offsetsEditable ? null : 'Only the Admin decides this, while the invoice is a draft or issued (not handed over).',
              onRows: it.str('billing_mode') == 'DNR' ? null : () => _rows(it, rowsEditable),
              onPdf: () => _pdf('machine', equipmentId: it.intv('equipment_id'), suffix: it.strOrNull('invoice_no') ?? 'machine-${it.str('equipment_code')}'),
              onExcel: () => _certificate(vendorId: it.intv('vendor_id'), equipmentId: it.intv('equipment_id'), code: it.str('equipment_code')),
              onFuelPdf: (it.dblOrNull('fuel_difference') ?? 0) == 0
                  ? null
                  : () => _pdf('fueldiff', equipmentId: it.intv('equipment_id'), suffix: it.strOrNull('fuel_invoice_no') ?? 'fuel-${it.str('equipment_code')}'),
              onNote: a.flag('notes') ? () => _newNote(item: it) : null,
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
    final st = b.str('state');
    Widget step(String label, String? at, bool done, {String? by, Color color = AppColors.working}) => Expanded(
          child: Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? color : AppColors.neutral, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: done ? AppColors.ink : AppColors.muted)),
                Text(at == null ? '-' : '${Fmt.date(at)}${by == null ? '' : '  ·  $by'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
          ]),
        );
    return Row(children: [
      step('Draft', b.strOrNull('generated_at'), true, by: b.strOrNull('generated_by'), color: AppColors.standby),
      step('Issued', b.strOrNull('finalized_at'), b.flag('is_finalized'), color: AppColors.info),
      step('Handed over', b.strOrNull('handed_over_at'), b.strOrNull('handed_over_at') != null),
      if (st == 'returned' || st == 'replaced' || b.strOrNull('returned_at') != null)
        step('Withdrawn', b.strOrNull('returned_at'), b.strOrNull('returned_at') != null, color: AppColors.edited)
      else if (st == 'cancelled')
        step('Cancelled', b.strOrNull('voided_at'), true, color: AppColors.breakdown),
    ]);
  }
}

class _SnapshotSheet extends StatefulWidget {
  const _SnapshotSheet({required this.batchId, required this.item, this.editable = false});
  final int batchId;
  final Json item;
  /// draft batch: a row opens with its office actions (edit, void); the batch then turns stale
  final bool editable;
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

  Future<void> _openRow(Json r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AttendanceDetailSheet(id: r.intv('eq_attendance_id')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.item.machineName} at ${widget.item.str('site_code')}: invoiced days', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (widget.editable)
                const Text('Tap a day to open it and edit it. A draft then asks to "Recalculate"; an issued invoice is brought up to date by itself (same number).',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
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
                              DataRow(
                                  onSelectChanged: widget.editable ? (_) => _openRow(r) : null,
                                  cells: [
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
    case 'MONTHLY_TERMS_CHANGED':
      return 'Month terms changed (${r.str('item')}): working days / hourly price ${r.str('was')} -> ${r.str('now')}';
    default:
      return r.str('message', r.str('code'));
  }
}