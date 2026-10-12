import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Called by the "Open ..." button of a help topic with the id of a screen of the app (e.g. 'invoices').
typedef HelpOpenScreen = void Function(String screenId);

/// The one "Help & Assistant" entry of the app.
/// There is no AI on the server, so it opens the Help Center: topics from assistant/guide.md on the server,
/// already filtered by the user's role there. [fromScreen] fills "On this page".
Future<void> openHelp(BuildContext context, {String? fromScreen, required HelpOpenScreen onOpenScreen}) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => HelpCenterScreen(fromScreen: fromScreen, onOpenScreen: onOpenScreen)),
  );
}

/// Help Center home: search, "On this page", "Popular topics", "All topics".
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key, this.fromScreen, required this.onOpenScreen});
  final String? fromScreen;
  final HelpOpenScreen onOpenScreen;

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _home = Loadable<Json>();
  final _query = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  bool _searching = false;
  Json? _results;
  Object? _searchError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _home.loading = true; _home.error = null; });
    try {
      _home.data = await Api.I.getObj('/help', query: {'screen': widget.fromScreen});
    } catch (e) {
      _home.error = e;
    }
    if (mounted) setState(() => _home.loading = false);
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      _searchSeq++; // an answer still on its way is ignored
      setState(() { _results = null; _searchError = null; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    final seq = ++_searchSeq;
    setState(() { _searching = true; _searchError = null; });
    try {
      final r = await Api.I.getObj('/help/search', query: {'q': q, 'screen': widget.fromScreen});
      if (!mounted || seq != _searchSeq) return;
      setState(() { _results = r; _searching = false; });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() { _searchError = e; _searching = false; });
    }
  }

  void _clear() {
    _query.clear();
    _onQueryChanged('');
  }

  void _openTopic(Json t) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => HelpTopicScreen(topicId: t.str('id'), title: t.str('title'), onOpenScreen: widget.onOpenScreen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Assistant')),
      body: Column(children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: TextField(
                  controller: _query,
                  onChanged: _onQueryChanged,
                  onSubmitted: (v) { if (v.trim().isNotEmpty) _search(v.trim()); },
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Type a few words, e.g. "mark batch as paid"',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(tooltip: 'Clear', onPressed: _clear, icon: const Icon(Icons.close_rounded)),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _query.text.trim().isEmpty ? _homeView() : _searchView()),
      ]),
    );
  }

  Widget _searchView() {
    final r = _results;
    if (_searchError != null) return ErrorView(error: _searchError!, onRetry: () => _search(_query.text.trim()));
    if (r == null) return const LoadingView();
    final items = r.list('results');
    final exact = r.flag('exact');
    return Stack(children: [
      _list([
        if (items.isEmpty)
          const EmptyView(text: 'No topic found.\nTry other words, or fewer words.', icon: Icons.search_off_rounded)
        else ...[
          if (!exact)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: _NoticeLine(text: 'No topic has all these words. These are the closest ones.'),
            ),
          _TopicCard(topics: items, onTap: _openTopic),
        ],
      ]),
      if (_searching) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }

  Widget _homeView() {
    if (_home.loading && _home.data == null) return const LoadingView();
    if (_home.error != null) return ErrorView(error: _home.error!, onRetry: _load);
    final h = _home.data ?? <String, dynamic>{};
    final here = h.list('on_this_page');
    final popular = h.list('popular');
    final all = h.list('topics');
    final screenTitle = h.obj('screen').str('title');

    // "All topics" grouped by the first screen of each topic, in the order of the app's screens
    final screenTitles = {for (final s in h.list('screens')) s.str('id'): s.str('title')};
    final groups = <String, List<Json>>{'General': []};
    for (final s in h.list('screens')) {
      groups[s.str('title')] = [];
    }
    for (final t in all) {
      final ids = t['screens'] is List ? (t['screens'] as List).map((e) => '$e').toList() : <String>[];
      final key = ids.isNotEmpty && screenTitles.containsKey(ids.first) ? screenTitles[ids.first]! : 'General';
      groups.putIfAbsent(key, () => <Json>[]).add(t);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _list([
        if (here.isNotEmpty) ...[
          _SectionTitle('On this page', trailing: screenTitle.isEmpty ? null : screenTitle),
          _TopicCard(topics: here, onTap: _openTopic),
          const SizedBox(height: 18),
        ],
        if (popular.isNotEmpty) ...[
          const _SectionTitle('Popular topics'),
          _TopicCard(topics: popular, onTap: _openTopic),
          const SizedBox(height: 18),
        ],
        const _SectionTitle('All topics'),
        if (all.isEmpty)
          const Card(child: EmptyView(text: 'No help topic yet.', icon: Icons.menu_book_rounded))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final g in groups.entries)
                if (g.value.isNotEmpty)
                  ExpansionTile(
                    title: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${g.value.length} topic${g.value.length == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    children: [for (final t in g.value) _topicTile(t)],
                  ),
            ]),
          ),
      ]),
    );
  }

  Widget _topicTile(Json t) => ListTile(
        dense: true,
        title: Text(t.str('title'), style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        onTap: () => _openTopic(t),
      );

  Widget _list(List<Widget> children) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(children: [
          Text(text.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(child: Text('· $trailing', overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          ],
        ]),
      );
}

/// A card of topics: title + one-line summary.
class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topics, required this.onTap});
  final List<Json> topics;
  final void Function(Json) onTap;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < topics.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.article_outlined, color: AppColors.navy),
              title: Text(topics[i].str('title'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: topics[i].str('summary').isEmpty
                  ? null
                  : Text(topics[i].str('summary'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: () => onTap(topics[i]),
            ),
          ],
        ]),
      );
}

/// A small tinted line of information.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.text, this.icon = Icons.info_outline_rounded, this.color = AppColors.info});
  final String text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: _RichLine(text, style: const TextStyle(fontSize: 13.5, color: AppColors.ink))),
        ]),
      );
}

// ===================================================================== topic page

/// One help topic: numbered steps, button names in bold, "Open ..." to go to the screen, related topics.
class HelpTopicScreen extends StatefulWidget {
  const HelpTopicScreen({super.key, required this.topicId, this.title, required this.onOpenScreen});
  final String topicId;
  final String? title;
  final HelpOpenScreen onOpenScreen;

  @override
  State<HelpTopicScreen> createState() => _HelpTopicScreenState();
}

class _HelpTopicScreenState extends State<HelpTopicScreen> {
  final _s = Loadable<Json>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _s.loading = true; _s.error = null; });
    try {
      _s.data = await Api.I.getObj('/help/topics/${Uri.encodeComponent(widget.topicId)}');
    } catch (e) {
      _s.error = e;
    }
    if (mounted) setState(() => _s.loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = _s.data;
    return Scaffold(
      appBar: AppBar(title: Text(t?.str('title') ?? widget.title ?? 'Help')),
      body: _s.loading && t == null
          ? const LoadingView()
          : _s.error != null
              ? ErrorView(error: _s.error!, onRetry: _load)
              : _body(t ?? <String, dynamic>{}),
    );
  }

  Widget _body(Json t) {
    final open = t.objOrNull('open');
    final related = t.list('related');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t.str('title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
              if (t.str('summary').isNotEmpty) ...[
                const SizedBox(height: 6),
                _RichLine(t.str('summary'), style: const TextStyle(color: AppColors.muted, fontSize: 15)),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final b in t.list('blocks')) _block(b)]),
                ),
              ),
              if (open != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => widget.onOpenScreen(open.str('id')),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text('Open ${open.str('title')}'),
                  ),
                ),
              ],
              if (related.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionTitle('Related topics'),
                _TopicCard(
                  topics: related,
                  onTap: (r) => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => HelpTopicScreen(topicId: r.str('id'), title: r.str('title'), onOpenScreen: widget.onOpenScreen)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _block(Json b) {
    const text = TextStyle(fontSize: 15, height: 1.4, color: AppColors.ink);
    switch (b.str('type')) {
      case 'step':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
              child: Text(b.str('n'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: _RichLine(b.str('text'), style: text))),
          ]),
        );
      case 'bullet':
        return Padding(
          padding: EdgeInsets.only(bottom: 8, left: b.flag('nested') ? 38 : 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 8), child: Icon(Icons.circle, size: 6, color: AppColors.muted)),
            const SizedBox(width: 10),
            Expanded(child: _RichLine(b.str('text'), style: text)),
          ]),
        );
      case 'note':
        final warn = b.str('kind') == 'warning';
        final tip = b.str('kind') == 'tip';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _NoticeLine(
            text: b.str('text'),
            icon: tip ? Icons.lightbulb_outline_rounded : warn ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: tip ? AppColors.working : warn ? AppColors.breakdown : AppColors.info,
          ),
        );
      default:
        return Padding(padding: const EdgeInsets.only(bottom: 12), child: _RichLine(b.str('text'), style: text));
    }
  }
}

/// Text where **words** are bold (button and screen names in the guide).
class _RichLine extends StatelessWidget {
  const _RichLine(this.text, {required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    final parts = text.split('**');
    return Text.rich(TextSpan(style: style, children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty) TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null),
    ]));
  }
}
