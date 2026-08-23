import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../constants/parcel_status.dart';

/// Renders a [ParcelStatus] as the fixed-color pill used everywhere a
/// parcel's status appears — dashboard, parcel list, timeline. Never
/// hardcode status colors at the call site; the color always comes from
/// the enum so it's guaranteed consistent across the whole app.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.dense = false});

  final ParcelStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: status.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: status.color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(status.label,
              style: TextStyle(fontSize: dense ? 10 : 11, fontWeight: FontWeight.w700, color: status.color)),
        ],
      ),
    );
  }
}

/// A generic colored pill for ad hoc states not covered by [ParcelStatus] —
/// e.g. "Overdue" / "Due soon" on the dashboard. Prefer [StatusBadge] when
/// the value is a real [ParcelStatus].
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.borderColor,
    this.filled = false,
  });

  const Pill.solid({super.key, required this.label, required this.backgroundColor})
      : color = Colors.white,
        borderColor = null,
        filled = true;

  final String label;
  final Color color;
  final Color backgroundColor;
  final Color? borderColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// A role tag, e.g. next to a user's name or an assigned team on a dashboard row.
class RolePill extends StatelessWidget {
  const RolePill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.iceTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ice),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: AppColors.navy), const SizedBox(width: 5)],
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.navy)),
        ],
      ),
    );
  }
}
