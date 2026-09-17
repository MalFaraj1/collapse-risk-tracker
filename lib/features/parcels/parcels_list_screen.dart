import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/parcel_status.dart';
import '../../core/constants/roles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../auth/auth_providers.dart';
import 'models/parcel.dart';
import 'providers/parcels_providers.dart';
import 'widgets/new_parcel_dialog.dart';

/// Parcel registry (FR-PAR-1..4) — fully wired to Firestore.
class ParcelsListScreen extends ConsumerWidget {
  const ParcelsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parcelsAsync = ref.watch(filteredParcelsProvider);
    final roleAsync = ref.watch(currentUserRoleProvider);
    final canCreate = roleAsync.valueOrNull != null &&
        {AppRole.callCenter, AppRole.engineering, AppRole.admin}.contains(roleAsync.valueOrNull);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'سجلّ العقارات',
          subtitle: 'كل العقارات المسجّلة في النظام، مع الحالة الحالية لكل عقار.',
          actions: [
            if (canCreate)
              AppButton(
                label: 'عقار جديد',
                icon: Icons.add_business_outlined,
                onPressed: () async {
                  final newId = await NewParcelDialog.show(context);
                  if (newId != null && context.mounted) {
                    context.go('/parcels/$newId');
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 18),
        _FilterBar(resultCount: parcelsAsync.valueOrNull?.length),
        const SizedBox(height: 14),
        parcelsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => AppEmptyState(
            icon: Icons.error_outline,
            title: 'تعذّر تحميل سجلّ العقارات',
            description: err.toString(),
          ),
          data: (parcels) {
            if (parcels.isEmpty) {
              return const AppEmptyState(
                icon: Icons.home_work_outlined,
                title: 'لا توجد عقارات مطابقة',
                description: 'جرّب تعديل كلمة البحث أو الفلاتر، أو أضف عقارًا جديدًا.',
              );
            }
            return AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 320),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('العقار')),
                      DataColumn(label: Text('العنوان')),
                      DataColumn(label: Text('الحالة')),
                      DataColumn(label: Text('آخر تحديث')),
                      DataColumn(label: Text('')),
                    ],
                    rows: parcels.map((p) => _buildRow(context, p)).toList(),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  DataRow _buildRow(BuildContext context, Parcel p) {
    return DataRow(
      key: ValueKey(p.id),
      onSelectChanged: (_) => context.go('/parcels/${p.id}'),
      cells: [
        DataCell(Text('${p.parcelNo}-${p.cadastralZone}', style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700))),
        DataCell(Text(p.address, overflow: TextOverflow.ellipsis)),
        DataCell(StatusBadge(status: p.status)),
        DataCell(Text(
          p.updatedAt != null ? _formatDate(p.updatedAt!) : '—',
          style: AppTypography.mono(fontSize: 12),
        )),
        const DataCell(Icon(Icons.chevron_left, color: AppColors.textFaint)),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.resultCount});
  final int? resultCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilter = ref.watch(parcelStatusFilterProvider);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'ابحث برقم العقار أو المنطقة العقارية أو العنوان...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (value) => ref.read(parcelSearchQueryProvider.notifier).state = value,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<ParcelStatus?>(
            value: statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            hint: const Text('كل الحالات', style: TextStyle(fontSize: 13)),
            items: [
              const DropdownMenuItem(value: null, child: Text('كل الحالات')),
              ...ParcelStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))),
            ],
            onChanged: (value) => ref.read(parcelStatusFilterProvider.notifier).state = value,
          ),
        ),
        const SizedBox(width: 16),
        if (resultCount != null)
          Text('$resultCount عقار', style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }
}