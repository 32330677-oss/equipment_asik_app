import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/json.dart';
import '../core/theme.dart';
import 'ui.dart';

/// Option lists used by forms and filters (vendors, machines, sites, operators, contracts).
class Lookups {
  static Future<List<PickOption>> vendors({bool activeOnly = false}) async {
    final rows = await Api.I.getList('/equipment/vendors', query: {if (activeOnly) 'status': 'Active'});
    return [for (final r in rows) PickOption(r.intv('vendor_id'), r.str('vendor_name'), '${r.str('vendor_code')}  ${r.str('status')}')];
  }

  static Future<List<PickOption>> machines({int? vendorId, String? status}) async {
    final rows = await Api.I.getList('/equipment/machines', query: {'vendor_id': vendorId, 'status': status, 'page_size': 200});
    return [
      for (final r in rows)
        PickOption(r.intv('equipment_id'), '${r.str('equipment_code')}  ${r.machineType}',
            [r.str('vendor_name'), if (r.strOrNull('plate_number') != null) r.str('plate_number'), if (r.strOrNull('site_code') != null) 'at ${r.str('site_code')}'].join('  ·  ')),
    ];
  }

  static Future<List<PickOption>> sites({bool activeOnly = true}) async {
    final rows = await Api.I.getList('/sites', query: {if (activeOnly) 'status': 'Active'});
    return [for (final r in rows) PickOption(r.intv('site_id'), '${r.str('site_code')}  ${r.str('site_name')}', r.strOrNull('project_name'))];
  }

  static Future<List<PickOption>> operators(int vendorId) async {
    final rows = await Api.I.getList('/equipment/operators', query: {'vendor_id': vendorId, 'status': 'Active'});
    return [
      for (final r in rows)
        PickOption(r.intv('operator_id'), r.str('full_name'), r.strOrNull('license_expiry') == null ? null : 'Licence until ${r.str('license_expiry')}'),
    ];
  }

  static Future<List<PickOption>> types() async {
    final rows = await Api.I.getList('/equipment/types');
    return [for (final r in rows.where((r) => r.flag('is_active'))) PickOption(r.intv('type_id'), r.str('type_name'), r.strOrNull('type_name_ar'))];
  }

  static Future<List<PickOption>> contracts(int vendorId) async {
    final rows = await Api.I.getList('/equipment/vendors/$vendorId/contracts');
    return [
      for (final r in rows)
        PickOption(r.intv('vendor_contract_id'), '${r.str('contract_number')}  (${r.str('currency')})',
            '${r.str('start_date')} to ${r.str('end_date', 'open')}  ·  ${r.str('status')}'),
    ];
  }
}

/// Form-like field that opens a searchable list. Shows the chosen label and a clear button.
class PickerField extends StatefulWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.load,
    required this.onChanged,
    this.valueLabel,
    this.icon,
    this.width,
    this.clearable = true,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final String? valueLabel;
  final Future<List<PickOption>> Function() load;
  final ValueChanged<PickOption?> onChanged;
  final IconData? icon;
  final double? width;
  final bool clearable;
  final bool enabled;
  final String? errorText;

  @override
  State<PickerField> createState() => _PickerFieldState();
}

class _PickerFieldState extends State<PickerField> {
  bool _loading = false;

  Future<void> _open() async {
    setState(() => _loading = true);
    try {
      final options = await widget.load();
      if (!mounted) return;
      setState(() => _loading = false);
      final p = await pickFromList(context, widget.label, options);
      if (p != null) widget.onChanged(p);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.valueLabel != null && widget.valueLabel!.isNotEmpty;
    final field = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.enabled && !_loading ? _open : null,
      child: InputDecorator(
        isEmpty: !has,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: widget.errorText,
          enabled: widget.enabled,
          prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 20),
          suffixIcon: _loading
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : has && widget.clearable && widget.enabled
                  ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), tooltip: 'Clear', onPressed: () => widget.onChanged(null))
                  : const Icon(Icons.expand_more_rounded),
        ),
        child: Text(has ? widget.valueLabel! : '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink)),
      ),
    );
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

/// Date field (yyyy-MM-dd) with picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.width, this.clearable = false, this.first, this.last});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final double? width;
  final bool clearable;
  final String? first;
  final String? last;

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    final field = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final d = await pickDate(context, initial: value, first: first, last: last);
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        isEmpty: !has,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_rounded, size: 20),
          suffixIcon: has && clearable ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null)) : null,
        ),
        child: Text(has ? value! : ''),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Text field with a controller kept by the caller; small helper for dialogs.
Widget textField(TextEditingController c, String label,
    {bool number = false, bool required = false, int maxLines = 1, String? hint, double? width, String? suffix, bool decimal = true}) {
  final f = TextFormField(
    controller: c,
    maxLines: maxLines,
    keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal, signed: true) : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
    decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint, suffixText: suffix),
    validator: (v) {
      final s = (v ?? '').trim();
      if (required && s.isEmpty) return 'Required';
      if (number && s.isNotEmpty && double.tryParse(s) == null) return 'Enter a number';
      return null;
    },
  );
  return width == null ? f : SizedBox(width: width, child: f);
}

/// Returns null for an empty text, the trimmed text otherwise.
String? textOrNull(TextEditingController c) {
  final s = c.text.trim();
  return s.isEmpty ? null : s;
}

num? numOrNull(TextEditingController c) {
  final s = c.text.trim();
  if (s.isEmpty) return null;
  return num.tryParse(s);
}

/// Standard form dialog shell: title, scrollable body, Cancel / Save.
Future<T?> showFormDialog<T>(BuildContext context, {required String title, required Widget Function(BuildContext ctx, StateSetter set) body, required Future<T?> Function() onSave, double width = 560, String saveLabel = 'Save'}) {
  final key = GlobalKey<FormState>();
  var busy = false;
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: width,
          child: Form(key: key, child: SingleChildScrollView(child: body(ctx, set))),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!key.currentState!.validate()) return;
                    set(() => busy = true);
                    try {
                      final r = await onSave();
                      if (ctx.mounted) Navigator.pop(ctx, r);
                    } catch (e) {
                      if (ctx.mounted) {
                        set(() => busy = false);
                        showError(ctx, e);
                      }
                    }
                  },
            child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(saveLabel),
          ),
        ],
      ),
    ),
  );
}

/// Two-column responsive grid for forms.
class FormGrid extends StatelessWidget {
  const FormGrid({super.key, required this.children, this.columns = 2, this.spacing = 12});
  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 440 ? 1 : columns;
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
    });
  }
}

/// Opens the system file picker for one file. Returns null when cancelled.
Future<UploadFile?> pickOneFile({String label = 'File', List<String> extensions = const ['pdf', 'jpg', 'jpeg', 'png']}) async {
  final f = await openFile(acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)]);
  if (f == null) return null;
  return UploadFile(await f.readAsBytes(), f.name);
}
