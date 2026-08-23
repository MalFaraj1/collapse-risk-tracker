import 'package:flutter/material.dart';

/// Design tokens — colors.
///
/// These values are ported 1:1 from the approved HTML/CSS design prototype
/// (`Collapse-Risk Tracker - UI Design Prototype.html`). Do not introduce new
/// colors ad hoc in a screen — add a token here first, so the palette stays
/// centrally controlled and consistent with the reference design everyone
/// signed off on.
abstract class AppColors {
  AppColors._();

  // --- Brand ------------------------------------------------------------------
  static const navy = Color(0xFF1B2A4A);
  static const navy2 = Color(0xFF24365C);
  static const navy3 = Color(0xFF2E4571);
  static const ice = Color(0xFFCADCFC);
  static const iceTint = Color(0xFFEEF3FC);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFF3E8C8);
  static const goldDark = Color(0xFF9C7D1B);

  // --- Surfaces -----------------------------------------------------------------
  static const bg = Color(0xFFF4F6FB);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE3E8F1);
  static const borderStrong = Color(0xFFCBD5E5);

  // --- Text -----------------------------------------------------------------------
  static const text = Color(0xFF1B2A4A);
  static const textBody = Color(0xFF38466A);
  static const textMuted = Color(0xFF6E7B99);
  static const textFaint = Color(0xFF9AA6C0);

  // --- Semantic / status colors ---------------------------------------------------
  static const success = Color(0xFF1E7A46);
  static const successBg = Color(0xFFE4F3EA);
  static const successBorder = Color(0xFFBFE3CD);

  static const danger = Color(0xFFB3261E);
  static const dangerBg = Color(0xFFFBEAE9);
  static const dangerBorder = Color(0xFFF1C3C0);

  static const warning = Color(0xFF9C6B08);
  static const warningBg = Color(0xFFFBF1DC);
  static const warningBorder = Color(0xFFEED89C);

  static const info = Color(0xFF2E5FA3);
  static const infoBg = Color(0xFFE8EFFA);
  static const infoBorder = Color(0xFFC4D6F0);

  static const purple = Color(0xFF6A4C93);
  static const purpleBg = Color(0xFFEFE9F5);
  static const purpleBorder = Color(0xFFD6C6E8);

  static const neutral = Color(0xFF4A4A4A);
  static const neutralBg = Color(0xFFEDEDED);
  static const neutralBorder = Color(0xFFD4D4D4);
}
