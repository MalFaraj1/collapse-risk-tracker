// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser download of raw bytes — the one place PDF and
/// Excel generation both hand off to once they've built their file, so
/// neither has to know how a download actually happens.
///
/// Flutter-Web-only by design: this app has no other target (see the
/// `dart:html` note in pubspec.yaml's dependency comment), so there is no
/// cross-platform abstraction to maintain here.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}