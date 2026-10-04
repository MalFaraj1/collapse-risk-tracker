import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/roles.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../auth/auth_providers.dart';
import '../review/models/decision.dart';
import 'data/import_parser.dart';
import 'data/import_repository.dart';
import 'models/import_models.dart';

/// Legacy warnings import — "استيراد إنذارات سابقة" (§7.9, FR-IMP-1..3).
///
/// Flow, as approved in the design:
///  1. Upload an Excel/CSV file of old paper warnings.
///  2. A PREVIEW shows every row already validated against the four
///     minimum fields (parcel number, zone, warning type, date — OQ-4),
///     so nothing is written until the administrator confirms.
///  3. Confirming imports the batch: each valid row is attached to its
///     parcel (created if absent) as an imported notice, which BR-1 then
///     accepts as a prior shoring warning (FR-IMP-3).
///  4. Rows with a missing or unreadable minimum field are flagged
///     "غير مطابق" and can be fixed one by one with "مراجعة" (FR-IMP-2).
///
/// Administrator-only (Appendix A).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  String? _selectedBatchId;
  ImportRowStatus? _filter; // null = all rows

  String? _previewFileName;
  Uint8List? _previewBytes;
  List<ParsedImportRow>? _preview;
  bool _parsing = false;
  bool _importing = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _parsing = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _parsing = false);
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw ImportFormatException('تعذّرت قراءة محتوى الملف.');
      final rows = ImportParser.parse(bytes, file.name);
      if (mounted) {
        setState(() {
          _previewFileName = file.name;
          _previewBytes = bytes;
          _preview = rows;
          _parsing = false;
        });
      }
    } on ImportFormatException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _preview = null;
          _parsing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeFirebaseError(e, 'تعذّرت قراءة الملف');
          _preview = null;
          _parsing = false;
        });
      }
    }
  }

  Future<void> _confirmImport() async {
    final rows = _preview;
    final name = _previewFileName;
    if (rows == null || name == null) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final batch = await ref
          .read(importRepositoryProvider)
          .importBatch(fileName: name, rows: rows, sourceBytes: _previewBytes);
      if (!mounted) return;
      setState(() {
        _selectedBatchId = batch.id;
        _preview = null;
        _previewFileName = null;
        _previewBytes = null;
        _filter = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر إتمام الاستيراد'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    if (role != AppRole.admin) {
      return const AppCard(
        child: AppAlert(kind: AppAlertKind.info, title: 'صلاحية غير كافية', message: 'استيراد الإنذارات السابقة متاح لمدير النظام فقط.'),
      );
    }

    final batchesAsync = ref.watch(importBatchesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'استيراد إنذارات سابقة',
          subtitle: 'رفع سجلّات ورقية قديمة لتصبح مرجعًا صالحًا لقاعدة BR-1 (§7.9, FR-IMP-1..3).',
          actions: [
            AppButton(label: 'رفع ملف جديد', icon: Icons.upload_file_outlined, onPressed: (_parsing || _importing) ? null : _pickFile),
          ],
        ),
        const SizedBox(height: 18),
        _dropzone(),
        if (_error != null) ...[const SizedBox(height: 14), AppAlert(kind: AppAlertKind.danger, message: _error!)],
        if (_preview != null) ...[const SizedBox(height: 18), _previewCard()],
        const SizedBox(height: 18),
        batchesAsync.when(
          loading: () => const AppCard(child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))),
          error: (e, _) => AppAlert(
            kind: AppAlertKind.danger,
            title: 'تعذّر تحميل سجلّ الاستيراد',
            message: describeFirebaseError(e, 'تعذّر تحميل سجلّ الاستيراد'),
          ),
          data: _batchSection,
        ),
      ],
    );
  }

  // ---- Upload card -------------------------------------------------------------

  Widget _dropzone() {
    return AppCard(
      child: InkWell(
        onTap: (_parsing || _importing) ? null : _pickFile,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Column(
            children: [
              _parsing
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.upload_file_outlined, size: 30, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text(
                _parsing ? 'جارٍ قراءة الملف...' : 'اضغط لاختيار ملف Excel (.xlsx) أو CSV',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              const Text(
                'الحقول المطلوبة كحد أدنى: رقم العقار، المنطقة العقارية، نوع الإنذار، التاريخ (OQ-4). عمود "المرجع" اختياري.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Pre-import preview ------------------------------------------------------

  Widget _previewCard() {
    final rows = _preview!;
    final valid = rows.where((r) => r.isValid).length;
    final flagged = rows.length - valid;
    const shown = 100;

    return AppCardWithHeader(
      title: 'معاينة قبل الاستيراد — $_previewFileName',
      icon: Icons.fact_check_outlined,
      trailing: '${rows.length} صفًا',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Pill(label: '$valid صف صالح', color: AppColors.success, backgroundColor: AppColors.successBg, borderColor: AppColors.border),
                Pill(
                  label: '$flagged سيُوسَم للمراجعة اليدوية',
                  color: flagged == 0 ? AppColors.textMuted : AppColors.warning,
                  backgroundColor: flagged == 0 ? AppColors.bg : AppColors.warningBg,
                  borderColor: flagged == 0 ? AppColors.border : AppColors.warningBorder,
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'لن يُكتب شيء قبل التأكيد. الصفوف الصالحة تُرفق بعقاراتها (وتُنشأ العقارات غير الموجودة)، والصفوف الناقصة تُسجَّل للمراجعة اليدوية.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('الصف')),
                  DataColumn(label: Text('رقم العقار')),
                  DataColumn(label: Text('المنطقة')),
                  DataColumn(label: Text('نوع الإنذار')),
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('التحقق')),
                ],
                rows: [
                  for (final r in rows.take(shown))
                    DataRow(cells: [
                      DataCell(Text('#${r.rowNumber}', style: AppTypography.mono(fontSize: 11.5, color: AppColors.textMuted))),
                      DataCell(Text(r.parcelNoRaw.isEmpty ? '—' : r.parcelNoRaw, style: AppTypography.mono(fontSize: 12))),
                      DataCell(Text(r.zoneRaw.trim().isEmpty ? '—' : r.zoneRaw, style: AppTypography.mono(fontSize: 12))),
                      DataCell(Text(r.type?.noticeTitle ?? (r.typeRaw.isEmpty ? '—' : r.typeRaw), style: const TextStyle(fontSize: 12.5))),
                      DataCell(Text(r.date == null ? (r.dateRaw.isEmpty ? '—' : r.dateRaw) : _fmt(r.date!), style: AppTypography.mono(fontSize: 12))),
                      DataCell(r.isValid
                          ? const Pill(label: 'صالح', color: AppColors.success, backgroundColor: AppColors.successBg, borderColor: AppColors.border)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Pill(label: 'للمراجعة', color: AppColors.warning, backgroundColor: AppColors.warningBg, borderColor: AppColors.warningBorder),
                                Text(r.error!, style: const TextStyle(fontSize: 10.5, color: AppColors.danger)),
                              ],
                            )),
                    ]),
                ],
              ),
            ),
            if (rows.length > shown)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('يُعرض أول $shown صف فقط من ${rows.length} — كل الصفوف ستُستورد.', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'إلغاء',
                  variant: AppButtonVariant.outline,
                  onPressed: _importing ? null : () => setState(() {
                        _preview = null;
                        _previewFileName = null;
                        _previewBytes = null;
                      }),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: _importing ? 'جارٍ الاستيراد...' : 'تأكيد الاستيراد',
                  icon: Icons.check,
                  onPressed: _importing ? null : _confirmImport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Batch log ---------------------------------------------------------------

  Widget _batchSection(List<ImportBatch> batches) {
    if (batches.isEmpty) {
      return const AppCard(
        child: AppEmptyState(
          icon: Icons.history,
          title: 'لا توجد عمليات استيراد بعد',
          description: 'ارفع أول ملف لتظهر نتيجته هنا: المطابقة تلقائيًا، والعقارات المنشأة، وما يحتاج مراجعة يدوية.',
        ),
      );
    }
    final batch = batches.firstWhere((b) => b.id == _selectedBatchId, orElse: () => batches.first);
    final rowsAsync = ref.watch(importRowsProvider(batch.id));

    return AppCardWithHeader(
      title: 'سجلّ الاستيراد — ${batch.label}',
      icon: Icons.history,
      trailing:
          '${batch.totalRows} صفًا · ${batch.matchedCount + batch.resolvedCount} مطابق · ${batch.unmatchedCount} بحاجة لمراجعة يدوية',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (batches.length > 1) ...[
              SizedBox(
                width: 380,
                child: DropdownButtonFormField<String>(
                  value: batch.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'عملية الاستيراد'),
                  items: [
                    for (final b in batches)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text('${b.label} · ${b.fileName}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedBatchId = v;
                    _filter = null;
                  }),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (batch.sourceFileUrl != null) ...[
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(batch.sourceFileUrl!);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_outlined, size: 15, color: AppColors.info),
                      const SizedBox(width: 6),
                      Text('تنزيل الملف الأصلي — ${batch.fileName}', style: const TextStyle(fontSize: 12, color: AppColors.info, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            LayoutBuilder(builder: (context, constraints) {
              final cards = [
                StatCard(value: '${batch.matchedCount}', label: 'مطابقة تلقائيًا', icon: Icons.task_alt, iconColor: AppColors.success, iconBackground: AppColors.successBg),
                StatCard(value: '${batch.createdParcels}', label: 'عقارات أُنشئت', icon: Icons.add_home_work_outlined, iconColor: AppColors.info, iconBackground: AppColors.infoBg),
                StatCard(value: '${batch.unmatchedCount}', label: 'بحاجة لمراجعة يدوية', icon: Icons.rule_outlined, iconColor: AppColors.warning, iconBackground: AppColors.warningBg),
              ];
              return GridView.count(
                crossAxisCount: constraints.maxWidth > 700 ? 3 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: constraints.maxWidth > 700 ? 2.4 : 3,
                children: cards,
              );
            }),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('الكل'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                ChoiceChip(label: const Text('مطابق'), selected: _filter == ImportRowStatus.matched, onSelected: (_) => setState(() => _filter = ImportRowStatus.matched)),
                ChoiceChip(label: const Text('غير مطابق'), selected: _filter == ImportRowStatus.unmatched, onSelected: (_) => setState(() => _filter = ImportRowStatus.unmatched)),
              ],
            ),
            const SizedBox(height: 12),
            rowsAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => AppAlert(kind: AppAlertKind.danger, message: describeFirebaseError(e, 'تعذّر تحميل صفوف الاستيراد')),
              data: (rows) => _rowsTable(rows),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesFilter(ImportRow r) {
    if (_filter == null) return true;
    if (_filter == ImportRowStatus.matched) return r.status.isOk; // matched, created and resolved all count as "matched"
    return r.status == ImportRowStatus.unmatched;
  }

  Widget _rowsTable(List<ImportRow> allRows) {
    final rows = allRows.where(_matchesFilter).toList();
    if (rows.isEmpty) {
      return const AppEmptyState(icon: Icons.search_off, title: 'لا صفوف مطابقة', description: 'لا توجد صفوف بهذه الحالة في عملية الاستيراد المحددة.');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('الصف')),
          DataColumn(label: Text('رقم العقار (من الملف)')),
          DataColumn(label: Text('المنطقة')),
          DataColumn(label: Text('نوع الإنذار')),
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('')),
        ],
        rows: [for (final r in rows) _row(r)],
      ),
    );
  }

  DataRow _row(ImportRow r) {
    final unmatched = r.status == ImportRowStatus.unmatched;
    return DataRow(cells: [
      DataCell(Text('#${r.rowNumber}', style: AppTypography.mono(fontSize: 11.5, color: AppColors.textMuted))),
      DataCell(Text(r.parcelNoRaw.isEmpty ? '—' : r.parcelNoRaw, style: AppTypography.mono(fontSize: 12, weight: FontWeight.w700, color: AppColors.text))),
      DataCell(Text(r.zoneRaw.trim().isEmpty ? '—' : r.zoneRaw, style: AppTypography.mono(fontSize: 12))),
      DataCell(Text(r.warningType?.noticeTitle ?? (r.typeRaw.isEmpty ? '—' : r.typeRaw), style: const TextStyle(fontSize: 12.5))),
      DataCell(Text(r.warningDate != null ? _fmt(r.warningDate!) : (r.dateRaw.isEmpty ? '—' : r.dateRaw), style: AppTypography.mono(fontSize: 12))),
      DataCell(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            unmatched
                ? const Pill(label: 'غير مطابق', color: Colors.white, backgroundColor: AppColors.danger)
                : Pill(
                    label: r.status == ImportRowStatus.resolved ? 'تمت المراجعة' : 'مطابق',
                    color: AppColors.success,
                    backgroundColor: AppColors.successBg,
                    borderColor: AppColors.border,
                  ),
            if (unmatched && r.errorReason != null) Text(r.errorReason!, style: const TextStyle(fontSize: 10.5, color: AppColors.danger)),
            if (r.note != null) Text(r.note!, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ],
        ),
      ),
      DataCell(
        unmatched
            ? AppButton(label: 'مراجعة', variant: AppButtonVariant.outline, dense: true, onPressed: () => _review(r))
            : (r.noticeId == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'عرض الإنذار المستورد',
                    icon: const Icon(Icons.chevron_left, size: 20, color: AppColors.textMuted),
                    onPressed: () => context.go('/notices/${r.noticeId}'),
                  )),
      ),
    ]);
  }

  Future<void> _review(ImportRow row) {
    return showDialog<void>(context: context, builder: (_) => _ReviewDialog(row: row));
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Manual review of one unmatched row: shows what the file said and why it
/// was flagged, and lets the administrator supply corrected values.
class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.row});
  final ImportRow row;

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  late final TextEditingController _parcelNo;
  late final TextEditingController _zone;
  late final TextEditingController _reference;
  late final TextEditingController _dateText;
  DecisionAction? _type;
  DateTime? _date;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _parcelNo = TextEditingController(text: r.parcelNoRaw.replaceAll(RegExp(r'^[-–—\s]+$'), ''));
    _zone = TextEditingController(text: r.zoneRaw.replaceAll(RegExp(r'^[-–—\s]+$'), ''));
    _reference = TextEditingController(text: r.reference ?? '');
    _type = r.warningType ?? ImportParser.parseType(r.typeRaw);
    _date = r.warningDate ?? ImportParser.parseDate(r.dateRaw);
    _dateText = TextEditingController(text: _date == null ? '' : _fmt(_date!));
  }

  @override
  void dispose() {
    _parcelNo.dispose();
    _zone.dispose();
    _reference.dispose();
    _dateText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateText.text = _fmt(picked);
      });
    }
  }

  Future<void> _save() async {
    if (_parcelNo.text.trim().isEmpty) return setState(() => _error = 'رقم العقار مطلوب.');
    if (_zone.text.trim().isEmpty) return setState(() => _error = 'المنطقة العقارية مطلوبة.');
    if (_type == null) return setState(() => _error = 'اختر نوع الإنذار.');
    if (_date == null) return setState(() => _error = 'اختر تاريخ الإنذار.');

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(importRepositoryProvider).resolveRow(
            widget.row,
            parcelNo: _parcelNo.text,
            zone: _zone.text,
            type: _type!,
            date: _date!,
            reference: _reference.text,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeFirebaseError(e, 'تعذّر حفظ المراجعة');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return AlertDialog(
      title: Text('مراجعة الصف #${r.rowNumber}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.errorReason != null) ...[
                AppAlert(kind: AppAlertKind.warning, title: 'سبب الوسم', message: r.errorReason!),
                const SizedBox(height: 14),
              ],
              if (_error != null) ...[AppAlert(kind: AppAlertKind.danger, message: _error!), const SizedBox(height: 14)],
              Row(
                children: [
                  Expanded(child: TextField(controller: _parcelNo, decoration: const InputDecoration(labelText: 'رقم العقار'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _zone, decoration: const InputDecoration(labelText: 'المنطقة العقارية'))),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<DecisionAction>(
                value: _type,
                decoration: InputDecoration(labelText: 'نوع الإنذار', helperText: r.typeRaw.isEmpty ? null : 'في الملف: ${r.typeRaw}'),
                items: [for (final a in DecisionAction.values) DropdownMenuItem(value: a, child: Text(a.noticeTitle))],
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 14),
              TextField(
                readOnly: true,
                controller: _dateText,
                onTap: _pickDate,
                decoration: InputDecoration(labelText: 'تاريخ الإنذار', helperText: r.dateRaw.isEmpty ? null : 'في الملف: ${r.dateRaw}'),
              ),
              const SizedBox(height: 14),
              TextField(controller: _reference, decoration: const InputDecoration(labelText: 'المرجع (اختياري)')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ واستيراد')),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
