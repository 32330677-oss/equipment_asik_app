import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fmt.dart';
import '../core/json.dart';
import '../core/theme.dart';

// ======================================================================= feedback
void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.breakdown : AppColors.ink,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

void showError(BuildContext context, Object e) => showSnack(context, e is ApiException ? e.message : 'Something went wrong. Please try again.', error: true);

Future<bool> confirmDialog(BuildContext context, String title, String message, {String confirm = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.breakdown) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a text (reason, note...). Returns null when cancelled.
///
/// [minLength] (with [required]) asks for a real explanation: the server refuses shorter reasons on controlled actions.
/// [help] is shown above the field (what happens next, who sees the reason).
Future<String?> promptText(BuildContext context, String title,
    {String label = 'Reason', String? initial, bool required = true, int maxLines = 3, String confirm = 'Save', int minLength = 0, String? help}) async {
  final c = TextEditingController(text: initial ?? '');
  final key = GlobalKey<FormState>();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (help != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(help, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            TextFormField(
              controller: c,
              autofocus: true,
              maxLines: maxLines,
              decoration: InputDecoration(labelText: label),
              validator: (v) {
                final t = (v ?? '').trim();
                if (required && t.isEmpty) return 'Required';
                if (required && minLength > 0 && t.length < minLength) return 'Write at least $minLength characters';
                return null;
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (key.currentState!.validate()) Navigator.pop(ctx, c.text.trim());
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r;
}

// ======================================================================= pickers
Future<String?> pickDate(BuildContext context, {String? initial, String? first, String? last}) async {
  final init = Fmt.parse(initial) ?? Fmt.now();
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: Fmt.parse(first) ?? DateTime(2020),
    lastDate: Fmt.parse(last) ?? DateTime(2035),
  );
  return d == null ? null : Fmt.dateOf(d);
}

/// Returns 'yyyy-MM-dd HH:mm'. [date] fixes the day (only the time is asked) unless [askDate].
Future<String?> pickDateTime(BuildContext context, {String? initial, bool askDate = true}) async {
  var base = Fmt.parse(initial) ?? Fmt.now();
  if (askDate) {
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (d == null) return null;
    base = DateTime(d.year, d.month, d.day, base.hour, base.minute);
  }
  if (!context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  if (t == null) return null;
  return Fmt.wallOf(DateTime(base.year, base.month, base.day, t.hour, t.minute));
}

class PickOption {
  PickOption(this.value, this.label, [this.subtitle]);
  final Object? value;
  final String label;
  final String? subtitle;
}

/// Searchable bottom sheet; returns the chosen option or null.
Future<PickOption?> pickFromList(BuildContext context, String title, List<PickOption> options) {
  return showModalBottomSheet<PickOption>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PickSheet(title: title, options: options),
  );
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.title, required this.options});
  final String title;
  final List<PickOption> options;
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.options
        .where((o) => q.isEmpty || o.label.toLowerCase().contains(q) || (o.subtitle ?? '').toLowerCase().contains(q))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: widget.options.length > 8,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No match'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      title: Text(list[i].label),
                      subtitle: list[i].subtitle == null ? null : Text(list[i].subtitle!),
                      onTap: () => Navigator.pop(context, list[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================= building blocks
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                if (title != null)
                  Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink))),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ]),
      ),
    );
  }
}

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.color = AppColors.navy, this.icon, this.width = 170});
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            if (icon != null)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
            if (icon != null) const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.neutral, this.outlined = false, this.icon});
  final String text;
  final Color color;
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: outlined ? 0.9 : 0.25)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3)),
      ]),
    );
  }
}

class StatePill extends StatelessWidget {
  const StatePill(this.state, {super.key, this.suffix});
  final String state;
  final String? suffix;
  @override
  Widget build(BuildContext context) {
    final s = StateStyle.of(state);
    return Pill(suffix == null ? s.label : '${s.label} $suffix', color: s.color, icon: s.icon, outlined: state == 'NotArrived');
  }
}

class WorkflowPill extends StatelessWidget {
  const WorkflowPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      'Submitted' => AppColors.info,
      'Approved' => AppColors.working,
      'Rejected' => AppColors.breakdown,
      'Cancelled' => AppColors.neutral,
      'Finalized' => AppColors.navy,
      'Paid' => AppColors.working,
      'Generated' => AppColors.info,
      'Voided' || 'Superseded' => AppColors.neutral,
      _ => AppColors.muted,
    };
    return Pill(status, color: c);
  }
}

class PaperPill extends StatelessWidget {
  const PaperPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'Matched' => const Pill('Paper OK', color: AppColors.working, icon: Icons.verified_rounded),
      'Mismatch' => const Pill('Mismatch', color: AppColors.breakdown, icon: Icons.error_rounded),
      'Missing' => const Pill('Missing', color: AppColors.standby, icon: Icons.help_rounded),
      _ => const Pill('Paper pending', color: AppColors.muted, outlined: true),
    };
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_rounded, this.action});
  final String text;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.neutral),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  bool get network => error is ApiException && (error as ApiException).isNetwork;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(network ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 48, color: network ? AppColors.standby : AppColors.breakdown),
          const SizedBox(height: 10),
          Text(network ? 'No connection' : 'Could not load this page', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(error is ApiException ? (error as ApiException).message : 'Something went wrong. Please try again.', textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.width = 150});
  final String label;
  final String value;
  final double width;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: width, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
        Expanded(child: Text(value.isEmpty ? '-' : value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }
}

/// Horizontal-scrolling DataTable inside a card.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.columns, required this.rows, this.empty = 'Nothing to show.', this.showCheckbox = false});
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String empty;
  final bool showCheckbox;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Card(child: EmptyView(text: empty));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              columns: columns,
              rows: rows,
              showCheckboxColumn: showCheckbox,
              headingRowHeight: 44,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 60,
              columnSpacing: 22,
              horizontalMargin: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a page body with pull-to-refresh and a max width.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.maxWidth = 1400});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Simple async state holder used by pages: loading / error / data.
class Loadable<T> {
  bool loading = true;
  Object? error;
  T? data;
}

/// Label: value text for compact cards.
Widget kv(String k, String v) => Text.rich(TextSpan(children: [
      TextSpan(text: '$k ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
    ]));

/// Dropdown builder used by filters and forms.
class Dropdown<T> extends StatelessWidget {
  const Dropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.width = 200});
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<T>(
      key: ValueKey<Object?>(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Reads 'details.blockers' style lists from an ApiException for friendly messages.
List<Json> detailList(Object e, String key) => e is ApiException && e.details != null ? e.details!.list(key) : <Json>[];

/// Coloured notice box (blocked action, read-only day, late entry...): an icon, a message and an optional action.
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.text, this.color = AppColors.info, this.icon = Icons.info_outline_rounded, this.title, this.action});
  final String text;
  final String? title;
  final Color color;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (title != null) Text(title!, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            Text(text, style: const TextStyle(fontSize: 13)),
          ]),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ]),
    );
  }
}

/// Readable label of a field name coming from the API ('check_out_time' -> 'check out time').
String fieldLabel(String key) => const {
      'day_status': 'Day status', 'check_in_time': 'Check-in', 'check_out_time': 'Check-out', 'operator_id': 'Operator',
      'meter_start': 'Meter start', 'meter_end': 'Meter end', 'work_description': 'Work done', 'remarks': 'Remarks',
      'standby_credit_hours': 'Standby hours', 'standby_credit_minutes': 'Standby minutes', 'downtime': 'Pauses', 'cancel_row': 'Cancel the row',
      'status': 'Status', 'paper_status': 'Paper', 'liters': 'Litres', 'price_per_liter': 'Price per litre',
    }[key] ??
    key.replaceAll('_', ' ');

/// Short text of a value for history lines (lists = count, null = empty).
String valueLabel(Object? v) {
  if (v == null) return '(empty)';
  if (v is List) return '${v.length} item(s)';
  if (v is Map) return '{...}';
  final s = '$v';
  return s.length > 40 ? '${s.substring(0, 40)}...' : s;
}

/// "field: old -> new" lines of an audit changed_fields object ({field: [old, new]}).
List<String> changedFieldLines(Object? changed) {
  if (changed is! Map) return const [];
  return [
    for (final e in changed.entries)
      if (e.value is List && (e.value as List).length == 2)
        '${fieldLabel('${e.key}')}: ${valueLabel((e.value as List)[0])} -> ${valueLabel((e.value as List)[1])}',
  ];
}

/// Human text of the warnings an API envelope carries (late entry, ignored fuel...).
String? warningsText(Json envelope) {
  final w = envelope['warnings'];
  if (w is! List || w.isEmpty) return null;
  final parts = <String>[];
  for (final x in w) {
    if (x is Map) {
      final m = asJson(x);
      parts.add(m.str('message', m.str('code')));
    } else if ('$x' == 'FUEL_AT_CHECKOUT_NOT_RECORDED') {
      parts.add('Fuel is not recorded at check-out (the office records fuel issues).');
    } else {
      parts.add('$x'.replaceAll('_', ' ').toLowerCase());
    }
  }
  return parts.join(' ');
}
