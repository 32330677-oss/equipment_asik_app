import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _s = Loadable<List<Json>>();
  String? _role;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getList('/users', query: {'role': _role, 'q': _q, 'page_size': 200});
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _showTempPassword(String username, String password) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key_rounded, color: AppColors.gold, size: 36),
        title: const Text('Temporary password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Give these to $username. The password is shown only once; it must be changed at the first sign-in.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SelectableText(password, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: password)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _edit([Json? user]) async {
    final saved = await showDialog<Json>(context: context, builder: (_) => _UserDialog(user: user));
    if (saved == null) return;
    if (user == null && saved['temporary_password'] != null) {
      await _showTempPassword(saved.str('username'), saved.str('temporary_password'));
    }
    _load();
  }

  Future<void> _toggle(Json u) async {
    final active = u.str('status') == 'Active';
    final reason = await promptText(context, active ? 'Deactivate ${u.str('full_name')}?' : 'Activate ${u.str('full_name')}?',
        label: active ? 'Why? (kept in the audit log)' : 'Note (optional)',
        required: active,
        minLength: active ? 5 : 0,
        confirm: active ? 'Deactivate' : 'Activate',
        help: active ? '${u.str('full_name')} will not be able to sign in.' : '${u.str('full_name')} will be able to sign in again.');
    if (reason == null) return;
    try {
      await Api.I.patch('/users/${u.intv('user_id')}/status', {'status': active ? 'Inactive' : 'Active', if (reason.isNotEmpty) 'reason': reason});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reset(Json u) async {
    final ok = await confirmDialog(context, 'Reset password', 'Create a new temporary password for ${u.str('full_name')}? The account is also unlocked.', confirm: 'Reset');
    if (!ok) return;
    try {
      final d = asJson(await Api.I.post('/users/${u.intv('user_id')}/reset-password'));
      if (mounted) await _showTempPassword(u.str('username'), d.str('temporary_password'));
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _s.data ?? <Json>[];
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(title: 'Users', subtitle: 'Admins, accountants and site supervisors', actions: [
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name'),
              onSubmitted: (v) { _q = v.trim(); _load(); },
            ),
          ),
          Dropdown<String?>(
            label: 'Role', value: _role, width: 170,
            items: const [
              DropdownMenuItem(value: null, child: Text('All roles')),
              DropdownMenuItem(value: 'Admin', child: Text('Admin')),
              DropdownMenuItem(value: 'Accountant', child: Text('Accountant')),
              DropdownMenuItem(value: 'Supervisor', child: Text('Supervisor')),
            ],
            onChanged: (v) { _role = v; _load(); },
          ),
          FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt_1), label: const Text('New user')),
        ]),
        if (_s.loading && _s.data == null) const LoadingView()
        else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
        else TableCard(
          empty: 'No users.',
          columns: const [
            DataColumn(label: Text('Name')), DataColumn(label: Text('Username')), DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')), DataColumn(label: Text('Last sign-in')), DataColumn(label: Text('')),
          ],
          rows: [
            for (final u in users)
              DataRow(cells: [
                DataCell(Text(u.str('full_name'), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(u.str('username'))),
                DataCell(Pill(u.str('role'), color: u.str('role') == 'Admin' ? AppColors.navy : u.str('role') == 'Accountant' ? AppColors.gold : AppColors.info)),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  Pill(u.str('status'), color: u.str('status') == 'Active' ? AppColors.working : AppColors.neutral),
                  if (u.strOrNull('locked_until') != null && u.str('locked_until').compareTo(Fmt.nowWall()) > 0) ...[
                    const SizedBox(width: 6), const Pill('Locked', color: AppColors.breakdown, icon: Icons.lock),
                  ],
                  if (u.flag('must_change_password')) ...[const SizedBox(width: 6), const Pill('Temp. password', color: AppColors.standby)],
                ])),
                DataCell(Text(u.strOrNull('last_login_at') == null ? 'Never' : '${Fmt.date(u.str('last_login_at'))} ${Fmt.time(u.str('last_login_at'))}')),
                DataCell(PopupMenuButton<String>(
                  onSelected: (a) {
                    if (a == 'edit') _edit(u);
                    if (a == 'status') _toggle(u);
                    if (a == 'reset') _reset(u);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                    PopupMenuItem(
                      value: 'status',
                      enabled: u.intv('user_id') != Auth.I.userId,
                      child: Text(u.str('status') == 'Active' ? 'Deactivate' : 'Activate'),
                    ),
                  ],
                )),
              ]),
          ],
        ),
      ],
    );
  }
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({this.user});
  final Json? user;
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.user?.str('username') ?? '');
  late final _name = TextEditingController(text: widget.user?.str('full_name') ?? '');
  late final _email = TextEditingController(text: widget.user?.str('email') ?? '');
  late final _phone = TextEditingController(text: widget.user?.str('phone_number') ?? '');
  late String _role = widget.user?.str('role') ?? 'Supervisor';
  late final String? _oldRole = widget.user?.str('role');
  final _reason = TextEditingController();
  bool _busy = false;

  /// a role change gives or removes permissions: a reason is required (audit log)
  bool get _roleChanged => _oldRole != null && _role != _oldRole;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = {
        'full_name': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone_number': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'role': _role,
        if (_roleChanged) 'reason': _reason.text.trim(),
      };
      final Json res = widget.user == null
          ? asJson(await Api.I.post('/users', {...body, 'username': _username.text.trim()}))
          : asJson(await Api.I.put('/users/${widget.user!.intv('user_id')}', body));
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.user == null;
    return AlertDialog(
      title: Text(isNew ? 'New user' : 'Edit user'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _username,
              enabled: isNew,
              decoration: const InputDecoration(labelText: 'Username', helperText: 'Letters, digits, dot, dash, underscore'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            Dropdown<String>(
              label: 'Role', value: _role, width: null,
              items: const [
                DropdownMenuItem(value: 'Supervisor', child: Text('Supervisor - records machines on his sites')),
                DropdownMenuItem(value: 'Accountant', child: Text('Accountant - paper, fuel, payroll')),
                DropdownMenuItem(value: 'Admin', child: Text('Admin - everything')),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            if (_roleChanged) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLines: 2,
                decoration: InputDecoration(labelText: 'Why change the role from $_oldRole to $_role? *'),
                validator: (v) => (v ?? '').trim().length < 5 ? 'Write at least 5 characters' : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email (optional)')),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(isNew ? 'Create' : 'Save')),
      ],
    );
  }
}
