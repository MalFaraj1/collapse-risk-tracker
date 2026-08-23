/// Design tokens — spacing and shape.
///
/// Matches the 4px-ish rhythm used throughout the approved prototype
/// (component paddings were mostly 8–22px, radii 6/10/16px).
abstract class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const xxl = 40.0;
}

abstract class AppRadius {
  AppRadius._();

  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const pill = 999.0;
}
