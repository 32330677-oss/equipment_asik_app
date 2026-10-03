import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Live board: every deployed machine and what it is doing now. Auto-refresh.
class LiveBoardScreen extends StatefulWidget {
  const LiveBoardScreen({super.key, this.siteId});
  final int? siteId;
  @override
  State<LiveBoardScreen> createState() => _LiveBoardScreenState();
}

class _LiveBoardScreenState extends State<LiveBoardScreen> {
  Json? _data;
  Object? _error;
  bool _loading = false;
  Timer? _timer;
  String _date = Fmt.today();
  String _group = 'site';
  bool _problemsOnly = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final d = await Api.I.getObj('/equipment/live', query: {'date': _date, 'site_id': widget.siteId});
      _data = d;
      _error = null;
      _timer?.cancel();
      if (_date == Fmt.today()) {
        _timer = Timer(Duration(seconds: d.intv('refresh_seconds', 60)), () { if (mounted) _load(); });
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _isProblem(Json m) =>
      m.str('live_state') == 'Breakdown' || m.flag('late') || m.flag('forgotten_checkout') || m.strOrNull('anomaly_code') != null;

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView();
    final k = d.obj('kpis');
    var machines = d.list('machines');
    if (_problemsOnly) machines = machines.where(_isProblem).toList();
    if (_q.isNotEmpty) {
      machines = machines.where((m) => '${m.str('equipment_code')} ${m.str('type_name')} ${m.str('vendor_name')} ${m.str('operator_name')}'.toLowerCase().contains(_q)).toList();
    }
    final groups = <String, List<Json>>{};
    for (final m in machines) {
      final key = _group == 'site'
          ? '${m.str('site_code')} - ${m.str('site_name')}${m.str('shift_type') == 'Night' ? '  (Night)' : ''}'
          : m.str('vendor_name');
      groups.putIfAbsent(key, () => <Json>[]).add(m);
    }
    final cost = k.obj('estimated_cost_today');
    final costText = cost.isEmpty ? '-' : cost.entries.map((e) => Fmt.money((e.value as num?) ?? 0, e.key)).join(' + ');

    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(
          title: 'Live board',
          subtitle: _date == Fmt.today() ? 'Updated ${d.str('as_of').length >= 16 ? d.str('as_of').substring(11, 16) : ''} - refreshes every ${d.intv('refresh_seconds', 60)} s' : 'Situation at the end of ${Fmt.date(_date)}',
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                final v = await pickDate(context, initial: _date, last: Fmt.today());
                if (v != null) { _date = v; _load(); }
              },
              icon: const Icon(Icons.event_rounded),
              label: Text(_date == Fmt.today() ? 'Today' : Fmt.date(_date)),
            ),
            IconButton.filledTonal(onPressed: _loading ? null : _load, icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded)),
          ],
        ),
        Wrap(spacing: 12, runSpacing: 12, children: [
          KpiTile(label: 'On site now', value: '${k.intv('on_site_now')} / ${k.intv('deployed')}', icon: Icons.precision_manufacturing_rounded),
          KpiTile(label: 'Working', value: '${k.intv('working')}', color: AppColors.working, icon: Icons.play_circle_fill_rounded),
          KpiTile(label: 'Breakdown', value: '${k.intv('breakdown')}', color: AppColors.breakdown, icon: Icons.build_circle_rounded),
          KpiTile(label: 'Standby', value: '${k.intv('standby')}', color: AppColors.standby, icon: Icons.pause_circle_filled_rounded),
          KpiTile(label: 'On break', value: '${k.intv('on_break')}', color: AppColors.onBreak, icon: Icons.coffee_rounded),
          KpiTile(label: 'Not arrived', value: '${k.intv('not_arrived')}', color: AppColors.breakdown, icon: Icons.schedule_rounded),
          KpiTile(label: 'Hours today', value: k.dbl('hours_today').toStringAsFixed(1), color: AppColors.ink, icon: Icons.timer_rounded),
          if (Auth.I.canSeeMoney) KpiTile(label: 'Estimated cost today', value: costText, color: AppColors.gold, icon: Icons.payments_rounded, width: 230),
        ]),
        if (k.intv('forgotten_checkout') > 0) ...[
          const SizedBox(height: 12),
          _Banner(icon: Icons.warning_amber_rounded, color: AppColors.breakdown,
              text: '${k.intv('forgotten_checkout')} machine(s) still checked in for too long - probably a forgotten check-out.'),
        ],
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'site', label: Text('By site'), icon: Icon(Icons.location_city_rounded)),
              ButtonSegment(value: 'vendor', label: Text('By vendor'), icon: Icon(Icons.business_rounded)),
            ],
            selected: {_group},
            onSelectionChanged: (s) => setState(() => _group = s.first),
          ),
          FilterChip(
            label: const Text('Problems only'),
            avatar: const Icon(Icons.report_problem_rounded, size: 18),
            selected: _problemsOnly,
            onSelected: (v) => setState(() => _problemsOnly = v),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Machine, vendor, operator'),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (machines.isEmpty)
          Card(child: EmptyView(text: _problemsOnly ? 'No problems right now.' : 'No machine deployed on this date.', icon: Icons.check_circle_outline))
        else
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 1200 ? 3 : c.maxWidth >= 760 ? 2 : 1;
            final w = (c.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(spacing: 14, runSpacing: 14, children: [
              for (final g in groups.entries) SizedBox(width: w, child: _GroupCard(title: g.key, machines: g.value)),
            ]);
          }),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), border: Border.all(color: color.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Expanded(child: Text(text))]),
      );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.title, required this.machines});
  final String title;
  final List<Json> machines;

  @override
  Widget build(BuildContext context) {
    int count(String s) => machines.where((m) => m.str('live_state') == s).length;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), overflow: TextOverflow.ellipsis)),
            Text('${machines.length} deployed', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _StateBar(counts: {
            'Working': count('Working'), 'OnBreak': count('OnBreak'), 'Standby': count('Standby'),
            'Breakdown': count('Breakdown'), 'NotArrived': count('NotArrived'),
            'Finished': count('Finished') + count('Absent') + count('Holiday'),
          }),
        ),
        const Divider(),
        for (final m in machines) _MachineRow(m: m),
      ]),
    );
  }
}

class _StateBar extends StatelessWidget {
  const _StateBar({required this.counts});
  final Map<String, int> counts;
  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(children: [
          for (final e in counts.entries)
            if (e.value > 0) Expanded(flex: e.value, child: Container(color: StateStyle.of(e.key).color.withValues(alpha: e.key == 'NotArrived' ? 0.35 : 1))),
        ]),
      ),
    );
  }
}

class _MachineRow extends StatelessWidget {
  const _MachineRow({required this.m});
  final Json m;

  @override
  Widget build(BuildContext context) {
    final state = m.str('live_state');
    final style = StateStyle.of(state);
    final since = m.strOrNull('since');
    final elapsed = m.intOrNull('elapsed_minutes');
    final open = m.objOrNull('open_downtime');
    final sub = <String>[
      m.str('vendor_name'),
      if (m.strOrNull('operator_name') != null) m.str('operator_name'),
      if (since != null) 'since ${Fmt.time(since)}${elapsed != null ? ' (${Fmt.duration(elapsed)})' : ''}',
      if (open != null && open.strOrNull('reason') != null) '"${open.str('reason')}"',
      if (state == 'Finished') '${Fmt.time(m.strOrNull('check_in_time'))}-${Fmt.time(m.strOrNull('check_out_time'))}',
    ];
    return InkWell(
      onTap: () => _details(context),
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: style.color, width: 4))),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(m.str('equipment_code'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Flexible(child: Text(m.str('type_name'), style: const TextStyle(color: AppColors.muted), overflow: TextOverflow.ellipsis)),
              ]),
              Text(sub.join('  |  '), style: const TextStyle(color: AppColors.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatePill(state),
            if (m.flag('late')) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Late', color: AppColors.breakdown)),
            if (m.flag('forgotten_checkout')) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Check-out?', color: AppColors.breakdown, icon: Icons.warning_rounded)),
          ]),
        ]),
      ),
    );
  }

  void _details(BuildContext context) {
    final downtime = m.list('downtime');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('${m.str('equipment_code')}  ${m.str('type_name')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              StatePill(m.str('live_state')),
            ]),
            const SizedBox(height: 10),
            InfoRow('Site', '${m.str('site_code')} - ${m.str('site_name')} (${m.str('shift_type')})'),
            InfoRow('Vendor', m.str('vendor_name')),
            InfoRow('Operator', m.str('operator_name', '-')),
            InfoRow('Check-in / out', '${Fmt.time(m.strOrNull('check_in_time'))}  -  ${Fmt.time(m.strOrNull('check_out_time'))}'),
            InfoRow('Worked today', Fmt.duration(m.intv('work_minutes_today'))),
            if (Auth.I.canSeeMoney && m['estimated_cost_today'] != null) InfoRow('Estimated cost', Fmt.money(m.dbl('estimated_cost_today'), m.strOrNull('currency'))),
            if (m.strOrNull('remarks') != null) InfoRow('Remarks', m.str('remarks')),
            if (m.strOrNull('anomaly_code') != null) InfoRow('Anomaly', m.str('anomaly_code')),
            const SizedBox(height: 10),
            const Text('Today', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (downtime.isEmpty) const Text('No downtime recorded.', style: TextStyle(color: AppColors.muted))
            else for (final p in downtime)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  StatePill(p.str('downtime_type') == 'Break' || p.str('downtime_type') == 'Refuel' ? 'OnBreak' : p.str('downtime_type')),
                  const SizedBox(width: 8),
                  Text('${Fmt.time(p.strOrNull('start_time'))} - ${p.strOrNull('end_time') == null ? 'now' : Fmt.time(p.strOrNull('end_time'))}'),
                  if (p.strOrNull('reason') != null) Expanded(child: Text('  ${p.str('reason')}', style: const TextStyle(color: AppColors.muted), overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
