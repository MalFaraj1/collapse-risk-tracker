import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../core/constants/parcel_status.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/timeline_rail.dart';

/// Parcel detail & timeline — the flagship screen of the whole app (§5.1,
/// FR-PAR-3). Every other feature (complaints, reviews, decisions, notices,
/// site visits, assessments, demolition) ultimately appends an entry to
/// this timeline, so as those features get built, extend [_mockTimeline]
/// below into a real merged, sorted stream across all those collections
/// rather than querying Firestore once per entity type inside the widget
/// tree.
///
/// TODO(Phase 3): replace the mock parcel + timeline with a real
/// `parcels/{id}` doc stream, merged with its related sub-collections/
/// queries, ordered by timestamp.
class ParcelDetailScreen extends StatelessWidget {
  const ParcelDetailScreen({super.key, required this.parcelId});

  final String parcelId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(parcelId, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(width: 10),
                      const StatusBadge(status: ParcelStatus.awaitingCompliance),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('شارع المعرض، طرابلس · مبنى سكني من 4 طوابق',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
            ),
            AppButton(label: 'سجلّ التدقيق', icon: Icons.history, variant: AppButtonVariant.outline, onPressed: () {}),
            const SizedBox(width: 10),
            AppButton(label: 'إجراء جديد', icon: Icons.add_task, onPressed: () {}),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          final timeline = AppCardWithHeader(
            title: 'الخط الزمني للحالة',
            icon: Icons.timeline_outlined,
            trailing: '${_mockTimeline.length} أحداث',
            contentPadding: const EdgeInsets.all(20),
            child: TimelineRail(items: _mockTimeline),
          );
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('بيانات العقار', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 10),
                    _kv('رقم العقار', '4471'),
                    _kv('المنطقة العقارية', 'Z12'),
                    _kv('عدد المباني', '1'),
                    _kv('الطوابق', '4'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                backgroundColor: AppColors.iceTint,
                borderColor: AppColors.ice,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('حالات سابقة على هذا العقار',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    SizedBox(height: 8),
                    Text('لا توجد حالات سابقة مغلقة على هذا العقار. هذه أول حالة مسجّلة (BR-3).',
                        style: TextStyle(fontSize: 12, color: AppColors.textBody, height: 1.6)),
                  ],
                ),
              ),
            ],
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: timeline),
                const SizedBox(width: 18),
                Expanded(child: side),
              ],
            );
          }
          return Column(children: [timeline, const SizedBox(height: 18), side]);
        }),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            Text(v, style: const TextStyle(fontSize: 12.5, color: AppColors.text, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

final _mockTimeline = [
  const TimelineRailItem(
    state: RailItemState.done,
    icon: Icons.call_outlined,
    title: 'شكوى مواطن مسجّلة',
    timestamp: '2026-05-02 · 09:14',
    body: 'بلاغ عبر الهاتف بشأن تشققات ظاهرة في الواجهة الأمامية.',
    meta: 'بواسطة: مركز الاتصال — لينا فارس',
  ),
  const TimelineRailItem(
    state: RailItemState.done,
    icon: Icons.description_outlined,
    title: 'تقرير اللجنة الهندسية مستلم',
    timestamp: '2026-05-22 · 14:40',
    body: 'التقرير REP-2201 يوصي بتدعيم فوري للواجهة الأمامية.',
  ),
  const TimelineRailItem(
    state: RailItemState.current,
    icon: Icons.domain_verification_outlined,
    title: 'بانتظار زيارة التحقق من الامتثال',
    timestamp: 'مستحق: 2026-08-14',
    body: 'الإشعار نُشر على المبنى بتاريخ 2026-07-15.',
  ),
  const TimelineRailItem(
    state: RailItemState.pending,
    icon: Icons.more_horiz,
    title: 'امتثال → إغلاق آمن، أو عدم امتثال → تقييم خارجي',
  ),
];
