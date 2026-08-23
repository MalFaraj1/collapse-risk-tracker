import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

enum AppAlertKind { info, warning, danger, success }

/// Inline alert banner — used for business-rule explanations (e.g. why
/// BR-1 is blocking an action), warnings, and confirmations. Prefer this
/// over a raw [Container] so every alert in the app reads consistently.
class AppAlert extends StatelessWidget {
  const AppAlert({
    super.key,
    required this.kind,
    required this.message,
    this.title,
  });

  final AppAlertKind kind;
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, icon) = switch (kind) {
      AppAlertKind.info => (AppColors.infoBg, AppColors.infoBorder, const Color(0xFF1E3E6E), Icons.info_outline),
      AppAlertKind.warning => (AppColors.warningBg, AppColors.warningBorder, const Color(0xFF6E4E06), Icons.warning_amber_rounded),
      AppAlertKind.danger => (AppColors.dangerBg, AppColors.dangerBorder, const Color(0xFF7A1A15), Icons.block),
      AppAlertKind.success => (AppColors.successBg, AppColors.successBorder, const Color(0xFF0F4A28), Icons.check_circle_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: fg)),
                  ),
                Text(message, style: TextStyle(fontSize: 12.5, color: fg, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
