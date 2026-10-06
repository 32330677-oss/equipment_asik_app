import 'package:flutter/material.dart';

import '../auth/change_password_screen.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../screens/admin/audit_screen.dart';
import '../screens/admin/settings_screen.dart';
import '../screens/admin/sites_screen.dart';
import '../screens/admin/users_screen.dart';
import '../screens/equipment/attendance_review_screen.dart';
import '../screens/equipment/fuel_adjustments_screen.dart';
import '../screens/equipment/live_board_screen.dart';
import '../screens/equipment/machines_screen.dart';
import '../screens/equipment/payroll_screen.dart';
import '../screens/equipment/timesheets_screen.dart';
import '../screens/equipment/vendors_screen.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.builder, {this.section});
  final String label;
  final IconData icon;
  final Widget Function() builder;
  final String? section;
}

/// Admin / Accountant shell: dark navigation rail on wide screens, drawer on phones.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<_NavItem> get _items {
    final admin = Auth.I.isAdmin;
    return [
      _NavItem('Live board', Icons.dashboard_rounded, () => const LiveBoardScreen(), section: 'Operations'),
      _NavItem('Attendance review', Icons.fact_check_rounded, () => const AttendanceReviewScreen()),
      _NavItem('Paper sheets', Icons.description_rounded, () => const TimesheetsScreen()),
      _NavItem('Invoice', Icons.payments_rounded, () => const PayrollScreen(), section: 'Money'),
      _NavItem('Fuel & adjustments', Icons.local_gas_station_rounded, () => const FuelAdjustmentsScreen()),
      _NavItem('Machines', Icons.precision_manufacturing_rounded, () => const MachinesScreen(), section: 'Fleet'),
      _NavItem('Vendors', Icons.business_rounded, () => const VendorsScreen()),
      _NavItem('Sites', Icons.location_city_rounded, () => const SitesScreen(), section: 'Setup'),
      if (admin) _NavItem('Users', Icons.manage_accounts_rounded, () => const UsersScreen()),
      if (admin) _NavItem('Settings', Icons.tune_rounded, () => const SettingsScreen()),
      if (admin) _NavItem('Audit log', Icons.history_rounded, () => const AuditScreen()),
    ];
  }

  void _profile() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: CircleAvatar(backgroundColor: AppColors.navy, child: Text(_initials(Auth.I.name), style: const TextStyle(color: Colors.white))),
            title: Text(Auth.I.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(Auth.I.role),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_reset_rounded),
            title: const Text('Change password'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.breakdown),
            title: const Text('Sign out', style: TextStyle(color: AppColors.breakdown)),
            onTap: () {
              Navigator.pop(ctx);
              Auth.I.logout();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_index >= items.length) _index = 0;
    final wide = MediaQuery.of(context).size.width >= 1000;
    final page = KeyedSubtree(key: ValueKey(_index), child: items[_index].builder());

    final appBar = AppBar(
      title: Row(children: [
        if (!wide) ...[Image.asset('assets/images/logo.png', height: 30), const SizedBox(width: 10)],
        Text(items[_index].label),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _profile,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                if (wide)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(Auth.I.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(Auth.I.role, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ]),
                const SizedBox(width: 10),
                CircleAvatar(radius: 17, backgroundColor: AppColors.navy, child: Text(_initials(Auth.I.name), style: const TextStyle(color: Colors.white, fontSize: 12))),
              ]),
            ),
          ),
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(children: [
          _SideNav(items: items, index: _index, onSelect: (i) => setState(() => _index = i)),
          Expanded(child: Scaffold(appBar: appBar, body: page)),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        backgroundColor: AppColors.navyDark,
        child: _SideNav(items: items, index: _index, expanded: true, onSelect: (i) {
          Navigator.pop(context);
          setState(() => _index = i);
        }),
      ),
      body: page,
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.items, required this.index, required this.onSelect, this.expanded = false});
  final List<_NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.section != null) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
          child: Text(it.section!.toUpperCase(), style: const TextStyle(color: Color(0xFF7F8AB4), fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ));
      }
      final selected = i == index;
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: selected ? const Color(0x26FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: selected
                  ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.gold, width: 3)))
                  : null,
              child: Row(children: [
                Icon(it.icon, size: 20, color: selected ? Colors.white : const Color(0xFFB9C1DC)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(it.label,
                      style: TextStyle(color: selected ? Colors.white : const Color(0xFFD0D5E8), fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                ),
              ]),
            ),
          ),
        ),
      ));
    }
    return Container(
      width: 250,
      color: AppColors.navyDark,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Image.asset('assets/images/logo.png', height: 34),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(AppConfig.appName, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 15)),
              ),
            ]),
          ),
          Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 16), children: children)),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(AppConfig.companyName, style: TextStyle(color: Color(0xFF7F8AB4), fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}
