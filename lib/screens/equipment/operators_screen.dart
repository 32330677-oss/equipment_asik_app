import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Licence badge: expired / expires within 30 days / valid.
Widget licenceBadge(Json o) {
  final exp = o.strOrNull('license_expiry');
  if (exp == null) return const Pill('No licence date', color: AppColors.neutral);
  final d = Fmt.parse(exp);
  final days = d == null ? 999 : d.difference(DateTime.now()).inDays;
  if (o.flag('license_expired') || days < 0) return Pill('Expired ${Fmt.date(exp)}', color: AppColors.breakdown, icon: Icons.error_rounded);
  if (days <= 30) return Pill('Expires ${Fmt.date(exp)}', color: AppColors.standby, icon: Icons.schedule_rounded);
  return Pill('Valid to ${Fmt.date(exp)}', color: AppColors.working);
}

/// Machine drivers supplied by the vendors.
class OperatorsScreen extends StatefulWidget {
  const OperatorsScreen({super.key});
  @override
  State<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends State<OperatorsScreen> {
  final _s = Loadable<List<Json>>();
  final _q = TextEditingController();
  PickOption? _vendor;
  String? _status = 'Active';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/equipment/operators', query: {'q': _q.text.trim(), 'vendor_id': _vendor?.value, 'status': _status});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _toggle(Json o) async {
    final next = o.str('status') == 'Active' ? 'Inactive' : 'Active';
    final ok = await confirmDialog(context, '$next ${o.str('full_name')}?',
        next == 'Inactive' ? 'The operator can no longer be chosen at check-in and is removed as default operator.' : 'The operator can be chosen again.',
        confirm: next == 'Inactive' ? 'Deactivate' : 'Activate', danger: next == 'Inactive');
    if (!ok) return;
    try {
      await Api.I.patch('/equipment/operators/${o.intv('operator_id')}/status', {'status': next});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _s.data ?? <Json>[];
    final admin = Auth.I.isAdmin;
    final expiring = rows.where((o) {
      final d = Fmt.parse(o.strOrNull('license_expiry'));
      return d != null && d.difference(DateTime.now()).inDays <= 30;
    }).length;
    return PageBody(onRefresh: _load, children: [
      PageHeader(title: 'Operators', subtitle: 'Drivers supplied by the vendors with their machines', actions: [
        SizedBox(
          width: 200,
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(labelText: 'Search name, licence', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            onSubmitted: (_) => _load(),
          ),
        ),
        PickerField(label: 'Vendor', width: 200, valueLabel: _vendor?.label, load: () => Lookups.vendors(), onChanged: (v) { _vendor = v; _load(); }),
        Dropdown<String?>(label: 'Status', value: _status, width: 130, items: const [
          DropdownMenuItem(value: null, child: Text('All')),
          DropdownMenuItem(value: 'Active', child: Text('Active')),
          DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
        ], onChanged: (v) { _status = v; _load(); }),
        if (admin)
          FilledButton.icon(
            onPressed: () async {
              final r = await showOperatorDialog(context, vendor: _vendor);
              if (r != null) _load();
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('New operator'),
          ),
      ]),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(label: 'Operators', value: '${rows.length}', icon: Icons.badge_rounded),
        KpiTile(label: 'Licence expired / < 30 days', value: '$expiring', color: expiring == 0 ? AppColors.working : AppColors.standby, icon: Icons.assignment_late_rounded, width: 230),
      ]),
      const SizedBox(height: 14),
      if (_s.loading && _s.data == null)
        const LoadingView()
      else if (_s.error != null)
        ErrorView(error: _s.error!, onRetry: _load)
      else
        TableCard(
          empty: 'No operator.',
          columns: const [
            DataColumn(label: Text('Name')), DataColumn(label: Text('Vendor')), DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Licence')), DataColumn(label: Text('Licence validity')), DataColumn(label: Text('Status')), DataColumn(label: Text('')),
          ],
          rows: [
            for (final o in rows)
              DataRow(cells: [
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 15, backgroundColor: AppColors.navy.withValues(alpha: 0.1), child: Text(o.str('full_name').isEmpty ? '?' : o.str('full_name')[0].toUpperCase(), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 13))),
                  const SizedBox(width: 10),
                  Text(o.str('full_name'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ])),
                DataCell(Text(o.str('vendor_name'))),
                DataCell(Text(o.str('phone_number', '-'))),
                DataCell(Text(o.str('license_number', '-'))),
                DataCell(licenceBadge(o)),
                DataCell(Pill(o.str('status'), color: o.str('status') == 'Active' ? AppColors.working : AppColors.neutral)),
                DataCell(admin
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () async {
                            final r = await showOperatorDialog(context, operator: o);
                            if (r != null) _load();
                          },
                        ),
                        IconButton(
                          tooltip: o.str('status') == 'Active' ? 'Deactivate' : 'Activate',
                          icon: Icon(o.str('status') == 'Active' ? Icons.person_off_rounded : Icons.person_rounded, size: 18),
                          onPressed: () => _toggle(o),
                        ),
                      ])
                    : const SizedBox()),
              ]),
          ],
        ),
    ]);
  }
}

/// Create or edit an operator. Returns the saved operator.
Future<Json?> showOperatorDialog(BuildContext context, {Json? operator, PickOption? vendor}) {
  final o = operator;
  var v = o == null ? vendor : PickOption(o.intv('vendor_id'), o.str('vendor_name'));
  var expiry = o?.strOrNull('license_expiry');
  final name = TextEditingController(text: o?.str('full_name'));
  final phone = TextEditingController(text: o?.str('phone_number'));
  final nid = TextEditingController(text: o?.str('national_id'));
  final lic = TextEditingController(text: o?.str('license_number'));
  final notes = TextEditingController(text: o?.str('notes'));
  return showFormDialog<Json>(
    context,
    title: o == null ? 'New operator' : 'Edit ${o.str('full_name')}',
    onSave: () async {
      if (v == null) throw ApiException(null, 'VALIDATION', 'Choose the vendor.');
      final body = {
        'vendor_id': v!.value, 'full_name': name.text.trim(), 'phone_number': textOrNull(phone), 'national_id': textOrNull(nid),
        'license_number': textOrNull(lic), 'license_expiry': expiry, 'notes': textOrNull(notes),
      }..removeWhere((k, x) => x == null);
      return asJson(o == null ? await Api.I.post('/equipment/operators', body) : await Api.I.put('/equipment/operators/${o.intv('operator_id')}', body));
    },
    body: (ctx, set) => FormGrid(children: [
      PickerField(label: 'Vendor *', valueLabel: v?.label, icon: Icons.business_rounded, clearable: false, load: () => Lookups.vendors(activeOnly: true), onChanged: (x) => set(() => v = x)),
      textField(name, 'Full name', required: true),
      textField(phone, 'Phone'),
      textField(nid, 'National ID'),
      textField(lic, 'Licence number'),
      DateField(label: 'Licence expiry', value: expiry, clearable: true, onChanged: (x) => set(() => expiry = x)),
      textField(notes, 'Notes', maxLines: 2),
    ]),
  );
}
