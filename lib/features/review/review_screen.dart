import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../../core/widgets/status_badge.dart';
import '../intake/models/case.dart';
import 'data/review_repository.dart';
import 'models/decision.dart';
import 'models/report.dart';
import 'models/review.dart';

/// Review & Decision — "المراجعة والقرار" (§7.3, BR-1, BR-6, FR-REV-1..4).
///
/// The most business-rule-critical screen in the app: turns a report into
/// exactly one of four enforcement decisions. Reached with a case ID
/// (`/review/:caseId`) — reaching it without one shows an explanatory
/// empty state, same pattern as Triage.
///
/// TWO STATES, both in this one continuous screen (no separate wizard
/// steps, matching the design established across every other screen):
///  1. No report recorded yet for this case → a short "record the report"
///     form (§5.1, FR-REV-1) — necessary because nothing else in this
///     app creates a Report, and the approved design only shows a report
///     that already exists.
///  2. A report exists → the actual review + decision form, read-only
///     report summary at the top, matching the approved design exactly.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.caseId});

  final String? caseId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  bool _loading = true;
  String? _loadError;
  Case? _caseRecord;
  Report? _report;
  bool _hasPriorShoringWarning = false;

  final _reportReferenceController = TextEditingController();
  final _reportSummaryController = TextEditingController();
  late final TextEditingController _reportDateController;
  DateTime _reportDate = DateTime.now();
  final List<PlatformFile> _reportMedia = [];
  bool _creatingReport = false;
  String? _reportFormError;

  ReviewPriority _priority = ReviewPriority.medium;
  DecisionAction? _action;
  DateTime _executionDate = DateTime.now().add(const Duration(days: 30));
  late final TextEditingController _executionDateController;
  bool _busy = false;
  String? _error;

  static const _defaultFollowupDays = 30;

  ReviewRepository get _repo => ref.read(reviewRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _reportDateController = TextEditingController(text: _fmt(_reportDate));
    _executionDateController = TextEditingController(text: _fmt(_executionDate));
    if (widget.caseId != null) _load();
  }

  @override
  void dispose() {
    _reportReferenceController.dispose();
    _reportSummaryController.dispose();
    _reportDateController.dispose();
    _executionDateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final caseRecord = await _repo.getCase(widget.caseId!);
      if (caseRecord == null) {
        if (mounted) {
          setState(() {
            _loadError = 'الحالة غير موجودة.';
            _loading = false;
          });
        }
        return;
      }
      final report = await _repo.getLatestReportForCase(caseRecord.id);
      final hasWarning = await _repo.hasPriorShoringWarning(caseRecord.parcelId);
      if (!mounted) return;
      setState(() {
        _caseRecord = caseRecord;
        _report = report;
        _hasPriorShoringWarning = hasWarning;
        _loading = false;
        if (report != null) _applyReportDefaults(report);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = describeFirebaseError(e, 'تعذّر تحميل الحالة');
          _loading = false;
        });
      }
    }
  }

  void _applyReportDefaults(Report report) {
    _priority = report.source == ReportSource.urgentOnsite ? ReviewPriority.urgent : ReviewPriority.medium;
    _executionDate = DateTime.now().add(const Duration(days: _defaultFollowupDays));
    _executionDateController.text = _fmt(_executionDate);
  }

  Future<void> _pickReportMedia() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _reportMedia.addAll(result.files));
    }
  }

  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _reportDate = picked;
        _reportDateController.text = _fmt(picked);
      });
    }
  }

  Future<void> _pickExecutionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _executionDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _executionDate = picked;
        _executionDateController.text = _fmt(picked);
      });
    }
  }

  Future<void> _submitReportForm() async {
    if (_reportSummaryController.text.trim().isEmpty) {
      setState(() => _reportFormError = 'ملخّص التقرير مطلوب.');
      return;
    }
    setState(() {
      _creatingReport = true;
      _reportFormError = null;
    });
    try {
      final report = await _repo.createReport(
        caseRecord: _caseRecord!,
        reference: _reportReferenceController.text.trim().isEmpty ? null : _reportReferenceController.text.trim(),
        date: _reportDate,
        summary: _reportSummaryController.text.trim(),
        media: _reportMedia,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _applyReportDefaults(report);
      });
    } catch (e) {
      if (mounted) setState(() => _reportFormError = describeFirebaseError(e, 'تعذّر حفظ التقرير'));
    } finally {
      if (mounted) setState(() => _creatingReport = false);
    }
  }

  Future<void> _saveDraft() async {
    if (_report == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.saveDraft(report: _report!, priority: _priority);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المسودة.')));
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر حفظ المسودة'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitDecision() async {
    if (_action == null) {
      setState(() => _error = 'الرجاء اختيار القرار.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final noticeId = await _repo.submitReviewAndDecision(
        report: _report!,
        priority: _priority,
        action: _action!,
        executionDate: _executionDate,
      );
      if (!mounted) return;
      context.go('/notices/$noticeId');
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر حفظ القرار'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.caseId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المراجعة والقرار', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد حالة للمراجعة',
              message: 'افتح هذه الشاشة من لوحة الإجراءات المستحقة أو من صفحة تفاصيل العقار لحالة معيّنة.',
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null || _caseRecord == null) {
      return AppCard(child: AppAlert(kind: AppAlertKind.danger, title: 'تعذّر التحميل', message: _loadError ?? ''));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المراجعة والقرار', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  const Text(
                    'مراجعة التقرير الهندسي واتخاذ قرار واحد من الإجراءات الأربعة (§7.3, BR-1, BR-6).',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (_report != null) _priorityBadge(_priority),
          ],
        ),
        const SizedBox(height: 22),
        _report == null ? _buildReportForm() : _buildReviewAndDecision(_report!),
      ],
    );
  }

  Widget _buildReportForm() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تسجيل التقرير', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text)),
          const SizedBox(height: 6),
          Text(
            _caseRecord!.dispatchedOnsiteAt != null
                ? 'المصدر: معاينة موقعية عاجلة (تم إيفاد مهندس بلدي عبر فرز الأولوية).'
                : 'المصدر: اللجنة الهندسية المشتركة.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          if (_reportFormError != null) ...[
            AppAlert(kind: AppAlertKind.danger, message: _reportFormError!),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _reportReferenceController,
            decoration: const InputDecoration(labelText: 'رقم مرجعي (اختياري)'),
          ),
          const SizedBox(height: 14),
          TextField(
            readOnly: true,
            controller: _reportDateController,
            decoration: const InputDecoration(labelText: 'تاريخ التقرير'),
            onTap: _pickReportDate,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reportSummaryController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'ملخّص التقرير *', hintText: 'ما الذي لوحظ أثناء المعاينة...'),
          ),
          const SizedBox(height: 16),
          const Text('الصور والفيديوهات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
          const SizedBox(height: 8),
          _pendingMediaList(),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: _creatingReport ? 'جارٍ الحفظ...' : 'حفظ التقرير ومتابعة المراجعة',
              icon: Icons.description_outlined,
              onPressed: _creatingReport ? null : _submitReportForm,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingMediaList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_reportMedia.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _reportMedia.length; i++)
                Chip(
                  label: Text(_reportMedia[i].name, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _reportMedia.removeAt(i)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        AppButton(
          label: 'إضافة صور أو فيديوهات',
          icon: Icons.attach_file,
          variant: AppButtonVariant.outline,
          dense: true,
          onPressed: _pickReportMedia,
        ),
      ],
    );
  }

  Widget _buildReviewAndDecision(Report report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final mainCard = AppCard(child: _buildDecisionForm(report));
        final sidePanel = _buildSidePanel(report);
        if (!isWide) return Column(children: [mainCard, const SizedBox(height: 18), sidePanel]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: mainCard),
            const SizedBox(width: 18),
            Expanded(child: sidePanel),
          ],
        );
      },
    );
  }

  Widget _buildDecisionForm(Report report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.description_outlined, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${report.reference != null ? 'تقرير ${report.reference} — ' : 'تقرير — '}${report.source.label}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.text),
              ),
            ),
            Pill(label: report.source.firestoreValue, color: AppColors.textMuted, backgroundColor: AppColors.bg, borderColor: AppColors.border),
          ],
        ),
        const SizedBox(height: 10),
        Text(report.summary, style: const TextStyle(fontSize: 13, color: AppColors.textBody, height: 1.7)),
        const SizedBox(height: 20),
        const Text('أولوية المراجعة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
        const SizedBox(height: 8),
        _priorityField(report),
        const SizedBox(height: 20),
        if (_error != null) ...[AppAlert(kind: AppAlertKind.danger, message: _error!), const SizedBox(height: 16)],
        const Text('القرار *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
        const SizedBox(height: 10),
        for (final action in DecisionAction.values) ...[
          _decisionOption(action),
          const SizedBox(height: 10),
        ],
        AppAlert(
          kind: AppAlertKind.info,
          title: 'تاريخ التنفيذ المحدَّد تلقائيًا (BR-4)',
          message: '$_defaultFollowupDays يومًا من اليوم — ${_fmt(_executionDate)}. يمكن تعديله أدناه.',
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 220,
          child: TextField(
            readOnly: true,
            controller: _executionDateController,
            decoration: const InputDecoration(labelText: 'تعديل تاريخ التنفيذ (اختياري)'),
            onTap: _pickExecutionDate,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'حفظ كمسودة', variant: AppButtonVariant.outline, onPressed: _busy ? null : _saveDraft),
            const SizedBox(width: 10),
            AppButton(
              label: _busy ? 'جارٍ الحفظ...' : 'تأكيد القرار وإصدار الإشعار',
              icon: Icons.gavel_outlined,
              onPressed: _busy ? null : _submitDecision,
            ),
          ],
        ),
      ],
    );
  }

  Widget _priorityField(Report report) {
    final locked = report.source == ReportSource.urgentOnsite;
    if (locked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: AppColors.borderStrong), borderRadius: BorderRadius.circular(8), color: AppColors.bg),
            child: const Row(
              children: [
                Icon(Icons.bolt, size: 18, color: AppColors.danger),
                SizedBox(width: 8),
                Text('عاجل (تلقائي — تقرير سريع)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text('مضبوطة تلقائيًا على "عاجل" لأن مصدر التقرير "معاينة سريعة" (BR-6).', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      );
    }
    return DropdownButtonFormField<ReviewPriority>(
      value: _priority,
      decoration: const InputDecoration(labelText: 'أولوية المراجعة'),
      items: ReviewPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
      onChanged: (v) => setState(() => _priority = v ?? _priority),
    );
  }

  Widget _decisionOption(DecisionAction action) {
    final disabled = action == DecisionAction.shoringConfirm && !_hasPriorShoringWarning;
    final selected = _action == action;
    return InkWell(
      onTap: disabled ? null : () => setState(() => _action = action),
      borderRadius: BorderRadius.circular(9),
      child: Opacity(
        opacity: disabled ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.navy : AppColors.border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(9),
            color: selected ? AppColors.iceTint : AppColors.surface,
          ),
          child: Row(
            children: [
              Icon(
                disabled ? Icons.lock_outline : (selected ? Icons.radio_button_checked : Icons.radio_button_off),
                size: 20,
                color: disabled ? AppColors.textFaint : (selected ? AppColors.navy : AppColors.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      disabled ? '🔒 غير متاح — لا يوجد إنذار تدعيم سابق على هذا العقار (BR-1)' : action.subtitle,
                      style: TextStyle(fontSize: 11.5, color: disabled ? AppColors.danger : AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(Report report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صور المعاينة (${report.mediaUrls.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
              const SizedBox(height: 10),
              if (report.mediaUrls.isEmpty)
                const Text('لا توجد وسائط مرفقة مع هذا التقرير.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final url in report.mediaUrls) MediaThumbnail(url: url, size: 84)],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          backgroundColor: AppColors.dangerBg,
          borderColor: AppColors.dangerBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.block, size: 18, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('قاعدة العمل BR-1', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.danger)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'لا يمكن إصدار "تأكيدي بالتدعيم" إلا إذا وُجد إنذار تدعيم سابق على العقار نفسه — '
                'صادر عن النظام أو مستورَد من سجلّات قديمة. يمنع النظام هذا الخيار تلقائيًا ويوضح السبب.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A1A15), height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _priorityBadge(ReviewPriority priority) {
    final (bg, fg) = switch (priority) {
      ReviewPriority.urgent => (AppColors.danger, Colors.white),
      ReviewPriority.high => (AppColors.warningBg, AppColors.warning),
      ReviewPriority.medium => (AppColors.infoBg, AppColors.info),
      ReviewPriority.low => (AppColors.bg, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('أولوية: ${priority.label}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}