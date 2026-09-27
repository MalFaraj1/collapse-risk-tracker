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
            final timelinePanel = _buildTimelinePanel();
            if (!isWide) return Column(children: [infoPanel, const SizedBox(height: 18), timelinePanel]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoPanel),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: timelinePanel),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The page's anchor: a navy banner carrying the parcel's identity (ID +
  /// status), its address, and a row of quick-glance facts, so the key
  /// information reads before the user scrolls into the detail panels.
  Widget _buildHero(Parcel parcel) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppColors.navy, AppColors.navy3],
        ),
        boxShadow: const [BoxShadow(color: Color(0x261B2A4A), blurRadius: 24, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Soft decorative glyph so the banner doesn't read as a flat slab.
          PositionedDirectional(
            end: -24,
            bottom: -36,
            child: Icon(Icons.domain, size: 160, color: Colors.white.withOpacity(0.05)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: Colors.white.withOpacity(0.1),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => context.go('/parcels'),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تفاصيل العقار',
                            style: TextStyle(fontSize: 12, color: AppColors.ice, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(parcel.id, style: AppTypography.mono(fontSize: 24, weight: FontWeight.w800, color: Colors.white)),
                              StatusBadge(status: parcel.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.place_outlined, size: 15, color: AppColors.gold),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  parcel.address.isEmpty ? 'لا يوجد عنوان مسجَّل' : parcel.address,
                                  style: const TextStyle(fontSize: 13.5, color: AppColors.ice),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _heroChip(Icons.tag, 'رقم العقار', parcel.parcelNo),
                    _heroChip(Icons.map_outlined, 'المنطقة العقارية', parcel.cadastralZone),
                    _heroChip(Icons.history, 'السجلات', _timeline.length.toString()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.gold),
            const SizedBox(width: 6),
            Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.ice)),
            Text(
              value.isEmpty ? '—' : value,
              style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      );

  Widget _buildInfoPanel(Parcel parcel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCardWithHeader(
          title: 'بيانات العقار',
          icon: Icons.badge_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              children: [
                _kv(Icons.tag, 'رقم العقار', parcel.parcelNo),
                _kv(Icons.map_outlined, 'المنطقة العقارية', parcel.cadastralZone),
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
      trailing: _timeline.isEmpty ? null : '${_timeline.length} سجل',
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

  Widget _kv(IconData icon, String k, String v, {bool isLast = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: AppColors.iceTint, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15, color: AppColors.navy3),
            ),
            const SizedBox(width: 10),
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const Spacer(),
            Flexible(
              child: Text(v.isEmpty ? '—' : v,
                  textAlign: TextAlign.end,
                  style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: AppColors.text)),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}