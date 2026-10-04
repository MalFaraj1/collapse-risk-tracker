import 'package:flutter/material.dart';

/// The Municipality of Tripoli crest. One constant so on-screen widgets and
/// PDF generators always load the same file.
const String kMunicipalityLogoAsset = 'assets/logo/logo.jpg';

/// The crest's intrinsic aspect ratio (403×760 px) — a tall shield, so
/// callers size it by height and the width follows.
const double kMunicipalityLogoAspectRatio = 403 / 760;

/// Renders the municipality crest at a given [height].
///
/// The source artwork sits on a white background, so on dark surfaces
/// (e.g. the navy sidebar) pass [onDark] to present it on a white rounded
/// plate — the crest is never recoloured or cropped.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.height, this.onDark = false});

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      kMunicipalityLogoAsset,
      height: height,
      width: height * kMunicipalityLogoAspectRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'شعار بلدية طرابلس',
    );

    if (!onDark) return image;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: height * .12, vertical: height * .08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: image,
    );
  }
}
