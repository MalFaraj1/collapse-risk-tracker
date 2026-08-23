import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

enum AppButtonVariant { primary, gold, outline, ghost, danger }

/// The single button component for the whole app. Pick a [variant] instead
/// of styling a raw [ElevatedButton]/[TextButton] per screen — this is what
/// keeps every button in the app looking like it belongs to the same
/// product (see the design prototype's style-guide screen for the source).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.dense = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool dense;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      AppButtonVariant.primary => (AppColors.navy, Colors.white, null),
      AppButtonVariant.gold => (AppColors.gold, AppColors.navy, null),
      AppButtonVariant.outline => (AppColors.surface, AppColors.text, AppColors.borderStrong),
      AppButtonVariant.ghost => (Colors.transparent, AppColors.textMuted, null),
      AppButtonVariant.danger => (AppColors.danger, Colors.white, null),
    };

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: dense ? 15 : 17), const SizedBox(width: 7)],
        Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: dense ? 12 : 13)),
      ],
    );

    return SizedBox(
      width: expand ? double.infinity : null,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: dense ? 8 : 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: border != null ? Border.all(color: border) : null,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: onPressed == null ? fg.withOpacity(.45) : fg),
              child: IconTheme.merge(
                data: IconThemeData(color: onPressed == null ? fg.withOpacity(.45) : fg),
                child: Opacity(opacity: onPressed == null ? 0.55 : 1, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small icon-only button, e.g. the notifications bell in the top bar.
class AppIconButton extends StatelessWidget {
  const AppIconButton({super.key, required this.icon, this.onPressed, this.showDot = false});

  final IconData icon;
  final VoidCallback? onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 19, color: AppColors.textMuted),
            ),
          ),
        ),
        if (showDot)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
