import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import 'app_spacing.dart';

/// Assembles the design tokens into a real Flutter [ThemeData].
///
/// Only one theme exists (light) — this is an internal municipal tool with
/// no dark-mode requirement in the spec. If that changes later, split this
/// into lightTheme/darkTheme rather than hardcoding colors elsewhere.
abstract class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        onPrimary: Colors.white,
        secondary: AppColors.gold,
        onSecondary: AppColors.navy,
        error: AppColors.danger,
        surface: AppColors.surface,
      ),
      textTheme: AppTypography.textTheme(base.textTheme),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardTheme(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),

      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.bg),
        headingTextStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: .3,
        ),
        dataTextStyle: const TextStyle(fontSize: 13, color: AppColors.textBody),
        dividerThickness: 1,
      ),
    );
  }
}
