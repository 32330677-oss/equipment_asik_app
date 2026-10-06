import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class SitesScreen extends StatefulWidget {
  const SitesScreen({super.key});
  @override
  State<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends State<SitesScreen> {
  final _s = Loadable<List<Json>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/sites');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _edit([Json? site]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _SiteDialog(site: site));
    if (ok == true) _load();
  }

  Future<void> _status(Json site, String status) async {
    final reason = await promptText(context, 'Set ${site.str('site_code')} to $status', label: 'Reason', required: false);
    if (reason == null) return;
    try {
      await Api.I.patch('/sites/${site.intv('site_id')}/status', {'status': status, 'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = Auth.I.isAdmin;
    final sites = _s.data ?? <Json>[];
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Sites', subtitle: 'Construction sites and who supervises them', actions: [
          if (admin) FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_location_alt_rounded), label: const Text('New site')),
        ]),
        if (_s.loading && _s.data == null) const LoadingView()
        else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
        else if (sites.isEmpty) const Card(child: EmptyView(text: 'No sites yet. Create the first construction site.', icon: Icons.location_city_rounded))
        else Wrap(spacing: 14, runSpacing: 14, children: [
          for (final s in sites)
            SizedBox(
              width: 340,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => showModalBottomSheet<void>(
                    context: context, isScrollControlled: true, showDragHandle: true,
                    builder: (_) => SupervisorsSheet(site: s, editable: admin),
                  ).then((_) => _load()),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(8)),
                          child: Text(s.str('site_code'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(s.str('site_name'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), overflow: TextOverflow.ellipsis)),
                        if (admin)
                          PopupMenuButton<String>(
                            onSelected: (a) => a == 'edit' ? _edit(s) : _status(s, a),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              if (s.str('status') != 'Active') const PopupMenuItem(value: 'Active', child: Text('Set Active')),
                              if (s.str('status') != 'Suspended') const PopupMenuItem(value: 'Suspended', child: Text('Suspend')),
                              if (s.str('status') != 'Completed') const PopupMenuItem(value: 'Completed', child: Text('Mark completed')),
                            ],
                          ),
                      ]),
                      const SizedBox(height: 10),
                      if (s.strOrNull('project_name') != null) kv('Project', s.str('project_name')),
                      if (s.strOrNull('location') != null) kv('Location', s.str('location')),
                      kv('Shifts', s.flag('has_night_shift') ? 'Day + Night' : 'Day'),
                      if (s.strOrNull('day_shift_start') != null) kv('Day starts', s.str('day_shift_start').substring(0, 5)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Pill(s.str('status'), color: s.str('status') == 'Active' ? AppColors.working : AppColors.neutral),
                        const SizedBox(width: 8),
                        Pill('${s.intv('deployed_machines')} machines', color: AppColors.info, icon: Icons.precision_manufacturing_rounded),
                        const Spacer(),
                        const Text('Supervisors', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12)),
                        const Icon(Icons.chevron_right, color: AppColors.navy, size: 18),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({this.site});
  final Json? site;
  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.site?.str('site_code') ?? '');
  late final _name = TextEditingController(text: widget.site?.str('site_name') ?? '');
  late final _project = TextEditingController(text: widget.site?.str('project_name') ?? '');
  late final _location = TextEditingController(text: widget.site?.str('location') ?? '');
  late bool _night = widget.site?.flag('has_night_shift') ?? false;
  late String? _dayStart = widget.site?.strOrNull('day_shift_start')?.substring(0, 5) ?? '07:00';
  late String? _nightStart = widget.site?.strOrNull('night_shift_start')?.substring(0, 5) ?? '19:00';
  bool _busy = false;

  Future<String?> _time(String? current) async {
    final parts = (current ?? '07:00').split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return current;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = {
        'site_code': _code.text.trim(),
        'site_name': _name.text.trim(),
        'project_name': _project.text.trim().isEmpty ? null : _project.text.trim(),
        'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
        'has_night_shift': _night,
        'day_shift_start': _dayStart,
        'night_shift_start': _night ? _nightStart : null,
      };
      if (widget.site == null) {
        await Api.I.post('/sites', body);
      } else {
        await Api.I.put('/sites/${widget.site!.intv('site_id')}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.site == null ? 'New site' : 'Edit site'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Code', hintText: 'S08'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Site name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null)),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: _project, decoration: const InputDecoration(labelText: 'Project (optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Location (optional)')),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Site has a night shift'),
                value: _night,
                onChanged: (v) => setState(() => _night = v),
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async { final t = await _time(_dayStart); setState(() => _dayStart = t); },
                    icon: const Icon(Icons.wb_sunny_outlined),
                    label: Text('Day starts ${_dayStart ?? '-'}'),
                  ),
                ),
                if (_night) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async { final t = await _time(_nightStart); setState(() => _nightStart = t); },
                      icon: const Icon(Icons.nightlight_outlined),
                      label: Text('Night starts ${_nightStart ?? '-'}'),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              const Text('Shift start times are used by the live board to flag machines that have not arrived.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// Supervisors of a site, per shift, with history. Admin can assign / replace / end.
class SupervisorsSheet extends StatefulWidget {
  const SupervisorsSheet({super.key, required this.site, required this.editable});
  final Json site;
  final bool editable;
  @override
  State<SupervisorsSheet> createState() => _SupervisorsSheetState();
}

class _SupervisorsSheetState extends State<SupervisorsSheet> {
  List<Json>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.getList('/sites/${widget.site.intv('site_id')}/supervisors');
      if (mounted) setState(() { _rows = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _assign({bool replace = false}) async {
    try {
      final users = await Api.I.getList('/users', query: {'role': 'Supervisor', 'status': 'Active', 'page_size': 200});
      if (!mounted) return;
      if (users.isEmpty) { showSnack(context, 'Create a user with the Supervisor role first.', error: true); return; }
      final u = await pickFromList(context, 'Choose the supervisor', [for (final x in users) PickOption(x.intv('user_id'), x.str('full_name'), x.str('username'))]);
      if (u == null || !mounted) return;
      var shift = 'Day';
      if (widget.site.flag('has_night_shift')) {
        final s = await pickFromList(context, 'Shift', [PickOption('Day', 'Day shift'), PickOption('Night', 'Night shift')]);
        if (s == null) return;
        shift = s.value as String;
      }
      if (!mounted) return;
      final from = await pickDate(context, initial: Fmt.today());
      if (from == null) return;
      final id = widget.site.intv('site_id');
      if (replace) {
        await Api.I.post('/sites/$id/supervisors/replace', {'user_id': u.value, 'shift_type': shift, 'first_day': from});
      } else {
        await Api.I.post('/sites/$id/supervisors', {'user_id': u.value, 'shift_type': shift, 'from_date': from});
      }
      if (mounted) showSnack(context, 'Supervisor assigned.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _end(Json r) async {
    final d = await pickDate(context, initial: Fmt.today());
    if (d == null) return;
    try {
      await Api.I.patch('/site-supervisors/${r.intv('site_supervisor_id')}/end', {'to_date': d});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// The first day of the period was entered wrong (e.g. today while the supervisor started with the project).
  Future<void> _changeStart(Json r) async {
    final d = await pickDate(context, initial: r.str('from_date'));
    if (d == null || d == r.str('from_date') || !mounted) return;
    final reason = await promptText(context, 'Correct the first day to ${Fmt.date(d)}?',
        label: 'Reason (kept in the history)',
        minLength: 5,
        confirm: 'Save',
        help: 'Use this when the first day was entered wrong, e.g. while entering past months. '
            'Days inside a finalized payroll cannot move, and two supervisors cannot cover the same site and shift.');
    if (reason == null) return;
    try {
      await Api.I.patch('/site-supervisors/${r.intv('site_supervisor_id')}/start', {'from_date': d, 'reason': reason});
      if (mounted) showSnack(context, 'First day corrected.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = Fmt.today();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${widget.site.str('site_code')} - ${widget.site.str('site_name')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('Supervisors record the machines of this site. One supervisor per shift at a time.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            if (widget.editable)
              Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: () => _assign(), icon: const Icon(Icons.person_add_alt_1), label: const Text('Assign')),
                OutlinedButton.icon(onPressed: () => _assign(replace: true), icon: const Icon(Icons.swap_horiz), label: const Text('Replace from a date')),
              ]),
            const SizedBox(height: 12),
            Expanded(
              child: _error != null
                  ? ErrorView(error: _error!, onRetry: _load)
                  : _rows == null
                      ? const LoadingView()
                      : _rows!.isEmpty
                          ? const EmptyView(text: 'No supervisor assigned yet.', icon: Icons.person_off_rounded)
                          : ListView.separated(
                              itemCount: _rows!.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (_, i) {
                                final r = _rows![i];
                                final current = r.str('from_date').compareTo(today) <= 0 && (r.strOrNull('to_date') == null || r.str('to_date').compareTo(today) >= 0);
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: current ? AppColors.working.withValues(alpha: 0.15) : AppColors.line,
                                    child: Icon(r.str('shift_type') == 'Night' ? Icons.nightlight_round : Icons.wb_sunny_rounded, color: current ? AppColors.working : AppColors.muted),
                                  ),
                                  title: Text(r.str('full_name'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${r.str('shift_type')} shift  |  ${Fmt.date(r.str('from_date'))} - ${r.strOrNull('to_date') == null ? 'open' : Fmt.date(r.str('to_date'))}'),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (current) const Pill('Current', color: AppColors.working),
                                    if (widget.editable)
                                      IconButton(tooltip: 'Correct the first day', icon: const Icon(Icons.edit_calendar_rounded), onPressed: () => _changeStart(r)),
                                    if (widget.editable && (r.strOrNull('to_date') == null || r.str('to_date').compareTo(today) >= 0))
                                      TextButton(onPressed: () => _end(r), child: const Text('End')),
                                  ]),
                                );
                              },
                            ),
            ),
          ]),
        ),
      ),
    );
  }
}
