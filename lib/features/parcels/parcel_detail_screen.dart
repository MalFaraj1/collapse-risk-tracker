import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../core/constants/roles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/timeline_rail.dart';
import '../auth/auth_providers.dart';
import 'models/building.dart';
import 'models/parcel.dart';
import 'models/parcel_attachment.dart';
import 'providers/parcels_providers.dart';
import 'widgets/add_building_dialog.dart';
import 'widgets/attachment_upload_button.dart';
import 'widgets/edit_address_dialog.dart';

/// Parcel detail & timeline (§5.1, FR-PAR-3) — fully wired to Firestore for
/// everything the Parcels feature itself owns: the parcel record, its
/// buildings, its attachments, and the read-only prior-cases check (BR-3).
///
/// The timeline currently includes real events from those three sources
/// only. As Intake, Review, Actions, etc. are built, extend
/// [_buildTimelineItems] below to merge in their collections too — see the
/// TODO comment at the bottom of that function for the exact pattern to
/// follow. This screen deliberately does not fabricate placeholder entries
/// for features that don't exist yet.
class ParcelDetailScreen extends ConsumerWidget {
  const ParcelDetailScreen({super.key, required this.parcelId});

  final String parcelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parcelAsync = ref.watch(parcelProvider(parcelId));

    return parcelAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => AppEmptyState(icon: Icons.error_outline, title: 'تعذّر تحميل بيانات العقار', description: err.toString()),
      data: (parcel) {
        if (parcel == null) {
          return const AppEmptyState(icon: Icons.search_off, title: 'العقار غير موجود', description: 'قد يكون الرابط غير صحيح أو تم حذفه.');
        }
        return _ParcelDetailBody(parcel: parcel);
      },
    );
  }
}

class _ParcelDetailBody extends ConsumerWidget {
  const _ParcelDetailBody({required this.parcel});
  final Parcel parcel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildingsAsync = ref.watch(parcelBuildingsProvider(parcel.id));
    final attachmentsAsync = ref.watch(parcelAttachmentsProvider(parcel.id));
    final priorCasesAsync = ref.watch(parcelPriorCasesProvider(parcel.id));
    final roleAsync = ref.watch(currentUserRoleProvider);
    final canEdit = {AppRole.callCenter, AppRole.engineering, AppRole.admin}.contains(roleAsync.valueOrNull);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('${parcel.parcelNo}-${parcel.cadastralZone}', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(width: 10),
                      StatusBadge(status: parcel.status),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(child: Text(parcel.address, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
                          tooltip: 'تعديل العنوان',
                          onPressed: () => EditAddressDialog.show(context, parcelId: parcel.id, currentAddress: parcel.address),
                        ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;

            final timeline = AppCardWithHeader(
              title: 'الخط الزمني للحالة',
              icon: Icons.timeline_outlined,
              contentPadding: const EdgeInsets.all(20),
              child: buildingsAsync.when(
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                error: (e, _) => Text('تعذّر تحميل الخط الزمني: $e'),
                data: (buildings) => attachmentsAsync.when(
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                  error: (e, _) => Text('تعذّر تحميل الخط الزمني: $e'),
                  data: (attachments) {
                    final items = _buildTimelineItems(parcel, buildings, attachments);
                    if (items.isEmpty) {
                      return const AppEmptyState(icon: Icons.timeline_outlined, title: 'لا توجد أحداث بعد');
                    }
                    return TimelineRail(items: items);
                  },
                ),
              ),
            );

            final side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('المباني', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        const Spacer(),
                        if (canEdit)
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.navy),
                            tooltip: 'إضافة مبنى',
                            onPressed: () => AddBuildingDialog.show(context, parcelId: parcel.id),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      buildingsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('خطأ: $e', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                        data: (buildings) {
                          if (buildings.isEmpty) {
                            return const Text('لا توجد مبانٍ مسجّلة بعد.', style: TextStyle(fontSize: 12, color: AppColors.textMuted));
                          }
                          return Column(
                            children: buildings
                                .map((b) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(children: [
                                        const Icon(Icons.apartment, size: 15, color: AppColors.textMuted),
                                        const SizedBox(width: 8),
                                        Text(
                                          b.floors != null ? '${b.floors} طوابق${b.description != null ? " — ${b.description}" : ""}' : (b.description ?? 'مبنى'),
                                          style: const TextStyle(fontSize: 12.5),
                                        ),
                                      ]),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('المرفقات', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        AttachmentUploadButton(parcelId: parcel.id),
                      ]),
                      const SizedBox(height: 10),
                      attachmentsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('خطأ: $e', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                        data: (attachments) {
                          if (attachments.isEmpty) {
                            return const Text('لا توجد مرفقات بعد.', style: TextStyle(fontSize: 12, color: AppColors.textMuted));
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: attachments
                                .map((a) => _AttachmentThumb(key: ValueKey(a.id), attachment: a))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                priorCasesAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (cases) => AppCard(
                    backgroundColor: AppColors.iceTint,
                    borderColor: AppColors.ice,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('حالات سابقة على هذا العقار', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        const SizedBox(height: 8),
                        if (cases.isEmpty)
                          const Text(
                            'لا توجد حالات سابقة مغلقة على هذا العقار. هذه أول حالة مسجّلة (BR-3).',
                            style: TextStyle(fontSize: 12, color: AppColors.textBody, height: 1.6),
                          )
                        else
                          Column(
                            children: cases
                                .map((c) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Text(
                                        '${c.id} — ${c.status}${c.lastUpdatedAt != null ? " — ${_formatDate(c.lastUpdatedAt!)}" : ""}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textBody),
                                      ),
                                    ))
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(flex: 2, child: timeline), const SizedBox(width: 18), Expanded(child: side)],
              );
            }
            return Column(children: [timeline, const SizedBox(height: 18), side]);
          }),
        ],
      ),
    );
  }

  /// Merges every real timeline source this feature currently owns, sorted
  /// chronologically. Returns an empty list gracefully if timestamps are
  /// still resolving (serverTimestamp() reads as null until the server
  /// round-trip completes) rather than crashing on a null comparison.
  List<TimelineRailItem> _buildTimelineItems(Parcel parcel, List<Building> buildings, List<ParcelAttachment> attachments) {
    final events = <(DateTime, TimelineRailItem)>[];

    if (parcel.createdAt != null) {
      events.add((
        parcel.createdAt!,
        TimelineRailItem(
          state: RailItemState.done,
          icon: Icons.add_home_outlined,
          title: 'تم إنشاء سجلّ العقار',
          timestamp: _formatDateTime(parcel.createdAt!),
        ),
      ));
    }

    for (final b in buildings) {
      if (b.createdAt == null) continue;
      events.add((
        b.createdAt!,
        TimelineRailItem(
          state: RailItemState.done,
          icon: Icons.apartment_outlined,
          title: 'تمت إضافة مبنى',
          timestamp: _formatDateTime(b.createdAt!),
          body: b.floors != null ? '${b.floors} طوابق' : null,
        ),
      ));
    }

    for (final a in attachments) {
      if (a.uploadedAt == null) continue;
      events.add((
        a.uploadedAt!,
        TimelineRailItem(
          state: RailItemState.done,
          icon: a.type == AttachmentType.pdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
          title: 'تم رفع مرفق',
          timestamp: _formatDateTime(a.uploadedAt!),
          body: a.fileName,
        ),
      ));
    }

    events.sort((x, y) => x.$1.compareTo(y.$1));

    // TODO(Phase 3): as each feature below is built, merge its collection in
    // here the same way — fetch via its own StreamProvider.family(parcel.id
    // or case id), map each doc to a TimelineRailItem, add to `events`
    // before the final sort. Do this for: complaints, reports, reviews,
    // decisions, notices, evacuationExecutions, siteVisits, assessments,
    // restorationStudies, demolitionOrders. Mark the most recent unresolved
    // one as RailItemState.current and everything after it as .pending, to
    // match this screen's original design intent.

    return events.map((e) => e.$2).toList();
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _formatDateTime(DateTime d) =>
      '${_formatDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({super.key, required this.attachment});
  final ParcelAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: attachment.fileName,
      child: InkWell(
        onTap: () {
          // Opens the file in a new browser tab on Flutter Web. On other
          // platforms, replace with a package like url_launcher.
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.navy2, borderRadius: BorderRadius.circular(9)),
          child: Icon(
            attachment.type == AttachmentType.pdf ? Icons.picture_as_pdf : Icons.image,
            color: AppColors.ice,
          ),
        ),
      ),
    );
  }
}