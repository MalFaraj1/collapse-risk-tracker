import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/google_map_card.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/timeline_rail.dart';
import '../admin/data/admin_repository.dart';
import '../audit/data/audit_log_repository.dart';
import '../audit/models/audit_log_entry.dart';
import '../intake/models/parcel.dart';
import 'data/parcels_repository.dart';

/// Parcel Detail — "تفاصيل العقار" (§7.2, FR-PAR-2/3/4).
///
/// Shows the parcel's own data plus a merged chronological timeline of
/// its cases, complaints, decisions, and notices. Every field Intake
/// saves on a complaint — channel, narrative, contact info, and every
/// attached photo/video — is shown here, not just the narrative. The
/// location card links out to real Google Maps for directions, using the
/// same [GoogleMapCard] component built for exactly this purpose.
class ParcelDetailScreen extends ConsumerStatefulWidget {
  const ParcelDetailScreen({super.key, required this.parcelId});

  final String parcelId;

  @override
  ConsumerState<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends ConsumerState<ParcelDetailScreen> {
  bool _loading = true;
  String? _loadError;
  Parcel? _parcel;
  List<ParcelTimelineEntry> _timeline = [];

  ParcelsRepository get _repo => ref.read(parcelsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final parcel = await _repo.getParcel(widget.parcelId);
      if (parcel == null) {
        if (mounted) {
          setState(() {
            _loadError = 'العقار غير موجود.';
            _loading = false;
          });
        }
        return;
      }
      final timeline = await _repo.getTimeline(widget.parcelId);
      if (!mounted) return;
      setState(() {
        _parcel = parcel;
        _timeline = timeline;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = describeFirebaseError(e, 'تعذّر تحميل بيانات العقار');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null || _parcel == null) {
      return AppCard(child: AppAlert(kind: AppAlertKind.danger, title: 'تعذّر التحميل', message: _loadError ?? ''));
    }

    final parcel = _parcel!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHero(parcel),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final infoPanel = _buildInfoPanel(parcel);
            final rightColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelinePanel(),
                const SizedBox(height: 18),
                _buildAuditTrailPanel(),
              ],
            );
            if (!isWide) return Column(children: [infoPanel, const SizedBox(height: 18), rightColumn]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoPanel),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: rightColumn),
              ],
            );
          },
        ),
      ],
    );
  }

  /// A proper header treatment — replacing a plain title row — that reads
  /// as the anchor for the whole page: a back affordance, the parcel's
  /// identity (ID + status) at real prominence, and its address directly
  /// beneath, all in one bordered surface rather than bare text floating
  /// on the page background.
  Widget _buildHero(Parcel parcel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A1B2A4A), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.go('/parcels'),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
              child: const Icon(Icons.arrow_forward, size: 18, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(parcel.id, style: AppTypography.mono(fontSize: 22, weight: FontWeight.w800, color: AppColors.text)),
                    StatusBadge(status: parcel.status),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        parcel.address.isEmpty ? 'لا يوجد عنوان مسجَّل' : parcel.address,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(Parcel parcel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCardWithHeader(
          title: 'بيانات العقار',
          icon: Icons.badge_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              children: [
                _kv(Icons.tag, 'رقم العقار', parcel.parcelNo),
                _kv(Icons.map_outlined, 'المنطقة العقارية', parcel.cadastralZone),
                _kv(Icons.apartment_outlined, 'عدد المباني', parcel.buildingCount.toString()),
                _kv(Icons.event_outlined, 'تاريخ الإنشاء', parcel.createdAt == null ? '—' : _fmt(parcel.createdAt!)),
                _kv(Icons.update_outlined, 'آخر تحديث', parcel.updatedAt == null ? '—' : _fmt(parcel.updatedAt!), isLast: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppCardWithHeader(
          title: 'الموقع',
          icon: Icons.map_outlined,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: parcel.hasLocation
                ? GoogleMapCard(
                    latitude: parcel.latitude!,
                    longitude: parcel.longitude!,
                    markerLabel: parcel.address.isEmpty ? parcel.id : parcel.address,
                  )
                : const NoLocationPlaceholder(canSetLocation: false, onSetLocation: _noop),
          ),
        ),
      ],
    );
  }

  static void _noop() {}

  Widget _buildTimelinePanel() {
    return AppCardWithHeader(
      title: 'الخط الزمني للعقار',
      icon: Icons.history,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _timeline.isEmpty
            ? const AppEmptyState(
                icon: Icons.history_toggle_off,
                title: 'لا يوجد سجلّ بعد',
                description: 'ستظهر هنا الشكاوى والحالات والقرارات والإشعارات المرتبطة بهذا العقار فور تسجيلها.',
              )
            : TimelineRail(
                items: _timeline
                    .map((e) => TimelineRailItem(
                          state: RailItemState.done,
                          icon: e.icon,
                          title: e.title,
                          body: e.subtitle,
                          meta: _fmt(e.timestamp),
                          trailing: _buildEntryExtra(e),
                        ))
                    .toList(),
              ),
      ),
    );
  }

  /// Renders everything Intake saved on a complaint that a plain
  /// title/body/meta row can't express: the complainant's contact info
  /// and every photo/video attached to it. Returns null for non-complaint
  /// entries (no contact, no media), so they render exactly as before.
  Widget? _buildEntryExtra(ParcelTimelineEntry e) {
    final hasContact = e.complainantContact != null && e.complainantContact!.trim().isNotEmpty;
    final hasMedia = e.mediaUrls.isNotEmpty;
    if (!hasContact && !hasMedia) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContact)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.call_outlined, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Text('جهة الاتصال: ${e.complainantContact}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
        if (hasMedia)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final url in e.mediaUrls) MediaThumbnail(url: url, size: 64)],
          ),
      ],
    );
  }

  /// FR-AUD-2/3: the raw, field-level audit trail — distinct from the
  /// narrative timeline above it. The timeline tells the STORY of a
  /// parcel ("a complaint came in, then a decision was made"); this shows
  /// the literal, attributable log of every write, which is what NFR-3's
  /// accountability requirement is actually asking for.
  Widget _buildAuditTrailPanel() {
    final auditAsync = ref.watch(parcelAuditLogProvider(widget.parcelId));
    final usersAsync = ref.watch(usersProvider);
    final users = usersAsync.valueOrNull;

    String actorName(String uid) {
      if (uid.isEmpty) return '—';
      final match = users?.where((u) => u.uid == uid).toList();
      if (match == null || match.isEmpty) return 'مستخدم غير مسجَّل في الدليل';
      final u = match.first;
      return u.displayName.isEmpty ? u.email : u.displayName;
    }

    return AppCardWithHeader(
      title: 'سجلّ التدقيق',
      icon: Icons.fact_check_outlined,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: auditAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
          error: (e, _) => AppAlert(kind: AppAlertKind.danger, message: describeFirebaseError(e, 'تعذّر تحميل سجلّ التدقيق')),
          data: (entries) => entries.isEmpty
              ? const AppEmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'لا يوجد سجلّ تدقيق بعد',
                  description: 'سيظهر هنا كل تغيير مرتبط بهذا العقار: من قام به، ومتى.',
                )
              : Column(
                  children: [
                    for (final entry in entries) _auditRow(entry, actorName(entry.actorUid)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _auditRow(AuditLogEntry entry, String actor) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 1))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(color: AppColors.iceTint, borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.bolt, size: 14, color: AppColors.navy3),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.summary, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                  const SizedBox(height: 3),
                  Text(
                    '$actor  ·  ${entry.timestamp == null ? '—' : _fmt(entry.timestamp!)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _kv(IconData icon, String k, String v, {bool isLast = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 8),
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const Spacer(),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: AppColors.text)),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
