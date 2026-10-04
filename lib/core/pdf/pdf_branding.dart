import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import '../widgets/app_logo.dart';

/// Loads (and caches) the municipality crest as a PDF image, so every
/// generated document — notices and report exports — carries the same
/// official letterhead mark.
class PdfBranding {
  PdfBranding._();

  static pw.MemoryImage? _logo;

  static Future<pw.MemoryImage> logo() async {
    return _logo ??= pw.MemoryImage((await rootBundle.load(kMunicipalityLogoAsset)).buffer.asUint8List());
  }
}
