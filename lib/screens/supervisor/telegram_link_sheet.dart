import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// "Link Telegram" (supervisor menu): shows whether the equipment bot is linked, opens Telegram with a one-time
/// link (valid 15 minutes), or unlinks. The bot only reads / records through the same rules as the app.
Future<void> openTelegramLink(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _TelegramLinkSheet(),
  );
}

class _TelegramLinkSheet extends StatefulWidget {
  const _TelegramLinkSheet();
  @override
  State<_TelegramLinkSheet> createState() => _TelegramLinkSheetState();
}

class _TelegramLinkSheetState extends State<_TelegramLinkSheet> {
  final _s = Loadable<Json>();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getObj('/telegram/me');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  Future<void> _link() async {
    setState(() => _busy = true);
    try {
      final d = asJson(await Api.I.post('/telegram/link-code'));
      final ok = await launchUrl(Uri.parse(d.str('url')), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'Could not open Telegram. Is it installed?', error: true);
      if (mounted) showSnack(context, 'In Telegram, tap Start. The link works once, for ${d.intv('valid_minutes')} minutes.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unlink() async {
    final ok = await confirmDialog(context, 'Unlink Telegram', 'The bot will stop answering in your Telegram chat. You can link it again at any time.', confirm: 'Unlink', danger: true);
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Api.I.delete('/telegram/me');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _s.data;
    final linked = d?.flag('linked') ?? false;
    final enabled = d?.flag('bot_enabled') ?? false;
    final user = d?.strOrNull('telegram_username');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.send_rounded, color: AppColors.info),
            const SizedBox(width: 10),
            const Expanded(child: Text('Telegram bot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            if (d != null) Pill(linked ? 'Linked' : 'Not linked', color: linked ? AppColors.working : AppColors.neutral),
          ]),
          const SizedBox(height: 12),
          if (_s.loading && d == null) const LoadingView()
          else if (_s.error != null) ErrorView(error: _s.error!, onRetry: _load)
          else ...[
            Text(
              linked
                  ? 'Your Telegram${user != null ? ' (@$user)' : ''} is linked. Tell the bot what happened with your machines, in your own words or a voice note. It shows what it will record and saves drafts only after you confirm. Submit stays in the app.'
                  : 'Link your Telegram to record your machines by text or voice note. The bot shows what it will record and saves drafts only after you confirm.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            if (!enabled && !linked)
              const Text('The bot is not switched on yet. Ask the office.', style: TextStyle(color: AppColors.breakdown))
            else if (!linked)
              FilledButton.icon(onPressed: _busy ? null : _link, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Open Telegram and link'))
            else ...[
              OutlinedButton.icon(onPressed: _busy ? null : _link, icon: const Icon(Icons.swap_horiz_rounded), label: const Text('Link another Telegram account')),
              const SizedBox(height: 8),
              TextButton.icon(onPressed: _busy ? null : _unlink, icon: const Icon(Icons.link_off_rounded, color: AppColors.breakdown), label: const Text('Unlink', style: TextStyle(color: AppColors.breakdown))),
            ],
          ],
        ]),
      ),
    );
  }
}
