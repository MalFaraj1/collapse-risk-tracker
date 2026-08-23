import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/parcel_status.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';

/// Parcel registry (FR-PAR-1..4).
/// TODO(Phase 3): replace mock rows with a StreamProvider over `parcels`,
/// with search-by-(parcel_no, cadastral_zone) per FR-PAR-1/FR-INT-2.
class ParcelsListScreen extends StatelessWidget {
  const ParcelsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'سجلّ العقارات',
          subtitle: 'كل العقارات المسجّلة في النظام، مع الحالة الحالية لكل عقار.',
          actions: [AppButton(label: 'عقار جديد', icon: Icons.add_business_outlined, onPressed: () {})],
        ),
        const SizedBox(height: 18),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('العقار')),
                DataColumn(label: Text('العنوان')),
                DataColumn(label: Text('الحالة')),
                DataColumn(label: Text('آخر إجراء')),
                DataColumn(label: Text('')),
              ],
              rows: _mock.map((p) {
                return DataRow(
                  onSelectChanged: (_) => context.go('/parcels/${p.id}'),
                  cells: [
                    DataCell(Text(p.id, style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700))),
                    DataCell(Text(p.address)),
                    DataCell(StatusBadge(status: p.status)),
                    DataCell(Text(p.lastAction, style: const TextStyle(fontSize: 12.5))),
                    const DataCell(Icon(Icons.chevron_left, color: AppColors.textFaint)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _MockParcel {
  const _MockParcel(this.id, this.address, this.status, this.lastAction);
  final String id, address, lastAction;
  final ParcelStatus status;
}

const _mock = [
  _MockParcel('PARCEL-4471-Z12', 'شارع المعرض، طرابلس', ParcelStatus.awaitingCompliance, 'إنذار تدعيم صادر'),
  _MockParcel('PARCEL-2098-Z04', 'حي التل، مبنى 12', ParcelStatus.evacuation, 'أمر إخلاء نُشر'),
  _MockParcel('PARCEL-9042-Z07', 'ساحة النجمة', ParcelStatus.inAssessment, 'أُرسل لخطيب وعلمي'),
  _MockParcel('PARCEL-5521-Z03', 'حي القبة', ParcelStatus.demolitionPending, 'إشعار هدم صادر'),
  _MockParcel('PARCEL-0765-Z01', 'شارع ميناء الحصن', ParcelStatus.closedSafe, 'تم التحقق من الترميم'),
];
