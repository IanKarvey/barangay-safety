// Saves a generated file for the person using the page: a browser download on
// the web dashboard. On a phone there is no such thing as "download a file to
// the computer", so the stub says so rather than pretending.
export 'file_download_stub.dart' if (dart.library.html) 'file_download_web.dart';
