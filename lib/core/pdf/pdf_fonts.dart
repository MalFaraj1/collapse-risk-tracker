import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Loads the bundled Cairo font files as real PDF fonts. Every PDF this
/// app generates — notice documents and report exports alike — goes
/// through this, so Arabic text renders correctly everywhere exactly
/// once, rather than each generator reimplementing font loading.
///
/// This exists specifically because `google_fonts` (already used
/// elsewhere in this app for on-screen text) cannot supply font bytes on
/// Flutter Web: on web it only injects a CSS `<link>` tag pointing at
/// Google's CDN, it never exposes the actual font file to Dart code. The
/// `pdf` package needs real font bytes to draw Arabic glyphs at all, so
/// these two files must be bundled as assets — see the `assets:` note in
/// pubspec.yaml for exactly where to get them and where to put them.
class PdfFonts {
  PdfFonts._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Loads (and caches) both weights, then returns a [pw.ThemeData] that
  /// makes them the default for every text widget in a document — so a
  /// generator only needs `pw.Document(theme: await PdfFonts.theme())`
  /// and never has to think about fonts again.
  static Future<pw.ThemeData> theme() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
    return pw.ThemeData.withFont(base: _regular!, bold: _bold!);
  }
}