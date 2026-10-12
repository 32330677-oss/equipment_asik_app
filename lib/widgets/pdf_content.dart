import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// What the office leaves out of a statement / invoice PDF for the vendor (12 Oct 2026). The money lines and the totals
/// always stay (they must add up); only explanations and internal details can be hidden. The choice is remembered on
/// this device. Keys = the `hide` values of the API.
const pdfHideOptions = <String, (String, String)>{
  'days': ('Daily attendance table', 'Every day with its times and hours.'),
  'monthly': ('Monthly hours calculation', 'Monthly machines: hours due, missing and extra hours, day by day.'),
  'notes': ('Notes under the money lines', 'e.g. the dates of absent days, how a line was computed.'),
  'reasons': ('Reasons of additions / deductions', 'The type and the amount stay; the reason text is left out.'),
  'terms': ('Pricing terms line', 'The short summary of the rate card.'),
  'sites': ('Cost by site', 'Monthly machine working at several sites.'),
  'operator': ('Operator column', 'Name of the operator on each day.'),
  'paper': ('Paper sheet columns', 'Sheet row number and paper status (internal).'),
};

const _kHide = 'pdf_hide_vendor';

/// Asks what to show; returns the keys to HIDE (empty = everything), or null when cancelled.
Future<Set<String>?> askPdfContent(BuildContext context, {String title = 'What does the vendor see?'}) async {
  var hide = <String>{};
  try {
    final p = await SharedPreferences.getInstance();
    hide = (p.getStringList(_kHide) ?? const <String>[]).where(pdfHideOptions.containsKey).toSet();
  } catch (_) {/* nothing remembered */}
  if (!context.mounted) return null;
  final r = await showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Ticked = printed. The amounts, every money line and the totals are always printed, so the PDF still adds up; '
                  'only explanations and internal details can be left out. Your choice is remembered on this device.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final e in pdfHideOptions.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: !hide.contains(e.key),
                  onChanged: (v) => set(() => v == true ? hide.remove(e.key) : hide.add(e.key)),
                  title: Text(e.value.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(e.value.$2, style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => set(() => hide.clear()), child: const Text('Show everything')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {...hide}), child: const Text('Open PDF')),
        ],
      ),
    ),
  );
  if (r == null) return null;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHide, r.toList()..sort());
  } catch (_) {/* not critical */}
  return r;
}
