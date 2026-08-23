import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Design tokens — typography.
///
/// One Arabic type family (Cairo) at multiple weights, deliberately — mixing
/// two Arabic faces tends to look inconsistent. JetBrains Mono is reserved
/// specifically for reference numbers, IDs, and timestamps (e.g. parcel
/// numbers, case IDs) to give records a precise, "system of record" feel
/// without breaking the Arabic reading rhythm elsewhere. See the approved
/// design prototype's style guide screen for the rationale in full.
abstract class AppTypography {
  AppTypography._();

  static TextTheme textTheme(TextTheme base) {
    return GoogleFonts.cairoTextTheme(base).copyWith(
      displayLarge: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.text),
      headlineLarge: GoogleFonts.cairo(fontSize: 23, fontWeight: FontWeight.w800, color: AppColors.text),
      headlineMedium: GoogleFonts.cairo(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text),
      titleLarge: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text),
      titleMedium: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text),
      bodyLarge: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textBody),
      bodyMedium: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textBody),
      bodySmall: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
      labelLarge: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text),
    );
  }

  /// Monospace style for parcel numbers, case IDs, dates, reference codes.
  /// Usage: `Text('PARCEL-4471-Z12', style: AppTypography.mono())`
  static TextStyle mono({double fontSize = 12.5, Color? color, FontWeight? weight}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color ?? AppColors.text,
      fontWeight: weight ?? FontWeight.w500,
    );
  }
}
