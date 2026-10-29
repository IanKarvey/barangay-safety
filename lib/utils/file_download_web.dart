// Web only (uses dart:html). Imported through file_download.dart.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

const bool kCanDownloadFiles = true;

/// Offers [bytes] to the browser as a download named [fileName].
Future<void> downloadFile(
  String fileName,
  Uint8List bytes, {
  required String mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
