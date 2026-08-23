import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';

/// Due Actions dashboard (§7.8, FR-DASH-1..5) — the pull-based work queue
/// that's the system's entire reminder mechanism (no push notifications,
/// by design).
///
/// This screen is built out as a full reference example of the design
/// system in action. The data below is placeholder — TODO(Phase 3): replace
/// with a StreamProvider reading `decisions` + `siteVisits` filtered by
/// execution date and the current user's role/team, per FR-DASH-1/2.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'الإجراءات المستحقة',
          subtitle: 'قائمة العمل التفاعلية — كل الإجراءات المتأخرة أو المستحقة قريبًا حسب دورك الحالي (§7.8).',
          actions: [
            AppButton(label: 'تصفية متقدمة', icon: Icons.tune, variant: AppButtonVariant.outline, onPressed: () {}),
            AppButton(label: 'شكوى جديدة', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final cards = [
              const StatCard(value: '7', label: 'إجراءات متأخرة', icon: Icons.warning_amber_rounded,
                  iconColor: AppColors.danger, iconBackground: AppColors.dangerBg),
              const StatCard(value: '12', label: 'مستحقة خلال 7 أيام', icon: Icons.schedule,
                  iconColor: AppColors.warning, iconBackground: AppColors.warningBg),
              const StatCard(value: '4', label: 'بانتظار زيارة ميدانية', icon: Icons.domain_verification_outlined,
                  iconColor: AppColors.info, iconBackground: AppColors.infoBg),
              const StatCard(value: '28', label: 'أُغلقت هذا الشهر', icon: Icons.task_alt,
                  iconColor: AppColors.success, iconBackground: AppColors.successBg),
            ];
            return GridView.count(
              crossAxisCount: isWide ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.7,
              children: cards,
            );
          },
        ),
        const SizedBox(height: 20),
        AppCardWithHeader(
          title: 'قائمة العمل',
          icon: Icons.format_list_bulleted,
          trailing: 'مرتبة حسب تاريخ الاستحقاق',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('العقار')),
                DataColumn(label: Text('الإجراء')),
                DataColumn(label: Text('الحالة')),
                DataColumn(label: Text('تاريخ الاستحقاق')),
                DataColumn(label: Text('الفريق المسؤول')),
                DataColumn(label: Text('')),
              ],
              rows: _mockRows.map((r) => _buildRow(context, r)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildRow(BuildContext context, _MockDueItem item) {
    return DataRow(cells: [
      DataCell(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.address, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
          Text(item.parcelId, style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
        ],
      )),
      DataCell(Text(item.action)),
      DataCell(Pill(
        label: item.overdue ? 'متأخر ${item.dueLabel}' : 'مستحق ${item.dueLabel}',
        color: item.overdue ? Colors.white : AppColors.warning,
        backgroundColor: item.overdue ? AppColors.danger : AppColors.warningBg,
      )),
      DataCell(Text(item.dueDate, style: AppTypography.mono(fontSize: 12))),
      DataCell(RolePill(label: item.team, icon: item.teamIcon)),
      DataCell(AppButton(
        label: item.overdue ? 'بدء زيارة' : 'عرض',
        variant: item.overdue ? AppButtonVariant.primary : AppButtonVariant.outline,
        dense: true,
        onPressed: () {},
      )),
    ]);
  }
}

class _MockDueItem {
  const _MockDueItem(this.address, this.parcelId, this.action, this.overdue, this.dueLabel, this.dueDate, this.team, this.teamIcon);
  final String address, parcelId, action, dueLabel, dueDate, team;
  final bool overdue;
  final IconData teamIcon;
}

const _mockRows = [
  _MockDueItem('شارع المعرض، طرابلس', 'PARCEL-4471-Z12', 'إنذار تدعيم — زيارة امتثال', true, '4 أيام', '2026-08-14', 'هندسي', Icons.engineering_outlined),
  _MockDueItem('حي التل، مبنى 12', 'PARCEL-2098-Z04', 'إخلاء — تحقق امتثال 48 س', true, 'يوم واحد', '2026-08-17', 'شرطة', Icons.local_police_outlined),
  _MockDueItem('جادة عبد الحميد كرامي', 'PARCEL-3350-Z09', 'إنذار ترميم — تحقق امتثال', false, 'خلال يومين', '2026-08-20', 'هندسي', Icons.engineering_outlined),
];
