import 'package:flutter/material.dart';

import '../core/fmt.dart';
import 'ui.dart';

/// Period of a running statement (vendor statement of account, machine billing history).
/// Returns the query ({} = since the start, up to today) or null when cancelled.
Future<Map<String, String>?> pickStatementPeriod(BuildContext context, String title) async {
  final now = Fmt.now();
  final which = await pickFromList(context, title, [
    PickOption('all', 'Since the start', 'Every movement up to today'),
    PickOption('year', 'This year', 'From 1 January; what is older shows as one brought-forward line'),
    PickOption('pick', 'Choose the dates', 'From a date to a date'),
  ]);
  if (which == null || !context.mounted) return null;
  if (which.value == 'all') return {};
  if (which.value == 'year') return {'from': Fmt.dateOf(DateTime(now.year, 1, 1))}; // up to today (the server's day)
  final from = await pickDate(context, initial: Fmt.dateOf(DateTime(now.year, 1, 1)), last: Fmt.today());
  if (from == null || !context.mounted) return null;
  final to = await pickDate(context, initial: Fmt.today(), last: Fmt.today());
  if (to == null || !context.mounted) return null;
  if (to.compareTo(from) < 0) {
    showSnack(context, 'The end date is before the start date.', error: true);
    return null;
  }
  return {'from': from, 'to': to};
}
