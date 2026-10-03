import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<String> saveBytes(Uint8List bytes, String fileName, String mime) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: fileName));
    return 'Ready to share: $fileName';
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  var file = File('${dir.path}${Platform.pathSeparator}$fileName');
  var n = 1;
  while (await file.exists()) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    file = File('${dir.path}${Platform.pathSeparator}$base ($n)$ext');
    n++;
  }
  await file.writeAsBytes(bytes, flush: true);
  await launchUrl(Uri.file(file.path));
  return 'Saved to ${file.path}';
}
