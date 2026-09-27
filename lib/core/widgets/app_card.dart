import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// The base surface for every grouped piece of content — replaces raw
/// [Card]/[Container] use across screens so radius, border, and background
/// stay consistent everywhere.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );
  }
}

/// A card with a titled header row and a divider — for tables/lists that
/// need a heading (e.g. "قائمة العمل" on the dashboard).
class AppCardWithHeader extends StatelessWidget {
  const AppCardWithHeader({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.count,
    this.countColor,
    this.contentPadding = EdgeInsets.zero,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? trailing;

  /// Optional item count shown as a small badge beside the title (e.g. the
  /// number of rows in a work queue).
  final int? count;

  /// Badge color when [count] is non-zero; defaults to navy.
  final Color? countColor;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: AppColors.textMuted), const SizedBox(width: 8)],
                Flexible(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                if (count != null) ...[const SizedBox(width: 8), _CountBadge(count: count!, color: countColor)],
                const Spacer(),
                if (trailing != null)
                  Text(trailing!, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: contentPadding, child: child),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.color});

  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final c = color ?? AppColors.navy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: active ? c : AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: active ? null : Border.all(color: AppColors.border),
      ),
      child: Text(
        '$count',
        style: AppTypography.mono(fontSize: 11, weight: FontWeight.w700, color: active ? Colors.white : AppColors.textMuted),
      ),
    );
  }
}

/// Page-level heading with optional trailing action buttons — the top of
/// every screen.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5), maxLines: 2),
        ],
      ],
    );
    if (actions == null || actions!.isEmpty) return heading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final actionsWrap = Wrap(spacing: 10, runSpacing: 10, children: actions!);
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 14), actionsWrap],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Expanded(child: heading), const SizedBox(width: 16), actionsWrap],
        );
      },
    );
  }
}

/// The KPI tiles at the top of the dashboard.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.trailing,
    this.onTap,
    this.highlight = false,
  });

  /// The number to display, or `null` while it is still loading.
  final String? value;
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Tints the card with its [iconColor] — use when the value needs
  /// attention (e.g. a non-zero overdue count).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final card = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: highlight ? Color.alphaBlend(iconBackground.withOpacity(.45), AppColors.surface) : null,
      borderColor: highlight ? iconColor.withOpacity(.4) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 38,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: value == null
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(value!,
                      style: AppTypography.mono(
                          fontSize: 28, weight: FontWeight.w800, color: highlight ? iconColor : AppColors.text)),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

/// Shown when a list/collection has no data yet, or as the body of a
/// not-yet-built screen (see [ComingSoonScreen]).
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({super.key, required this.icon, required this.title, this.description, this.compact = false});

  final IconData icon;
  final String title;
  final String? description;

  /// A single-row version for places where many empty states stack up
  /// (e.g. dashboard queues) and the full centered block wastes space.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(icon, size: 18, color: AppColors.textFaint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textBody)),
                if (description != null)
                  Text(description!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.5)),
              ],
            ),
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.text)),
            if (description != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(description!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
