import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/file_save.dart';
import 'ui.dart';

/// Shows a PDF produced by the API with print / share / save actions.
class PdfViewScreen extends StatefulWidget {
  const PdfViewScreen({super.key, required this.title, required this.fileName, required this.load});
  final String title;
  final String fileName;
  final Future<Uint8List> Function() load;

  static Future<void> open(BuildContext context, {required String title, required String fileName, required Future<Uint8List> Function() load}) {
    return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PdfViewScreen(title: title, fileName: fileName, load: load)));
  }

  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _error = null; _bytes = null; });
    try {
      final b = await widget.load();
      if (mounted) setState(() => _bytes = b);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    if (_bytes == null) return;
    try {
      final msg = await FileSave.save(_bytes!, widget.fileName);
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_bytes != null) IconButton(tooltip: 'Save / download', onPressed: _save, icon: const Icon(Icons.download_rounded)),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _bytes == null
              ? const LoadingView()
              : PdfPreview(
                  build: (_) async => _bytes!,
                  pdfFileName: widget.fileName,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowSharing: true,
                  allowPrinting: true,
                ),
    );
  }
}

/// Downloads a stored file (PDF or image) and shows it: PDFs in [PdfViewScreen], images in a zoomable viewer.
Future<void> viewStoredFile(BuildContext context, {required String title, required String fileName, required Future<Uint8List> Function() load}) async {
  Uint8List bytes;
  try {
    bytes = await load();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final isPdf = bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
  if (isPdf) {
    await PdfViewScreen.open(context, title: title, fileName: fileName.endsWith('.pdf') ? fileName : '$fileName.pdf', load: () async => bytes);
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                try {
                  final msg = await FileSave.save(bytes, fileName);
                  if (ctx.mounted) showSnack(ctx, msg);
                } catch (e) {
                  if (ctx.mounted) showError(ctx, e);
                }
              },
            ),
          ],
        ),
        body: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(bytes, fit: BoxFit.contain))),
      ),
    ),
  );
}
