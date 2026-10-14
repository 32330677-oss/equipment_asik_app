import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/pdf_view.dart';
import '../../widgets/ui.dart';
import 'payroll_screen.dart' show BatchScreen;

// Invoices and finance (decisions of 13-14 Oct 2026): states of an invoice, hand-over to finance, withdrawal from
// finance (signed acknowledgement) and debit / credit notes. The app records no payment: finance pays outside it.

/// Labels of the states the server returns (eqLock.stateOf; notes use the same keys).
const invoiceStateLabels = {
  'draft': 'Draft',
  'issued': 'Issued',
  'handed_over': 'Handed over',
  'returned': 'Withdrawn from finance',
  'cancelled': 'Cancelled',
  'superseded': 'Old calculation',
  'replaced': 'Re-issued (new number)',
};

Color invoiceStateColor(String s) => switch (s) {
      'draft' => AppColors.standby,
      'issued' => AppColors.info,
      'handed_over' => AppColors.working,
      'returned' => AppColors.edited,
      'cancelled' => AppColors.breakdown,
      _ => AppColors.neutral,
    };

IconData invoiceStateIcon(String s) => switch (s) {
      'draft' => Icons.edit_note_rounded,
      'issued' => Icons.receipt_long_rounded,
      'handed_over' => Icons.lock_rounded,
      'returned' => Icons.undo_rounded,
      'cancelled' => Icons.block_rounded,
      _ => Icons.history_rounded,
    };

Pill invoiceStatePill(String s) => Pill(invoiceStateLabels[s] ?? s, color: invoiceStateColor(s), icon: invoiceStateIcon(s));

/// eq_notes.status -> the same keys as an invoice.
String noteState(String status) =>
    const {'Draft': 'draft', 'Issued': 'issued', 'HandedOver': 'handed_over', 'Returned': 'returned', 'Cancelled': 'cancelled'}[status] ?? status.toLowerCase();

/// "Debit note" / "Credit note".
String noteKindText(String kind) => kind == 'Credit' ? 'Credit note' : 'Debit note';

/// Signed amount of a note: a credit note lowers what the vendor gets.
String noteAmountText(Json n) => '${n.str('kind') == 'Credit' ? '−' : '+'}${Fmt.money2(n.strOrNull('amount'), n.str('currency'))}';

void openHandoverPdf(BuildContext context, int id, String no) => PdfViewScreen.open(context,
    title: 'Hand-over sheet $no', fileName: '$no.pdf', load: () => Api.I.getBytes('/equipment/payroll/handovers/$id/pdf'));

void openWithdrawalPdf(BuildContext context, int id, String no) => PdfViewScreen.open(context,
    title: 'Withdrawal acknowledgement $no', fileName: '$no.pdf', load: () => Api.I.getBytes('/equipment/payroll/withdrawals/$id/pdf'));

void openNotePdf(BuildContext context, Json n) => PdfViewScreen.open(context,
    title: '${noteKindText(n.str('kind'))} ${n.str('note_no', 'draft')}',
    fileName: '${n.str('note_no', 'note-${n.str('note_id')}')}.pdf',
    load: () => Api.I.getBytes('/equipment/payroll/notes/${n.intv('note_id')}/pdf'));

// =================================================================== withdrawal from finance
/// The signed acknowledgement of a withdrawal: why, who in finance gives it back, when, and whether it was paid.
/// Returns the body for POST .../withdraw, or null when cancelled.
Future<Json?> withdrawDialog(BuildContext context, {required String title, String? currency}) {
  final reason = TextEditingController();
  final person = TextEditingController();
  final paidAmount = TextEditingController();
  var on = Fmt.today();
  var paid = false;
  return showFormDialog<Json>(
    context,
    title: title,
    width: 520,
    saveLabel: 'Withdraw',
    onSave: () async {
      final r = reason.text.trim();
      final p = person.text.trim();
      if (r.length < 5) throw ApiException(null, 'VALIDATION', 'Write why it is withdrawn (at least 5 characters).');
      if (p.length < 2) throw ApiException(null, 'VALIDATION', 'Write who in finance gives it back.');
      final amount = numOrNull(paidAmount);
      if (paid && amount != null && amount < 0) throw ApiException(null, 'VALIDATION', 'The amount paid cannot be negative.');
      return <String, dynamic>{
        'reason': r,
        'finance_person': p,
        'withdrawn_on': on,
        'was_paid': paid,
        if (paid && amount != null) 'paid_amount': amount,
      };
    },
    body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('A withdrawal acknowledgement (WD-...) is printed to be signed by finance. No scan is needed. '
          'Afterwards the Admin can change the invoice and re-issue it with a new number, cancel it, or hand it over again unchanged.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      const SizedBox(height: 14),
      textField(reason, 'Why is it withdrawn?', required: true, maxLines: 3),
      const SizedBox(height: 12),
      FormGrid(children: [
        textField(person, 'Finance person who gives it back', required: true),
        DateField(label: 'Date', value: on, last: Fmt.today(), onChanged: (v) => set(() => on = v ?? on)),
      ]),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: paid,
        onChanged: (v) => set(() => paid = v ?? false),
        title: const Text('Finance had already paid it (in full or in part)'),
      ),
      if (paid) textField(paidAmount, 'Amount already paid${currency == null ? '' : ' ($currency)'} (optional)', number: true),
    ]),
  );
}

// =================================================================== debit / credit notes
/// Create (note == null) or change a debit / credit note. Presets come from the invoice it is made from.
/// Returns the saved note.
Future<Json?> editNote(BuildContext context, {Json? note, int? vendorId, String? vendorName, int? refBatchId, String? refLabel, String? currency, int? equipmentId, String? equipmentLabel}) {
  final n = note ?? <String, dynamic>{};
  var kind = n.str('kind', 'Credit');
  PickOption? vendor = n.intOrNull('vendor_id') != null
      ? PickOption(n.intv('vendor_id'), n.str('vendor_name'))
      : (vendorId == null ? null : PickOption(vendorId, vendorName ?? '#$vendorId'));
  PickOption? machine = n.intOrNull('equipment_id') != null
      ? PickOption(n.intv('equipment_id'), n.machineName)
      : (equipmentId == null ? null : PickOption(equipmentId, equipmentLabel ?? '#$equipmentId'));
  PickOption? ref = n.intOrNull('ref_batch_id') != null
      ? PickOption(n.intv('ref_batch_id'), n.obj('ref_invoice').str('invoice_no', 'Invoice #${n.str('ref_batch_id')}'))
      : (refBatchId == null ? null : PickOption(refBatchId, refLabel ?? 'Invoice #$refBatchId'));
  var cur = n.strOrNull('currency') ?? currency ?? 'USD';
  final amount = TextEditingController(text: n.strOrNull('amount') ?? '');
  final reason = TextEditingController(text: n.strOrNull('reason') ?? '');
  var date = n.strOrNull('note_date') == null ? Fmt.today() : n.str('note_date').substring(0, 10);
  String? from = n.strOrNull('period_from')?.substring(0, 10);
  String? to = n.strOrNull('period_to')?.substring(0, 10);
  final editing = note != null;
  return showFormDialog<Json>(
    context,
    title: editing ? 'Change ${noteKindText(kind).toLowerCase()} ${n.str('note_no', '(draft)')}' : 'New debit / credit note',
    width: 600,
    saveLabel: editing ? 'Save' : 'Create draft',
    onSave: () async {
      if (vendor == null) throw ApiException(null, 'VALIDATION', 'Choose the vendor.');
      final a = numOrNull(amount);
      if (a == null || a <= 0) throw ApiException(null, 'VALIDATION', 'Type the amount (always positive: the kind gives the direction).');
      if (reason.text.trim().length < 5) throw ApiException(null, 'VALIDATION', 'Write the reason (printed on the note).');
      final body = <String, dynamic>{
        'kind': kind,
        'vendor_id': vendor!.value,
        'equipment_id': machine?.value,
        'currency': cur,
        'amount': a,
        'reason': reason.text.trim(),
        'note_date': date,
        'period_from': from,
        'period_to': to,
        'ref_batch_id': ref?.value,
      };
      if (!editing) body.removeWhere((k, v) => v == null);
      return asJson(editing ? await Api.I.put('/equipment/payroll/notes/${n.intv('note_id')}', body) : await Api.I.post('/equipment/payroll/notes', body));
    },
    body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Debit note: the vendor gets MORE. Credit note: the vendor gets LESS. A new note is a draft without a number; '
          'the Admin issues it (DN- / CN-) and hands it over to finance like an invoice. The link to an invoice is shown in the app only, never printed.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Debit', icon: Icon(Icons.add_circle_outline_rounded), label: Text('Debit note (+)')),
          ButtonSegment(value: 'Credit', icon: Icon(Icons.remove_circle_outline_rounded), label: Text('Credit note (−)')),
        ],
        selected: {kind},
        onSelectionChanged: (s) => set(() => kind = s.first),
      ),
      const SizedBox(height: 12),
      FormGrid(children: [
        PickerField(
          label: 'Vendor *',
          icon: Icons.business_rounded,
          valueLabel: vendor?.label,
          enabled: !editing,
          load: () => Lookups.vendors(),
          onChanged: (v) => set(() {
            vendor = v;
            machine = null;
            ref = null;
          }),
        ),
        PickerField(
          label: 'Machine (empty = the vendor in general)',
          icon: Icons.precision_manufacturing_rounded,
          valueLabel: machine?.label,
          enabled: vendor != null,
          load: () => Lookups.machines(vendorId: vendor?.value as int?),
          onChanged: (v) => set(() => machine = v),
        ),
        textField(amount, 'Amount', number: true, required: true),
        Dropdown<String>(label: 'Currency', value: cur, width: null, items: const [
          DropdownMenuItem(value: 'USD', child: Text('USD')),
          DropdownMenuItem(value: 'SYP', child: Text('SYP')),
          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
        ], onChanged: (v) => set(() => cur = v ?? cur)),
        DateField(label: 'Note date', value: date, onChanged: (v) => set(() => date = v ?? date)),
        PickerField(
          label: 'Belongs to invoice (optional, app only)',
          icon: Icons.link_rounded,
          valueLabel: ref?.label,
          enabled: vendor != null,
          load: () async {
            final rows = await Api.I.getList('/equipment/payroll/batches', query: {'vendor_id': vendor?.value, 'state': 'Active'});
            return [
              for (final b in rows.where((b) => b.flag('is_finalized')))
                PickOption(b.intv('eq_batch_id'), b.str('vendor_invoice_no', 'Invoice #${b.str('eq_batch_id')}'),
                    '${Fmt.date(b.str('start_date'))} – ${Fmt.date(b.str('end_date'))}  ·  ${invoiceStateLabels[b.str('state')] ?? b.str('state')}'),
            ];
          },
          onChanged: (v) => set(() => ref = v),
        ),
        DateField(label: 'Period from (optional)', value: from, clearable: true, onChanged: (v) => set(() => from = v)),
        DateField(label: 'Period to (optional)', value: to, clearable: true, first: from, onChanged: (v) => set(() => to = v)),
      ]),
      const SizedBox(height: 12),
      textField(reason, 'Reason (printed on the note)', required: true, maxLines: 3),
    ]),
  );
}

/// One debit / credit note: details, PDF and what the current role may do (the server says it in `actions`).
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.id});
  final int id;
  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  Json? _n;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = await Api.I.getObj('/equipment/payroll/notes/${widget.id}');
      if (mounted) setState(() { _n = n; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<dynamic> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (mounted) showSnack(context, ok);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final r = await editNote(context, note: _n);
    if (r != null) {
      if (mounted) showSnack(context, 'Note saved.');
      await _load();
    }
  }

  Future<void> _issue() async {
    final ok = await confirmDialog(context, 'Issue this ${noteKindText(_n!.str('kind')).toLowerCase()}?',
        'It gets its official number (${_n!.str('kind') == 'Credit' ? 'CN' : 'DN'}-...), never reused.', confirm: 'Issue');
    if (ok) _act(() => Api.I.patch('/equipment/payroll/notes/${widget.id}/issue'), 'Note issued.');
  }

  Future<void> _cancel() async {
    final draft = _n!.str('status') == 'Draft';
    if (draft) {
      final ok = await confirmDialog(context, 'Delete this draft note?', 'It has no number yet.', confirm: 'Delete', danger: true);
      if (ok) _act(() => Api.I.patch('/equipment/payroll/notes/${widget.id}/cancel', {}), 'Draft deleted.');
      return;
    }
    final reason = await promptText(context, 'Cancel note ${_n!.str('note_no')}?', label: 'Why?', minLength: 3, confirm: 'Cancel note',
        help: 'Its number stays cancelled and is never reused.');
    if (reason != null) _act(() => Api.I.patch('/equipment/payroll/notes/${widget.id}/cancel', {'reason': reason}), 'Note cancelled.');
  }

  Future<void> _withdraw() async {
    final body = await withdrawDialog(context, title: 'Withdraw ${_n!.str('note_no')} from finance', currency: _n!.str('currency'));
    if (body == null) return;
    setState(() => _busy = true);
    try {
      final r = await Api.I.request('POST', '/equipment/payroll/notes/${widget.id}/withdraw', body: body);
      await _load();
      if (!mounted) return;
      final wid = asJson(r).intOrNull('withdrawal_id');
      showSnack(context, 'Withdrawn from finance.');
      if (wid != null) openWithdrawalPdf(context, wid, _n?.str('withdrawal_no', 'withdrawal') ?? 'withdrawal');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    return Scaffold(
      appBar: AppBar(title: Text(n == null ? 'Note' : '${noteKindText(n.str('kind'))} ${n.str('note_no', '(draft)')}')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : n == null
              ? const LoadingView()
              : PageBody(onRefresh: _load, maxWidth: 900, children: [
                  const SizedBox(height: 16),
                  _body(n),
                ]),
    );
  }

  Widget _body(Json n) {
    final a = n.obj('actions');
    final st = noteState(n.str('status'));
    final ref = n.obj('ref_invoice');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.str('note_no', 'Draft note'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('${noteKindText(n.str('kind'))}  ·  ${n.str('vendor_name')}${n.strOrNull('equipment_code') == null ? '  ·  vendor in general' : '  ·  ${n.machineName}'}',
                    style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
            invoiceStatePill(st),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            KpiTile(label: 'Amount', value: noteAmountText(n), color: n.str('kind') == 'Credit' ? AppColors.breakdown : AppColors.working, width: 220),
            KpiTile(label: 'Date', value: Fmt.date(n.str('note_date')), width: 170),
            if (n.strOrNull('period_from') != null)
              KpiTile(label: 'Period', value: '${Fmt.date(n.str('period_from'))} – ${Fmt.date(n.strOrNull('period_to') ?? n.str('period_from'))}', width: 260),
          ]),
          const SizedBox(height: 12),
          InfoRow('Reason', n.str('reason')),
          InfoRow('Created', '${Fmt.date(n.str('created_at'))}  ·  ${n.str('created_by')}'),
          if (n.strOrNull('issued_at') != null) InfoRow('Issued', '${Fmt.date(n.str('issued_at'))}  ·  ${n.str('issued_by')}'),
          if (n.strOrNull('handover_no') != null) InfoRow('Hand-over', n.str('handover_no')),
          if (n.strOrNull('withdrawal_no') != null) InfoRow('Withdrawn', n.str('withdrawal_no')),
          if (n.strOrNull('cancel_reason') != null) InfoRow('Cancelled', n.str('cancel_reason')),
          if (ref.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NoticeBox(
                icon: Icons.link_rounded,
                title: 'Belongs to invoice ${ref.str('invoice_no', '#${ref.str('eq_batch_id')}')} (shown in the app only)',
                text: '${Fmt.date(ref.str('start_date'))} – ${Fmt.date(ref.str('end_date'))}  ·  ${invoiceStateLabels[ref.str('state')] ?? ref.str('state')}',
                action: TextButton(
                  onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => BatchScreen(id: ref.intv('eq_batch_id')))),
                  child: const Text('Open'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => openNotePdf(context, n), icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF')),
            if (a.flag('edit')) OutlinedButton.icon(onPressed: _busy ? null : _edit, icon: const Icon(Icons.edit_rounded), label: const Text('Change')),
            if (a.flag('issue')) FilledButton.icon(onPressed: _busy ? null : _issue, icon: const Icon(Icons.verified_rounded), label: const Text('Issue')),
            if (a.flag('hand_over'))
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => HandoverScreen(noteIds: {widget.id})));
                        _load();
                      },
                icon: const Icon(Icons.outbox_rounded),
                label: const Text('Hand over to finance'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.working),
              ),
            if (a.flag('withdraw')) OutlinedButton.icon(onPressed: _busy ? null : _withdraw, icon: const Icon(Icons.undo_rounded), label: const Text('Withdraw from finance')),
            if (a.flag('cancel'))
              OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                icon: const Icon(Icons.block_rounded, color: AppColors.breakdown),
                label: Text(n.str('status') == 'Draft' ? 'Delete draft' : 'Cancel note', style: const TextStyle(color: AppColors.breakdown)),
              ),
          ]),
        ]),
      ),
    );
  }
}

// =================================================================== hand-over to finance
/// Admin: choose issued invoices and notes (and ones withdrawn and unchanged), who receives them and when; a numbered
/// hand-over sheet (HO-...) is printed to be signed. From then on they are locked for everybody.
class HandoverScreen extends StatefulWidget {
  const HandoverScreen({super.key, this.batchIds = const {}, this.noteIds = const {}});
  final Set<int> batchIds;
  final Set<int> noteIds;
  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends State<HandoverScreen> {
  List<Json>? _batches;
  List<Json>? _notes;
  Object? _error;
  final Set<int> _b = {};
  final Set<int> _n = {};
  final _receiver = TextEditingController();
  final _note = TextEditingController();
  var _on = Fmt.today();
  bool _busy = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _b.addAll(widget.batchIds);
    _n.addAll(widget.noteIds);
    _load();
  }

  @override
  void dispose() {
    _receiver.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        Api.I.getList('/equipment/payroll/batches', query: {'state': 'Issued'}),
        Api.I.getList('/equipment/payroll/batches', query: {'state': 'Returned'}),
        Api.I.getList('/equipment/payroll/notes', query: {'status': 'Issued'}),
        Api.I.getList('/equipment/payroll/notes', query: {'status': 'Returned'}),
      ]);
      if (mounted) setState(() { _batches = [...r[0], ...r[1]]; _notes = [...r[2], ...r[3]]; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool _match(String text) => _filter.isEmpty || text.toLowerCase().contains(_filter.toLowerCase());

  Future<void> _submit() async {
    if (_b.isEmpty && _n.isEmpty) {
      showSnack(context, 'Choose at least one invoice or note.', error: true);
      return;
    }
    if (_receiver.text.trim().length < 2) {
      showSnack(context, 'Write who receives them in finance.', error: true);
      return;
    }
    final ok = await confirmDialog(context, 'Hand ${_b.length + _n.length} document(s) over to finance?',
        'They are locked for everybody afterwards. To change one later, the Admin withdraws it from finance with a signed acknowledgement.',
        confirm: 'Hand over');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final h = asJson(await Api.I.post('/equipment/payroll/handovers', {
        'batch_ids': _b.toList(),
        'note_ids': _n.toList(),
        'handed_on': _on,
        'receiver_name': _receiver.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      }));
      if (!mounted) return;
      showSnack(context, 'Handed over: ${h.str('handover_no')}');
      Navigator.pop(context);
      openHandoverPdf(context, h.intv('handover_id'), h.str('handover_no'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'ROWS_NOT_APPROVED' || e.code == 'SCAN_MISSING' || e.code == 'REISSUE_FIRST') {
        final id = e.details?.intOrNull('eq_batch_id');
        await confirmDialog(context, 'Cannot hand over yet', '${e.message}${id == null ? '' : '\n\nOpen the invoice to fix it.'}', confirm: 'OK');
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
    final batches = (_batches ?? <Json>[]).where((b) => _match('${b.str('vendor_invoice_no')} ${b.str('scope_vendor_name')} ${b.str('eq_batch_id')}')).toList();
    final notes = (_notes ?? <Json>[]).where((n) => _match('${n.str('note_no')} ${n.str('vendor_name')} ${n.str('equipment_code')}')).toList();
    final totals = <String, double>{};
    for (final b in (_batches ?? <Json>[]).where((b) => _b.contains(b.intv('eq_batch_id')))) {
      totals[b.str('currency')] = (totals[b.str('currency')] ?? 0) + b.dbl('total_net');
    }
    for (final n in (_notes ?? <Json>[]).where((n) => _n.contains(n.intv('note_id')))) {
      totals[n.str('currency')] = (totals[n.str('currency')] ?? 0) + (n.str('kind') == 'Credit' ? -n.dbl('amount') : n.dbl('amount'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Hand over to finance')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _batches == null
              ? const LoadingView()
              : PageBody(maxWidth: 1000, children: [
                  const SizedBox(height: 16),
                  const NoticeBox(
                    icon: Icons.outbox_rounded,
                    text: 'Tick the invoices and notes you give to finance now. A hand-over sheet (HO-...) is printed for signature; '
                        'no scan is needed. An issued invoice is brought up to date first (same number).',
                  ),
                  SectionCard(
                    title: '1. Who receives them',
                    child: FormGrid(children: [
                      textField(_receiver, 'Received by (finance)', required: true),
                      DateField(label: 'Date', value: _on, last: Fmt.today(), onChanged: (v) => setState(() => _on = v ?? _on)),
                      textField(_note, 'Note (optional, printed)'),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: '2. Documents',
                    trailing: SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded, size: 20), hintText: 'Number or vendor'),
                        onChanged: (v) => setState(() => _filter = v.trim()),
                      ),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (batches.isEmpty && notes.isEmpty) const EmptyView(text: 'Nothing issued is waiting to be handed over.', icon: Icons.inbox_rounded),
                      for (final b in batches)
                        CheckboxListTile(
                          value: _b.contains(b.intv('eq_batch_id')),
                          onChanged: (v) => setState(() => v == true ? _b.add(b.intv('eq_batch_id')) : _b.remove(b.intv('eq_batch_id'))),
                          secondary: Icon(invoiceStateIcon(b.str('state')), color: invoiceStateColor(b.str('state'))),
                          title: Text('${b.str('vendor_invoice_no', 'Invoice #${b.str('eq_batch_id')}')}  ·  ${b.str('scope_vendor_name', 'several vendors')}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${Fmt.date(b.str('start_date'))} – ${Fmt.date(b.str('end_date'))}  ·  ${Fmt.money2(b.strOrNull('total_net'), b.str('currency'))}'
                              '${b.str('state') == 'returned' ? '  ·  withdrawn earlier, unchanged' : ''}'),
                        ),
                      for (final n in notes)
                        CheckboxListTile(
                          value: _n.contains(n.intv('note_id')),
                          onChanged: (v) => setState(() => v == true ? _n.add(n.intv('note_id')) : _n.remove(n.intv('note_id'))),
                          secondary: Icon(n.str('kind') == 'Credit' ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, color: AppColors.gold),
                          title: Text('${n.str('note_no')}  ·  ${n.str('vendor_name')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${noteKindText(n.str('kind'))}${n.strOrNull('equipment_code') == null ? '' : '  ·  ${n.str('equipment_code')}'}  ·  ${noteAmountText(n)}'),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 12, children: [
                    Text('${_b.length + _n.length} chosen${totals.isEmpty ? '' : '  ·  ${totals.entries.map((e) => Fmt.money(e.value, e.key)).join(' + ')}'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    FilledButton.icon(
                      onPressed: _busy || !Auth.I.isAdmin ? null : _submit,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.outbox_rounded),
                      label: const Text('Hand over and print the sheet'),
                    ),
                  ]),
                ]),
    );
  }
}

/// Hand-over sheets already made (to print them again).
class HandoversScreen extends StatefulWidget {
  const HandoversScreen({super.key});
  @override
  State<HandoversScreen> createState() => _HandoversScreenState();
}

class _HandoversScreenState extends State<HandoversScreen> {
  final _s = Loadable<List<Json>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/payroll/handovers');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Hand-over sheets')),
      body: _s.error != null
          ? ErrorView(error: _s.error!, onRetry: _load)
          : _s.loading && _s.data == null
              ? const LoadingView()
              : PageBody(onRefresh: _load, maxWidth: 1000, children: [
                  const SizedBox(height: 16),
                  TableCard(
                    empty: 'Nothing handed over to finance yet.',
                    columns: const [
                      DataColumn(label: Text('Number')), DataColumn(label: Text('Date')), DataColumn(label: Text('Received by')),
                      DataColumn(label: Text('Documents'), numeric: true), DataColumn(label: Text('By')), DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final h in rows)
                        DataRow(cells: [
                          DataCell(Text(h.str('handover_no'), style: const TextStyle(fontWeight: FontWeight.w700))),
                          DataCell(Text(Fmt.date(h.str('handed_on')))),
                          DataCell(Text(h.str('receiver_name'))),
                          DataCell(Text(h.str('documents'))),
                          DataCell(Text(h.str('by_name'), style: const TextStyle(color: AppColors.muted))),
                          DataCell(IconButton(
                            tooltip: 'Print the sheet',
                            onPressed: () => openHandoverPdf(context, h.intv('handover_id'), h.str('handover_no')),
                            icon: const Icon(Icons.picture_as_pdf_rounded),
                          )),
                        ]),
                    ],
                  ),
                ]),
    );
  }
}
