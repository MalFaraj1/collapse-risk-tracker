import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../../core/widgets/timeline_rail.dart';
import '../intake/models/case.dart';
import '../review/models/decision.dart';
import '../review/models/notice.dart';
import 'data/site_visit_repository.dart';
import 'models/site_visit.dart';

/// Site Visit — "زيارة ميدانية — تحقق من الامتثال" (§7.8, FR-DASH-3/4).
///
/// A GENERIC compliance-verification form: it works for any warning-type
/// decision (Shoring Warning, Confirmatory Shoring, Restoration Warning),
/// not just one — unlike Evacuation Execution, which is single-purpose.
/// Reached with a decision ID (`/sitevisit/:decisionId`); there is no
/// meaningful way to record a site visit without knowing which action it
/// verifies, so a bare `/sitevisit` shows an explanatory empty state
/// rather than a broken form, same pattern as every other decision-scoped
/// screen in this app.
///
/// This screen deliberately does NOT handle EVACUATION decisions — that
/// decision type has its own dedicated 48-hour compliance mechanism
/// (see EvacuationExecution.complianceVisitDate); opening this screen on
/// an evacuation decision shows a clear error instead of silently doing
/// the wrong thing.
class SiteVisitScreen extends ConsumerStatefulWidget {
  const SiteVisitScreen({super.key, this.decisionId});

  final String? decisionId;

  @override
  ConsumerState<SiteVisitScreen> createState() => _SiteVisitScreenState();
}

class _SiteVisitScreenState extends ConsumerState<SiteVisitScreen> {
  bool _loading = true;
  String? _loadError;
  Decision? _decision;
  Case? _caseRecord;
  Notice? _notice;
  List<SiteVisit> _priorVisits = [];

  SiteVisitOutcome _outcome = SiteVisitOutcome.complied;
  final _notesController = TextEditingController();
  final List<PlatformFile> _media = [];
  bool _busy = false;
  String? _submitError;

  SiteVisitRepository get _repo => ref.read(siteVisitRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (widget.decisionId != null) _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final decision = await _repo.getDecision(widget.decisionId!);
      if (decision == null) {
        if (mounted) setState(() { _loadError = 'القرار غير موجود.'; _loading = false; });
        return;
      }
      if (decision.action == DecisionAction.evacuation) {
        if (mounted) {
          setState(() {
            _loadError = 'قرارات الإخلاء لها آلية تحقق خاصة بها — استخدم شاشة "تنفيذ الإخلاء" بدلًا من هذه الشاشة.';
            _loading = false;
          });
        }
        return;
      }
      final caseRecord = await _repo.getCase(decision.caseId);
      final notice = await _repo.getNoticeForDecision(decision.id);
      final visits = await _repo.getVisitsForDecision(decision.id);
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _caseRecord = caseRecord;
        _notice = notice;
        _priorVisits = visits;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loadError = describeFirebaseError(e, 'تعذّر تحميل بيانات الحالة'); _loading = false; });
    }
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _media.addAll(result.files));
    }
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _submitError = null; });
    try {
      await _repo.submitVisit(
        decision: _decision!,
        outcome: _outcome,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        media: _media,
      );
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (mounted) setState(() => _submitError = describeFirebaseError(e, 'تعذّر حفظ نتيجة الزيارة'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decisionId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('زيارة ميدانية', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد إجراء للتحقق منه',
              message: 'افتح هذه الشاشة من لوحة الإجراءات المستحقة أو من صفحة تفاصيل العقار لإجراء معيّن.',
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null || _decision == null) {
      return AppCard(child: AppAlert(kind: AppAlertKind.danger, title: 'تعذّر التحميل', message: _loadError ?? ''));
    }

    final decision = _decision!;
    final isClosed = _caseRecord?.status == CaseStatus.closed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('زيارة ميدانية — تحقق من الامتثال', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'تسجيل نتيجة زيارة التحقق الميدانية من لوحة الإجراءات المستحقة (§7.8, FR-DASH-3/4).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final sidePanel = _buildSidePanel();
            final mainPanel = AppCard(child: isClosed ? _buildClosedState() : _buildForm(decision));
            if (!isWide) return Column(children: [mainPanel, const SizedBox(height: 18), sidePanel]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: mainPanel),
                const SizedBox(width: 18),
                Expanded(child: sidePanel),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildClosedState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppAlert(
          kind: AppAlertKind.success,
          title: 'الحالة مغلقة',
          message: 'أُغلقت هذه الحالة بوصفها آمنة بعد زيارة تحقق سابقة. لا حاجة لتسجيل زيارة جديدة.',
        ),
        if (_priorVisits.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('سجلّ الزيارات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
          const SizedBox(height: 10),
          for (final v in _priorVisits) _visitHistoryCard(v),
        ],
      ],
    );
  }

  Widget _buildForm(Decision decision) {
    final overdueDays = DateTime.now().difference(decision.executionDate).inDays;
    final isOverdue = overdueDays > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('العقار', decision.parcelId),
        _kv('الإجراء قيد التحقق',
            '${decision.action.noticeTitle}${_notice != null ? ' — ${_shortId(_notice!.id)}' : ''}'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('تاريخ الاستحقاق', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text(
                isOverdue ? '${_fmt(decision.executionDate)}  (متأخر $overdueDays ${overdueDays == 1 ? "يوم" : "أيام"})' : _fmt(decision.executionDate),
                style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: isOverdue ? AppColors.danger : AppColors.text),
              ),
            ],
          ),
        ),
        if (_priorVisits.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppAlert(
            kind: AppAlertKind.warning,
            title: 'يوجد سجلّ زيارات سابق',
            message: 'آخر نتيجة: ${_priorVisits.first.outcome.label} بتاريخ ${_priorVisits.first.visitedAt != null ? _fmt(_priorVisits.first.visitedAt!) : "—"}.',
          ),
        ],
        const SizedBox(height: 20),
        if (_submitError != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _submitError!),
          const SizedBox(height: 16),
        ],
        const Text('نتيجة الزيارة *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
        const SizedBox(height: 10),
        for (final outcome in SiteVisitOutcome.values) ...[
          _outcomeOption(outcome),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        const Text('ملاحظات المفتش', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'وصف ما تمّت معاينته في الموقع...'),
        ),
        const SizedBox(height: 20),
        const Text('صور الزيارة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
        const SizedBox(height: 8),
        _pendingMediaList(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'إلغاء',
              variant: AppButtonVariant.outline,
              onPressed: _busy ? null : () => context.go('/dashboard'),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: _busy
                  ? 'جارٍ الحفظ...'
                  : (_outcome == SiteVisitOutcome.complied ? 'تأكيد النتيجة وإغلاق الحالة' : 'تأكيد النتيجة وإحالة للتقييم'),
              icon: Icons.check_circle_outline,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }

  Widget _outcomeOption(SiteVisitOutcome outcome) {
    final selected = _outcome == outcome;
    return InkWell(
      onTap: () => setState(() => _outcome = outcome),
      borderRadius: BorderRadius.circular(9),
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
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? AppColors.navy : AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(outcome.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(outcome.subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingMediaList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_media.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _media.length; i++)
                Chip(
                  label: Text(_media[i].name, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _media.removeAt(i)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickMedia,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderStrong, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.bg,
            ),
            child: const Column(
              children: [
                Icon(Icons.add_a_photo_outlined, size: 26, color: AppColors.textFaint),
                SizedBox(height: 8),
                Text('التقط أو ارفع صورًا أو فيديوهات للموقع',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _visitHistoryCard(SiteVisit visit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(visit.outcome.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
              Text(visit.visitedAt != null ? _fmt(visit.visitedAt!) : '—', style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          if (visit.notes != null && visit.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(visit.notes!, style: const TextStyle(fontSize: 12, color: AppColors.textBody)),
          ],
          if (visit.mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final url in visit.mediaUrls) MediaThumbnail(url: url, size: 56)]),
          ],
        ],
      ),
    );
  }

  Widget _buildSidePanel() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ماذا يحدث حسب النتيجة؟', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
          const SizedBox(height: 12),
          TimelineRail(
            items: [
              TimelineRailItem(
                state: _outcome == SiteVisitOutcome.complied ? RailItemState.current : RailItemState.pending,
                icon: Icons.check_circle_outline,
                title: 'تم الامتثال',
                body: 'الحالة تُغلق فورًا بوصفها CLOSED_SAFE.',
              ),
              TimelineRailItem(
                state: _outcome != SiteVisitOutcome.complied ? RailItemState.current : RailItemState.pending,
                icon: Icons.assignment_late_outlined,
                title: 'لم يتم الامتثال / امتثال جزئي',
                body: 'تُحال الحالة تلقائيًا إلى التقييم الخارجي (خطيب وعلمي).',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            Flexible(
              child: Text(v, textAlign: TextAlign.end, style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: AppColors.text)),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _shortId(String id) => 'NOTICE-${(id.length <= 8 ? id : id.substring(0, 8)).toUpperCase()}';
}