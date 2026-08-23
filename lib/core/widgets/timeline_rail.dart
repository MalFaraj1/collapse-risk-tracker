import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

enum RailItemState { done, current, pending }

/// The vertical timeline rail — the other signature motif alongside
/// [CountdownRing]. Used for the parcel timeline (§5.1, FR-PAR-3) and any
/// other sequential-history view (e.g. an evacuation's step checklist could
/// use this too — prefer it over inventing a new list style).
class TimelineRail extends StatelessWidget {
  const TimelineRail({super.key, required this.items});

  final List<TimelineRailItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          _RailRow(item: items[i], isLast: i == items.length - 1),
      ],
    );
  }
}

class TimelineRailItem {
  const TimelineRailItem({
    required this.state,
    required this.icon,
    required this.title,
    this.timestamp,
    this.body,
    this.meta,
  });

  final RailItemState state;
  final IconData icon;
  final String title;
  final String? timestamp;
  final String? body;
  final String? meta;
}

class _RailRow extends StatelessWidget {
  const _RailRow({required this.item, required this.isLast});

  final TimelineRailItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isDone = item.state == RailItemState.done;
    final isCurrent = item.state == RailItemState.current;

    final Color nodeBg = isDone ? AppColors.success : (isCurrent ? AppColors.navy : AppColors.surface);
    final Color nodeBorder = isDone ? AppColors.success : (isCurrent ? AppColors.gold : AppColors.borderStrong);
    final Color iconColor = isDone ? Colors.white : (isCurrent ? AppColors.gold : AppColors.textMuted);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node + connecting line
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: nodeBg,
                  border: Border.all(
                    color: nodeBorder,
                    width: 2.5,
                    style: item.state == RailItemState.pending ? BorderStyle.solid : BorderStyle.solid,
                  ),
                  boxShadow: isCurrent
                      ? [BoxShadow(color: AppColors.goldLight, blurRadius: 0, spreadRadius: 4)]
                      : null,
                ),
                child: Icon(item.icon, size: 14, color: iconColor),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [
                      Text(item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.text)),
                      if (item.timestamp != null)
                        Text(item.timestamp!, style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                  if (item.body != null) ...[
                    const SizedBox(height: 3),
                    Text(item.body!,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.6)),
                  ],
                  if (item.meta != null) ...[
                    const SizedBox(height: 5),
                    Text(item.meta!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
