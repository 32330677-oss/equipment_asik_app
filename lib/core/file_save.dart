import 'dart:typed_data';

import 'file_save_stub.dart'
    if (dart.library.js_interop) 'file_save_web.dart'
    if (dart.library.io) 'file_save_io.dart' as impl;

/// Saves (desktop: Downloads folder and opens it), downloads (web) or shares (mobile) a file.
/// Returns a short human message ("Saved to ..." / "Downloaded").
class FileSave {
  static Future<String> save(Uint8List bytes, String fileName) => impl.saveBytes(bytes, fileName, mimeFor(fileName));

  static String mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}
