import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/constants/parcel_status.dart';
import '../../core/constants/roles.dart';
import '../../core/excel_export/excel_export.dart';
import '../../core/models/report_section.dart';
import '../../core/pdf/report_pdf_builder.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/web_download.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../assessment/models/funding_candidate.dart';
import '../intake/models/parcel.dart';
import 'data/reports_repository.dart';

enum _FilterKind { zone, status, dateRange, team, parcel, month, fundingStatus, window }

/// One card in the hub: what the report is, which filters it accepts, and
/// how to build its data. The seven cards below match the approved design
/// (R1–R7, each with PDF and Excel export).
class _ReportSpec {
  const _ReportSpec({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.filters,
    required this.build,
    this.requiresParcel = false,
  });

  final String code;
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Set<_FilterKind> filters;
  final Future<ReportResult> Function(ReportsRepository repo, ReportFilters filters) build;

  /// R6 is meaningless without a parcel, so exporting it prompts for one.
  final bool requiresParcel;
}

const _purple = Color(0xFF6B4FA0);
const _purpleBg = Color(0xFFF0EBFA);

final _specs = <_ReportSpec>[
  _ReportSpec(
    code: 'R1',
    title: 'ملخّص حالة العقارات',
    description: 'الحالة الحالية وآخر إجراء لكل عقار.',
    icon: Icons.description_outlined,
    iconColor: AppColors.info,
    iconBackground: AppColors.infoBg,
    filters: {_FilterKind.zone, _FilterKind.status},
    build: (repo, f) => repo.buildR1(f),
  ),
  _ReportSpec(
    code: 'R2',
    title: 'العقارات حسب المرحلة',
    description: 'أعداد العقارات مصنّفة حسب الحالة ونوع الإجراء.',
    icon: Icons.bar_chart_outlined,
    iconColor: _purple,
    iconBackground: _purpleBg,
    filters: {_FilterKind.zone, _FilterKind.dateRange},
    build: (repo, f) => repo.buildR2(f),
  ),
  _ReportSpec(
    code: 'R3',
    title: 'إجراءات متأخرة ومستحقة',
    description: 'نفس بيانات لوحة الإجراءات المستحقة، بصيغة تقرير.',
    icon: Icons.warning_amber_rounded,
    iconColor: AppColors.danger,
    iconBackground: AppColors.dangerBg,
    filters: {_FilterKind.zone, _FilterKind.window},
    build: (repo, f) => repo.buildR3(f),
  ),
  _ReportSpec(
    code: 'R4',
    title: 'نشاط كل فريق',
    description: 'الإجراءات والزيارات الميدانية لكل فريق خلال فترة محددة.',
    icon: Icons.groups_outlined,
    iconColor: AppColors.info,
    iconBackground: AppColors.infoBg,
    filters: {_FilterKind.team, _FilterKind.dateRange},
    build: (repo, f) => repo.buildR4(f),
  ),
  _ReportSpec(
    code: 'R5',
    title: 'الملخص الشهري للمجلس',
    description: 'صفحة واحدة: حالات جديدة، إجراءات صادرة، إخلاءات، عمليات هدم.',
    icon: Icons.calendar_month_outlined,
    iconColor: AppColors.warning,
    iconBackground: AppColors.warningBg,
    filters: {_FilterKind.month},
    build: (repo, f) => repo.buildR5(f),
  ),
  _ReportSpec(
    code: 'R6',
    title: 'السجل الكامل لعقار',
    description: 'الخط الزمني الكامل وسجلّ التدقيق لعقار واحد.',
    icon: Icons.fact_check_outlined,
    iconColor: AppColors.success,
    iconBackground: AppColors.successBg,
    filters: {_FilterKind.parcel},
    requiresParcel: true,
    build: (repo, f) => repo.buildR6(f),
  ),
  _ReportSpec(
    code: 'R7',
    title: 'مرشّحو تمويل الترميم',
    description: 'المباني الجاهزة للترميم التي لا يقدر أصحابها على تحمل الكلفة.',
    icon: Icons.volunteer_activism_outlined,
    iconColor: AppColors.warning,
    iconBackground: AppColors.warningBg,
    filters: {_FilterKind.zone, _FilterKind.fundingStatus},
    build: (repo, f) => repo.buildR7(f),
  ),
];

/// Reports Hub — "التقارير" (§9, R1–R7).
///
/// Seven management reports, each exportable as PDF or Excel, both fully
/// right-to-left. Every report accepts the filters the spec lists for it;
/// filters are set per report with "تصفية" and stay applied until changed.
/// R6 asks for a parcel first because it has no meaning without one.
///
/// Exports that match no data are NOT downloaded as blank files — the user
/// is told instead.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final Map<String, ReportFilters> _filters = {};
  String? _busyKey; // '<code>:pdf' or '<code>:xlsx'
  String? _error;
  String? _success;

  ReportsRepository get _repo => ref.read(reportsRepositoryProvider);

  Future<ReportFilters?> _openFilters(_ReportSpec spec) {
    return showDialog<ReportFilters>(
      context: context,
      builder: (_) => _FilterDialog(spec: spec, initial: (_filters[spec.code] ?? ReportFilters()).copy(), repo: _repo),
    ).then((result) {
      if (result != null && mounted) setState(() => _filters[spec.code] = result);
      return result;
    });
  }

  Future<void> _export(_ReportSpec spec, {required bool pdf}) async {
    var filters = _filters[spec.code] ?? ReportFilters();
    if (spec.requiresParcel && filters.parcelId == null) {
      final chosen = await _openFilters(spec);
      if (chosen == null || chosen.parcelId == null) return;
      filters = chosen;
    }

    setState(() {
      _busyKey = '${spec.code}:${pdf ? 'pdf' : 'xlsx'}';
      _error = null;
      _success = null;
    });
    try {
      final result = await spec.build(_repo, filters);
      if (result.rowCount == 0) {
        if (mounted) setState(() => _error = 'لا توجد بيانات مطابقة لهذا التقرير بالفلاتر الحالية — لم يُنشأ أي ملف.');
        return;
      }
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final fileBase = 'report-${spec.code.toLowerCase()}-$stamp';

      if (pdf) {
        final bytes = await buildReportPdf(title: '${spec.title} (${spec.code})', subtitle: filters.describe(), sections: result.sections);
        downloadBytes(bytes, '$fileBase.pdf', 'application/pdf');
      } else {
        final bytes = buildExcelWorkbook(sheetName: spec.title, sections: result.sections);
        downloadBytes(bytes, '$fileBase.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
      if (mounted) setState(() => _success = 'تم تجهيز تقرير ${spec.code} — ${result.rowCount} سجلًّا.');
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر إنشاء التقرير'));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'التقارير',
          subtitle: 'سبعة تقارير إدارية جاهزة للتصدير بصيغة PDF أو Excel، بالعربية RTL (§9).',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[AppAlert(kind: AppAlertKind.warning, message: _error!), const SizedBox(height: 14)],
        if (_success != null) ...[AppAlert(kind: AppAlertKind.success, message: _success!), const SizedBox(height: 14)],
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 980 ? 3 : (constraints.maxWidth > 640 ? 2 : 1);
          final rows = <List<_ReportSpec>>[];
          for (var i = 0; i < _specs.length; i += columns) {
            rows.add(_specs.sublist(i, i + columns > _specs.length ? _specs.length : i + columns));
          }
          return Column(
            children: [
              for (final row in rows) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < row.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        Expanded(child: _card(row[i])),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        }),
      ],
    );
  }

  Widget _card(_ReportSpec spec) {
    final filters = _filters[spec.code];
    final hasFilters = filters != null && !filters.isEmpty;
    final pdfBusy = _busyKey == '${spec.code}:pdf';
    final xlsxBusy = _busyKey == '${spec.code}:xlsx';
    final anyBusy = _busyKey != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: spec.iconBackground, borderRadius: BorderRadius.circular(9)),
            child: Icon(spec.icon, size: 18, color: spec.iconColor),
          ),
          const SizedBox(height: 12),
          Text('${spec.title} — ${spec.code}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.text)),
          const SizedBox(height: 6),
          Text(spec.description, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.6)),
          if (hasFilters) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.iceTint, borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)),
              child: Text(filters.describe(), style: const TextStyle(fontSize: 11, color: AppColors.navy, height: 1.5)),
            ),
          ],
          const Spacer(),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: spec.requiresParcel && !hasFilters ? 'اختيار عقار' : (hasFilters ? 'تعديل الفلاتر' : 'تصفية'),
                icon: Icons.tune,
                variant: AppButtonVariant.ghost,
                dense: true,
                onPressed: anyBusy ? null : () => _openFilters(spec),
              ),
              AppButton(
                label: pdfBusy ? 'جارٍ الإنشاء...' : 'PDF',
                icon: Icons.picture_as_pdf_outlined,
                variant: AppButtonVariant.outline,
                dense: true,
                onPressed: anyBusy ? null : () => _export(spec, pdf: true),
              ),
              AppButton(
                label: xlsxBusy ? 'جارٍ الإنشاء...' : 'Excel',
                icon: Icons.grid_on_outlined,
                variant: AppButtonVariant.outline,
                dense: true,
                onPressed: anyBusy ? null : () => _export(spec, pdf: false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Collects a report's filters. Only the filters that report accepts are
/// shown; "مسح" clears them all.
class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.spec, required this.initial, required this.repo});

  final _ReportSpec spec;
  final ReportFilters initial;
  final ReportsRepository repo;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late ReportFilters _f;
  late final Future<List<Parcel>> _parcels;
  late final TextEditingController _window;

  bool _has(_FilterKind k) => widget.spec.filters.contains(k);

  @override
  void initState() {
    super.initState();
    _f = widget.initial;
    _window = TextEditingController(text: _f.windowDays?.toString() ?? '');
    _parcels = (_has(_FilterKind.zone) || _has(_FilterKind.parcel)) ? widget.repo.listParcels() : Future.value(<Parcel>[]);
  }

  @override
  void dispose() {
    _window.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: (_f.from != null && _f.to != null) ? DateTimeRange(start: _f.from!, end: _f.to!) : null,
    );
    if (picked != null) setState(() {
      _f.from = picked.start;
      _f.to = picked.end;
    });
  }

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<DateTime> get _months {
    final now = DateTime.now();
    return [for (var i = 0; i < 24; i++) DateTime(now.year, now.month - i, 1)];
  }

  bool get _canApply => !widget.spec.requiresParcel || _f.parcelId != null;

  void _apply() {
    final n = int.tryParse(_window.text.trim());
    _f.windowDays = (n != null && n >= 1 && n <= 365) ? n : null;
    Navigator.pop(context, _f);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('فلاتر ${widget.spec.title} (${widget.spec.code})'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<Parcel>>(
          future: _parcels,
          builder: (context, snap) {
            final parcels = snap.data ?? const <Parcel>[];
            final loading = snap.connectionState != ConnectionState.done;
            final zones = {for (final p in parcels) p.cadastralZone}.toList()..sort();

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.spec.requiresParcel)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text('هذا التقرير يخص عقارًا واحدًا — اختر العقار المطلوب.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ),
                  if (loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                  if (!loading && _has(_FilterKind.parcel)) ...[
                    DropdownButtonFormField<String>(
                      value: parcels.any((p) => p.id == _f.parcelId) ? _f.parcelId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'العقار'),
                      hint: const Text('اختر عقارًا'),
                      items: [
                        for (final p in parcels)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.address.isEmpty ? '${p.parcelNo} — ${p.cadastralZone}' : '${p.parcelNo} — ${p.cadastralZone} — ${p.address}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _f.parcelId = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!loading && _has(_FilterKind.zone)) ...[
                    DropdownButtonFormField<String?>(
                      value: zones.contains(_f.zone) ? _f.zone : null,
                      decoration: const InputDecoration(labelText: 'المنطقة العقارية'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('كل المناطق')),
                        for (final z in zones) DropdownMenuItem<String?>(value: z, child: Text(z)),
                      ],
                      onChanged: (v) => setState(() => _f.zone = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_has(_FilterKind.status)) ...[
                    DropdownButtonFormField<ParcelStatus?>(
                      value: _f.status,
                      decoration: const InputDecoration(labelText: 'حالة العقار'),
                      items: [
                        const DropdownMenuItem<ParcelStatus?>(value: null, child: Text('كل الحالات')),
                        for (final s in ParcelStatus.values) DropdownMenuItem<ParcelStatus?>(value: s, child: Text(s.label)),
                      ],
                      onChanged: (v) => setState(() => _f.status = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_has(_FilterKind.fundingStatus)) ...[
                    DropdownButtonFormField<FundingCandidateStatus?>(
                      value: _f.fundingStatus,
                      decoration: const InputDecoration(labelText: 'حالة التمويل'),
                      items: [
                        const DropdownMenuItem<FundingCandidateStatus?>(value: null, child: Text('كل الحالات')),
                        for (final s in FundingCandidateStatus.values) DropdownMenuItem<FundingCandidateStatus?>(value: s, child: Text(s.label)),
                      ],
                      onChanged: (v) => setState(() => _f.fundingStatus = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_has(_FilterKind.team)) ...[
                    DropdownButtonFormField<AppRole?>(
                      value: _f.team,
                      decoration: const InputDecoration(labelText: 'الفريق'),
                      items: [
                        const DropdownMenuItem<AppRole?>(value: null, child: Text('كل الفرق')),
                        for (final r in AppRole.values) DropdownMenuItem<AppRole?>(value: r, child: Text(r.label)),
                      ],
                      onChanged: (v) => setState(() => _f.team = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_has(_FilterKind.dateRange)) ...[
                    InkWell(
                      onTap: _pickRange,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'الفترة الزمنية',
                          suffixIcon: (_f.from == null)
                              ? const Icon(Icons.date_range_outlined, size: 18)
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => setState(() {
                                    _f.from = null;
                                    _f.to = null;
                                  }),
                                ),
                        ),
                        child: Text(
                          (_f.from == null || _f.to == null) ? 'كل الفترات' : '${_d(_f.from!)}  ←  ${_d(_f.to!)}',
                          style: TextStyle(fontSize: 14, color: (_f.from == null) ? AppColors.textMuted : AppColors.text),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_has(_FilterKind.month)) ...[
                    DropdownButtonFormField<DateTime>(
                      value: _months.contains(_f.month) ? _f.month : _months.first,
                      decoration: const InputDecoration(labelText: 'الشهر'),
                      items: [
                        for (final m in _months) DropdownMenuItem(value: m, child: Text('${m.year}-${m.month.toString().padLeft(2, '0')}')),
                      ],
                      onChanged: (v) => setState(() => _f.month = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_has(_FilterKind.window)) ...[
                    TextField(
                      controller: _window,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'نافذة "مستحقة قريبًا" (بالأيام)',
                        helperText: 'اتركه فارغًا لاستخدام الافتراضي من إعدادات النظام.',
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _f = ReportFilters();
            _window.clear();
          }),
          child: const Text('مسح'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _canApply ? _apply : null, child: const Text('تطبيق')),
      ],
    );
  }
}
