import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fmt.dart';
import '../core/json.dart';
import '../core/theme.dart';
import 'lookups.dart';
import 'pdf_view.dart';
import 'ui.dart';

/// Every version of a stored document (fuel receipt, contract scan). Old files are never replaced: a new upload is a
/// new version and needs a reason. [basePath] e.g. '/equipment/fuel-issues/12/receipt' (list = basePath + 's').
Future<bool> showFileVersions(BuildContext context,
    {required String title, required String basePath, required String listPath, required String fileName, bool canUpload = false,
    List<String> extensions = const ['pdf', 'jpg', 'jpeg', 'png']}) async {
  var changed = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _VersionsDialog(
        title: title, basePath: basePath, listPath: listPath, fileName: fileName, canUpload: canUpload, extensions: extensions, onChanged: () => changed = true),
  );
  return changed;
}

/// Upload (first file or a new version). Asks the reason when a file already exists. Returns true when uploaded.
Future<bool> uploadFileVersion(BuildContext context, {required String basePath, required bool hasFile, String label = 'File', List<String> extensions = const ['pdf', 'jpg', 'jpeg', 'png']}) async {
  final f = await pickOneFile(label: label, extensions: extensions);
  if (f == null || !context.mounted) return false;
  String? reason;
  if (hasFile) {
    reason = await promptText(context, 'Replace the current file?', label: 'Why (min 5 characters) — the old file is kept', confirm: 'Upload new version');
    if (reason == null) return false;
  }
  try {
    await Api.I.upload(basePath, [f], fields: {'reason': reason});
    if (context.mounted) showSnack(context, hasFile ? 'New version uploaded; the old one is kept.' : 'File uploaded.');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class _VersionsDialog extends StatefulWidget {
  const _VersionsDialog(
      {required this.title, required this.basePath, required this.listPath, required this.fileName, required this.canUpload, required this.extensions, required this.onChanged});
  final String title;
  final String basePath;
  final String listPath;
  final String fileName;
  final bool canUpload;
  final List<String> extensions;
  final VoidCallback onChanged;
  @override
  State<_VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<_VersionsDialog> {
  List<Json>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.getList(widget.listPath);
      if (mounted) setState(() { _rows = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : rows == null
                ? const SizedBox(height: 120, child: LoadingView())
                : rows.isEmpty
                    ? const Padding(padding: EdgeInsets.all(12), child: Text('No file yet.', style: TextStyle(color: AppColors.muted)))
                    : SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          for (final v in rows)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: v.flag('is_current') ? AppColors.working : AppColors.neutral,
                                child: Text('v${v.str('version_no')}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                              title: Text('${v.str('original_name', widget.fileName)}${v.flag('is_current') ? '  (current)' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              subtitle: Text('${Fmt.date(v.str('uploaded_at'))} ${Fmt.time(v.str('uploaded_at'))} · ${v.str('uploaded_by', '-')}'
                                  '${v.strOrNull('reason') == null ? '' : '\n${v.str('reason')}'}'),
                              trailing: IconButton(
                                tooltip: 'View',
                                icon: const Icon(Icons.visibility_rounded, color: AppColors.navy),
                                onPressed: () => viewStoredFile(context,
                                    title: '${widget.title} v${v.str('version_no')}',
                                    fileName: '${widget.fileName}-v${v.str('version_no')}',
                                    load: () => Api.I.getBytes(widget.basePath, query: {'version': v.intv('version_no')})),
                              ),
                            ),
                        ]),
                      ),
      ),
      actions: [
        if (widget.canUpload)
          TextButton.icon(
            icon: const Icon(Icons.upload_file_rounded),
            label: Text((rows ?? const []).isEmpty ? 'Upload' : 'Upload new version'),
            onPressed: () async {
              final ok = await uploadFileVersion(context, basePath: widget.basePath, hasFile: (rows ?? const []).isNotEmpty, extensions: widget.extensions);
              if (ok) {
                widget.onChanged();
                _load();
              }
            },
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
