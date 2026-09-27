import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/excel_export/excel_export.dart';
import '../../core/pdf/report_pdf_builder.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/web_download.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import 'data/reports_repository.dart';

/// Reports Hub — "التقارير" (§9, R1\u2013R7).
///
/// Five of the seven specified reports are fully implemented \u2014 R1, R2,
/// R3, R5, R7 \u2014 each backed by real Firestore data via
/// [ReportsRepository], each exportable as both PDF and Excel through the
/// shared builders in core/pdf and core/excel_export.
///
/// R4 (per-team workload) and R6 (full case audit trail) are shown but
/// disabled with an explicit reason rather than built as fake buttons:
/// R4 needs a user/role directory to attribute work to a team, which
/// doesn't exist until Admin Settings is built; R6 needs an AuditLog
/// collection, which was never created anywhere in this Flutter/Firebase
/// project. Both are genuine, disclosed infrastructure gaps, not
/// oversights in this screen.
///
/// Every export uses the FULL current dataset \u2014 there is no per-report
/// filter dialog yet, even though \u00a79 lists filters (zone/team/window)
/// for some reports. Adding those is the same shape of work as the
/// reports themselves, not a different mechanism: a small filter row
/// above the export buttons, feeding the same ReportsRepository methods,
/// which already accept the relevant optional parameters.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _busyReportId;
  String? _error;

  ReportsRepository get _repo => ref.read(reportsRepositoryProvider);

  Future<void> _export({
    required String reportId,
    required String title,
    required String subtitle,
    required Future<ReportResult> Function() fetch,
    required bool asPdf,
  }) async {
    setState(() {
      _busyReportId = reportId;
      _error = null;
    });
    try {
      final result = await fetch();
      if (asPdf) {
        final bytes = await buildReportPdf(title: title, subtitle: subtitle, headers: result.headers, rows: result.rows);
        downloadBytes(bytes, '$reportId.pdf', 'application/pdf');
      } else {
        final bytes = buildExcelWorkbook(sheetName: reportId, headers: result.headers, rows: result.rows);
        downloadBytes(bytes, '$reportId.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر إنشاء التقرير'));
    } finally {
      if (mounted) setState(() => _busyReportId = null);
    }
  }

  String _currentMonthLabel() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('التقارير', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'سبعة تقارير إدارية جاهزة للتصدير بصيغة PDF أو Excel، بالعربية RTL (§9).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _error!),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1100 ? 3 : (constraints.maxWidth > 700 ? 2 : 1);
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _reportCard(
                  id: 'R1',
                  icon: Icons.description_outlined,
                  title: 'ملخص حالة العقارات \u2014 R1',
                  description: 'الحالة الحالية وآخر تحديث لكل عقار.',
                  onExport: (asPdf) => _export(
                    reportId: 'R1',
                    title: 'ملخص حالة العقارات',
                    subtitle: 'الحالة الحالية وآخر تحديث لكل عقار',
                    fetch: () => _repo.buildR1ParcelStatusSummary(),
                    asPdf: asPdf,
                  ),
                ),
                _reportCard(
                  id: 'R2',
                  icon: Icons.bar_chart_outlined,
                  title: 'العقارات حسب المرحلة \u2014 R2',
                  description: 'أعداد العقارات مصنّفة حسب الحالة الحالية.',
                  onExport: (asPdf) => _export(
                    reportId: 'R2',
                    title: 'العقارات حسب المرحلة',
                    subtitle: 'أعداد العقارات مصنّفة حسب الحالة الحالية',
                    fetch: () => _repo.buildR2ParcelsByStage(),
                    asPdf: asPdf,
                  ),
                ),
                _reportCard(
                  id: 'R3',
                  icon: Icons.warning_amber_rounded,
                  title: 'إجراءات متأخرة ومستحقة \u2014 R3',
                  description: 'الإجراءات غير المنجزة المتأخرة أو المستحقة خلال 7 أيام.',
                  onExport: (asPdf) => _export(
                    reportId: 'R3',
                    title: 'الإجراءات المتأخرة والمستحقة',
                    subtitle: 'الإجراءات غير المنجزة المستحقة خلال 7 أيام أو المتأخرة',
                    fetch: () => _repo.buildR3OverdueAndUpcoming(),
                    asPdf: asPdf,
                  ),
                ),
                _reportCard(
                  id: 'R4',
                  icon: Icons.groups_outlined,
                  title: 'نشاط كل فريق \u2014 R4',
                  description: 'الإجراءات والزيارات الميدانية لكل فريق خلال فترة محددة.',
                  unavailableReason: 'يتطلّب دليل مستخدمين وأدوار \u2014 لوحة إعدادات النظام غير مُفعَّلة بعد.',
                ),
                _reportCard(
                  id: 'R5',
                  icon: Icons.calendar_month_outlined,
                  title: 'الملخص الشهري للمجلس \u2014 R5',
                  description: 'حالات جديدة، إجراءات صادرة، إخلاءات، هدم، مفتوحة/مغلقة.',
                  onExport: (asPdf) => _export(
                    reportId: 'R5',
                    title: 'الملخص الشهري للمجلس',
                    subtitle: 'ملخص شهر ${_currentMonthLabel()}',
                    fetch: () => _repo.buildR5MonthlyRollup(DateTime.now()),
                    asPdf: asPdf,
                  ),
                ),
                _reportCard(
                  id: 'R6',
                  icon: Icons.history_edu_outlined,
                  title: 'السجلّ الكامل لعقار \u2014 R6',
                  description: 'الخط الزمني الكامل وسجلّ التدقيق لعقار واحد.',
                  unavailableReason: 'يتطلّب سجلّ تدقيق (Audit Log) غير مُطبَّق بعد في هذا الإصدار.',
                ),
                _reportCard(
                  id: 'R7',
                  icon: Icons.volunteer_activism_outlined,
                  title: 'مرشّحو تمويل الترميم \u2014 R7',
                  description: 'المباني الجاهزة للترميم التي لا يقدر أصحابها على تحمّل الكلفة.',
                  onExport: (asPdf) => _export(
                    reportId: 'R7',
                    title: 'مرشّحو تمويل الترميم',
                    subtitle: 'المباني الجاهزة للترميم بانتظار جهة تمويل',
                    fetch: () => _repo.buildR7FundingCandidates(),
                    asPdf: asPdf,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _reportCard({
    required String id,
    required IconData icon,
    required String title,
    required String description,
    Future<void> Function(bool asPdf)? onExport,
    String? unavailableReason,
  }) {
    final busy = _busyReportId == id;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.iceTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.navy, size: 20),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.text)),
          const SizedBox(height: 6),
          Expanded(
            child: Text(description, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.5)),
          ),
          const SizedBox(height: 12),
          if (unavailableReason != null)
            Text(unavailableReason, style: const TextStyle(fontSize: 11, color: AppColors.textFaint, fontStyle: FontStyle.italic))
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: busy ? '...' : 'Excel',
                    icon: Icons.grid_on,
                    dense: true,
                    expand: true,
                    variant: AppButtonVariant.outline,
                    onPressed: busy ? null : () => onExport!(false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: busy ? '...' : 'PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    dense: true,
                    expand: true,
                    variant: AppButtonVariant.outline,
                    onPressed: busy ? null : () => onExport!(true),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}