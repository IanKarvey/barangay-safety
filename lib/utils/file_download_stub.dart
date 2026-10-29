import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Whether this platform can hand a file to the user. On a phone that is the
/// system share sheet: save to Drive or Files, send by Messenger or email, or open
/// straight in Excel or Word.
const bool kCanDownloadFiles = true;

Future<void> downloadFile(
  String fileName,
  Uint8List bytes, {
  required String mimeType,
}) async {
  await SharePlus.instance.share(ShareParams(
    // The in-memory file has no name of its own on a phone, so the name is given
    // separately — without it the receiving app would see a random temp name.
    files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
    fileNameOverrides: [fileName],
    subject: fileName,
  ));
}
