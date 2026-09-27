import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/parcel_status.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../intake/models/parcel.dart';
import 'data/parcels_repository.dart';

/// Parcel Registry — "سجلّ العقارات" (§7.2, FR-PAR-1..4).
///
/// Rebuilt from scratch against the real, live Parcel model that Intake
/// and every workflow screen (Triage, Review, Evacuation, Site Visit,
/// Assessment, Demolition) already read and write — replacing a previous
/// version of this screen built against a separate, richer
/// neighborhoods/buildings model that no real screen ever populated. See
/// the accompanying message for exactly what was retired.
class ParcelsListScreen extends ConsumerStatefulWidget {
  const ParcelsListScreen({super.key});

  @override
  ConsumerState<ParcelsListScreen> createState() => _ParcelsListScreenState();
}

class _ParcelsListScreenState extends ConsumerState<ParcelsListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _zoneFilter; // null = all zones
  ParcelStatus? _statusFilter; // null = all statuses

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _search = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ParcelsRepository get _repo => ref.read(parcelsRepositoryProvider);

  Future<void> _openNewParcelDialog() async {
    final parcelNoController = TextEditingController();
    final zoneController = TextEditingController();
    final addressController = TextEditingController();
    final buildingCountController = TextEditingController(text: '1');
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('عقار جديد'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) ...[
                  AppAlert(kind: AppAlertKind.danger, message: error!),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: parcelNoController,
                        decoration: const InputDecoration(labelText: 'رقم العقار'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: zoneController,
                        decoration: const InputDecoration(labelText: 'المنطقة العقارية'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: buildingCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'عدد المباني'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (parcelNoController.text.trim().isEmpty ||
                          zoneController.text.trim().isEmpty ||
                          addressController.text.trim().isEmpty) {
                        setSt(() => error = 'الرجاء تعبئة رقم العقار والمنطقة والعنوان.');
                        return;
                      }
                      setSt(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _repo.createParcel(
                          parcelNo: parcelNoController.text,
                          cadastralZone: zoneController.text,
                          address: addressController.text,
                          buildingCount: int.tryParse(buildingCountController.text) ?? 1,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setSt(() {
                          error = describeFirebaseError(e, 'تعذّر إنشاء العقار');
                          saving = false;
                        });
                      }
                    },
              child: Text(saving ? 'جارٍ الحفظ...' : 'إنشاء العقار'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parcelsAsync = ref.watch(_watchAllParcelsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'سجلّ العقارات',
          subtitle: 'كل العقارات المسجّلة في النظام، مع الحالة الحالية لكل عقار.',
          actions: [
            AppButton(label: 'عقار جديد', icon: Icons.add_business_outlined, onPressed: _openNewParcelDialog),
          ],
        ),
        const SizedBox(height: 22),
        parcelsAsync.when(
          loading: () => const AppCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, stack) => AppCard(
            child: AppAlert(
              kind: AppAlertKind.danger,
              title: 'تعذّر تحميل سجلّ العقارات',
              message: describeFirebaseError(error, 'تعذّر تحميل العقارات'),
            ),
          ),
          data: (parcels) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStats(parcels),
              const SizedBox(height: 18),
              _buildRegistry(parcels),
            ],
          ),
        ),
      ],
    );
  }

  // --- Summary ------------------------------------------------------------------

  static const _urgentStatuses = {
    ParcelStatus.urgentOnsite,
    ParcelStatus.evacuation,
    ParcelStatus.demolitionPending,
  };
  static const _closedStatuses = {ParcelStatus.closedSafe, ParcelStatus.demolished};

  Widget _buildStats(List<Parcel> parcels) {
    final urgent = parcels.where((p) => _urgentStatuses.contains(p.status)).length;
    final closed = parcels.where((p) => _closedStatuses.contains(p.status)).length;
    final open = parcels.length - closed;

    final cards = [
      StatCard(
        value: '${parcels.length}',
        label: 'إجمالي العقارات',
        icon: Icons.home_work_outlined,
        iconColor: AppColors.navy3,
        iconBackground: AppColors.iceTint,
      ),
      StatCard(
        value: '$open',
        label: 'حالات مفتوحة',
        icon: Icons.pending_actions_outlined,
        iconColor: AppColors.info,
        iconBackground: AppColors.infoBg,
      ),
      StatCard(
        value: '$urgent',
        label: 'تتطلب إجراءً عاجلًا',
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerBg,
      ),
      StatCard(
        value: '$closed',
        label: 'مغلقة',
        icon: Icons.task_alt,
        iconColor: AppColors.success,
        iconBackground: AppColors.successBg,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 480 ? 2 : 1);
      const gap = 14.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in cards) SizedBox(width: width, child: c)],
      );
    });
  }

  // --- Registry -----------------------------------------------------------------

  bool get _hasFilters => _search.isNotEmpty || _zoneFilter != null || _statusFilter != null;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _zoneFilter = null;
      _statusFilter = null;
    });
  }

  Widget _buildRegistry(List<Parcel> parcels) {
    final zones = parcels.map((p) => p.cadastralZone).where((z) => z.isNotEmpty).toSet().toList()..sort();
    // A selected zone that no longer exists in the live data would make the
    // dropdown assert — fall back to "all zones".
    if (_zoneFilter != null && !zones.contains(_zoneFilter)) _zoneFilter = null;

    final q = _search.toLowerCase();
    final filtered = parcels.where((p) {
      final matchesSearch = q.isEmpty ||
          p.id.toLowerCase().contains(q) ||
          p.parcelNo.toLowerCase().contains(q) ||
          p.cadastralZone.toLowerCase().contains(q) ||
          p.address.toLowerCase().contains(q);
      final matchesZone = _zoneFilter == null || p.cadastralZone == _zoneFilter;
      final matchesStatus = _statusFilter == null || p.status == _statusFilter;
      return matchesSearch && matchesZone && matchesStatus;
    }).toList()
      ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));

    return AppCardWithHeader(
      title: 'قائمة العقارات',
      icon: Icons.list_alt_outlined,
      trailing: _hasFilters ? '${filtered.length} من ${parcels.length}' : '${parcels.length} عقار',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: _buildFilters(zones),
          ),
          const Divider(height: 1),
          if (parcels.isEmpty)
            const AppEmptyState(
              icon: Icons.home_work_outlined,
              title: 'لا توجد عقارات مسجّلة بعد',
              description: 'تُضاف العقارات تلقائيًا عند تسجيل شكوى جديدة، أو يمكن إنشاء عقار مباشرةً من هذه الشاشة.',
            )
          else if (filtered.isEmpty)
            Column(
              children: [
                const AppEmptyState(
                  icon: Icons.search_off,
                  title: 'لا نتائج مطابقة',
                  description: 'لم يُعثر على عقارات مطابقة لبحثك أو عوامل التصفية المحددة.',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('مسح عوامل التصفية'),
                  ),
                ),
              ],
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact) _buildHeaderRow(),
                  for (var i = 0; i < filtered.length; i++)
                    compact
                        ? _buildCompactRow(filtered[i], isLast: i == filtered.length - 1)
                        : _buildWideRow(filtered[i], isLast: i == filtered.length - 1),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildFilters(List<String> zones) {
    final search = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'ابحث برقم العقار أو المنطقة أو العنوان...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _searchController.clear,
              ),
      ),
    );
    final zone = DropdownButtonFormField<String?>(
      value: _zoneFilter,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'المنطقة العقارية'),
      items: [
        const DropdownMenuItem(value: null, child: Text('كل المناطق')),
        ...zones.map((z) => DropdownMenuItem(value: z, child: Text(z, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: (v) => setState(() => _zoneFilter = v),
    );
    final status = DropdownButtonFormField<ParcelStatus?>(
      value: _statusFilter,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'الحالة'),
      items: [
        const DropdownMenuItem(value: null, child: Text('كل الحالات')),
        ...ParcelStatus.values
            .map((s) => DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: (v) => setState(() => _statusFilter = v),
    );
    final clear = IconButton(
      tooltip: 'مسح عوامل التصفية',
      onPressed: _hasFilters ? _clearFilters : null,
      icon: const Icon(Icons.filter_alt_off_outlined),
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: zone),
                const SizedBox(width: 12),
                Expanded(child: status),
                clear,
              ],
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(flex: 3, child: search),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: zone),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: status),
          const SizedBox(width: 4),
          clear,
        ],
      );
    });
  }

  // Column flexes shared by the header and each wide row so they line up.
  static const _flexId = 3, _flexAddress = 4, _flexZone = 2, _flexStatus = 3, _flexDate = 2;

  Widget _buildHeaderRow() {
    Widget h(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        );
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          h('العقار', _flexId),
          h('العنوان', _flexAddress),
          h('المنطقة', _flexZone),
          h('الحالة', _flexStatus),
          h('آخر تحديث', _flexDate),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  /// The whole row is the tap target — no separate "عرض" button to aim for.
  Widget _rowShell({required Parcel parcel, required bool isLast, required Widget child}) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => context.go('/parcels/${parcel.id}'),
        hoverColor: AppColors.iceTint,
        child: Container(
          decoration: BoxDecoration(
            border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildWideRow(Parcel parcel, {required bool isLast}) {
    return _rowShell(
      parcel: parcel,
      isLast: isLast,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(flex: _flexId, child: _idCell(parcel)),
            Expanded(
              flex: _flexAddress,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(
                  parcel.address.isEmpty ? '—' : parcel.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.4),
                ),
              ),
            ),
            Expanded(
              flex: _flexZone,
              child: Text(
                parcel.cadastralZone.isEmpty ? '—' : parcel.cadastralZone,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textBody),
              ),
            ),
            Expanded(
              flex: _flexStatus,
              child: Align(alignment: AlignmentDirectional.centerStart, child: StatusBadge(status: parcel.status)),
            ),
            Expanded(
              flex: _flexDate,
              child: Text(
                parcel.updatedAt == null ? '—' : _fmt(parcel.updatedAt!),
                style: AppTypography.mono(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            const Icon(Icons.chevron_left, size: 20, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactRow(Parcel parcel, {required bool isLast}) {
    final meta = [
      if (parcel.cadastralZone.isNotEmpty) parcel.cadastralZone,
      if (parcel.updatedAt != null) 'آخر تحديث ${_fmt(parcel.updatedAt!)}',
    ].join('  ·  ');

    return _rowShell(
      parcel: parcel,
      isLast: isLast,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _idCell(parcel)),
                      const SizedBox(width: 8),
                      StatusBadge(status: parcel.status, dense: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 14, color: AppColors.textFaint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          parcel.address.isEmpty ? '—' : parcel.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textBody),
                        ),
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(meta, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_left, size: 20, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _idCell(Parcel parcel) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: parcel.status.backgroundColor, borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.home_work_outlined, size: 17, color: parcel.status.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parcel.id,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: AppColors.text),
              ),
              if (parcel.parcelNo.isNotEmpty && parcel.parcelNo != parcel.id)
                Text(
                  'رقم ${parcel.parcelNo}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final _watchAllParcelsProvider = StreamProvider<List<Parcel>>((ref) {
  return ref.watch(parcelsRepositoryProvider).watchAllParcels();
});
