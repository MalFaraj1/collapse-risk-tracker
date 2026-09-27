import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/parcel_status.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/countdown_ring.dart';
import '../../core/widgets/status_badge.dart';
import '../review/models/decision.dart';
import 'data/evacuation_repository.dart';
import 'models/evacuation_execution.dart';

/// Evacuation Execution — "تنفيذ الإخلاء" (§6.2, §7.5, BR-7, FR-EVC-1..6).
///
/// Police's step-by-step tracker for carrying out an EVACUATION decision:
/// post the order (starts a 48-hour compliance clock), collect residents'
/// data, forward it to the Relief Authority, then a post-48h compliance
/// visit that either closes this out or triggers forced enforcement.
///
/// Reached with a decision ID (`/evacuation/:decisionId`) — this screen
/// only makes sense in the context of one specific evacuation decision,
/// same reasoning as every other decision-scoped screen in this app.
class EvacuationScreen extends ConsumerStatefulWidget {
  const EvacuationScreen({super.key, this.decisionId});

  final String? decisionId;

  @override
  ConsumerState<EvacuationScreen> createState() => _EvacuationScreenState();
}

class _EvacuationScreenState extends ConsumerState<EvacuationScreen> {
  bool _loading = true;
  String? _loadError;
  Decision? _decision;
  EvacuationExecution? _execution;
  bool _busy = false;
  String? _actionError;

  EvacuationRepository get _repo => ref.read(evacuationRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (widget.decisionId != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final decision = await _repo.getDecision(widget.decisionId!);
      if (decision == null) {
        if (mounted) setState(() { _loadError = 'القرار غير موجود.'; _loading = false; });
        return;
      }
      if (decision.action != DecisionAction.evacuation) {
        if (mounted) setState(() { _loadError = 'هذا القرار ليس أمر إخلاء.'; _loading = false; });
        return;
      }
      final execution = await _repo.getOrCreate(decision);
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _execution = execution;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loadError = describeFirebaseError(e, 'تعذّر تحميل بيانات الإخلاء'); _loading = false; });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() { _busy = true; _actionError = null; });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _actionError = describeFirebaseError(e, 'تعذّر حفظ الإجراء'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPosted() =>
      _runAction(() => _repo.markPosted(_execution!.id));

  Future<void> _markSentToRelief() =>
      _runAction(() => _repo.markSentToRelief(_execution!.id));

  Future<void> _promptResidentsData() async {
    final familyController = TextEditingController();
    final individualController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('جمع بيانات الشاغلين'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: familyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد العائلات'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: individualController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الأفراد'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (saved == true) {
      final families = int.tryParse(familyController.text.trim()) ?? 0;
      final individuals = int.tryParse(individualController.text.trim()) ?? 0;
      await _runAction(() => _repo.markResidentsDataCollected(_execution!.id, families: families, individuals: individuals));
    }
  }

  Future<void> _promptComplianceVisit() async {
    var selected = ComplianceOutcome.vacated;
    final outcome = await showDialog<ComplianceOutcome>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('نتيجة زيارة التحقق'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ComplianceOutcome>(
                value: ComplianceOutcome.vacated,
                groupValue: selected,
                title: const Text('تم إخلاء المبنى بالكامل'),
                onChanged: (v) => setSt(() => selected = v!),
              ),
              RadioListTile<ComplianceOutcome>(
                value: ComplianceOutcome.occupantsRemain,
                groupValue: selected,
                title: const Text('ما زال هناك شاغلون'),
                onChanged: (v) => setSt(() => selected = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (outcome != null) {
      await _runAction(() => _repo.recordComplianceVisit(_execution!.id, outcome: outcome));
    }
  }

  Future<void> _markEnforced() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإخلاء القسري'),
        content: const Text('سيتم تسجيل أن الإخلاء نُفّذ قسريًا لوجود شاغلين متبقّين بعد انتهاء المهلة. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed == true) {
      await _runAction(() => _repo.markEnforced(_execution!.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decisionId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تنفيذ الإخلاء', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد قرار إخلاء',
              message: 'افتح هذه الشاشة من لوحة الإجراءات المستحقة أو من صفحة تفاصيل العقار لقرار إخلاء معيّن.',
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null || _decision == null || _execution == null) {
      return AppCard(child: AppAlert(kind: AppAlertKind.danger, title: 'تعذّر التحميل', message: _loadError ?? ''));
    }

    final decision = _decision!;
    final execution = _execution!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('تنفيذ الإخلاء', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'متابعة خطوات تنفيذ أمر الإخلاء الصادر عن الفريق الهندسي (§6.2, BR-7, FR-EVC-1..6).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        const StatusBadge(status: ParcelStatus.evacuation),
        const SizedBox(height: 18),
        if (_actionError != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _actionError!),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final sidePanel = _buildSidePanel(execution);
            final mainPanel = _buildChecklist(execution);
            if (!isWide) return Column(children: [sidePanel, const SizedBox(height: 18), mainPanel]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: sidePanel),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: mainPanel),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSidePanel(EvacuationExecution execution) {
    final deadline = execution.complianceDeadline;
    final progress = _progress(execution);
    final urgent = progress > 0.85;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            children: [
              const Text('مهلة الامتثال — 48 ساعة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
              const SizedBox(height: 16),
              if (execution.postedDate == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('لم يبدأ العدّاد بعد — انشر أمر الإخلاء أولًا.', style: TextStyle(fontSize: 12, color: AppColors.textMuted), textAlign: TextAlign.center),
                )
              else ...[
                CountdownRing(
                  progress: progress,
                  urgent: urgent,
                  centerLabel: '${(progress * 100).round()}%',
                  subLabel: 'من المهلة القصوى',
                ),
                const SizedBox(height: 14),
                Text(
                  deadline == null ? '' : _remainingLabel(deadline),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: urgent ? AppColors.danger : AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('بيانات الشاغلين', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
              const SizedBox(height: 10),
              _kv('عدد العائلات', execution.familyCount?.toString() ?? '—'),
              _kv('عدد الأفراد', execution.individualCount?.toString() ?? '—'),
              _kv('حالة الإرسال للإغاثة', execution.residentsDataSentToRelief ? 'مكتمل ✓' : 'لم يتم بعد'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChecklist(EvacuationExecution execution) {
    return AppCardWithHeader(
      title: 'خطوات التنفيذ',
      icon: Icons.checklist_outlined,
      contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepRow(
            done: execution.postedDate != null,
            title: 'نشر أمر الإخلاء على المبنى',
            subtitle: 'يبدأ عدّاد الامتثال 48 ساعة من هذه اللحظة',
            timestamp: execution.postedDate,
            actionLabel: 'تسجيل',
            onAction: _busy ? null : _markPosted,
          ),
          _stepRow(
            done: execution.residentsDataCollected,
            enabled: execution.postedDate != null,
            title: 'جمع بيانات الشاغلين',
            subtitle: execution.residentsDataCollected
                ? '${execution.familyCount} عائلات — ${execution.individualCount} أفراد'
                : 'عدد العائلات والأفراد داخل المبنى',
            timestamp: execution.residentsDataCollectedDate,
            actionLabel: 'تسجيل',
            onAction: _busy || execution.postedDate == null ? null : _promptResidentsData,
          ),
          _stepRow(
            done: execution.residentsDataSentToRelief,
            enabled: execution.residentsDataCollected,
            title: 'إرسال بيانات الشاغلين للهيئة العليا للإغاثة',
            subtitle: 'لغايات بدل الإيواء والتعويض',
            timestamp: execution.residentsDataSentDate,
            actionLabel: 'تسجيل',
            onAction: _busy || !execution.residentsDataCollected ? null : _markSentToRelief,
          ),
          _stepRow(
            done: execution.complianceVisitDate != null,
            enabled: execution.postedDate != null,
            title: 'زيارة التحقق بعد 48 ساعة',
            subtitle: execution.complianceVisitDate != null
                ? execution.complianceOutcome?.label ?? ''
                : 'تحديد ما إذا كان هناك شاغلون متبقّون',
            timestamp: execution.complianceVisitDate,
            dueDate: execution.complianceVisitDate == null ? execution.complianceDeadline : null,
          ),
          _stepRow(
            done: execution.enforced,
            enabled: execution.complianceOutcome == ComplianceOutcome.occupantsRemain,
            title: 'تنفيذ الإخلاء القسري (إن لزم)',
            subtitle: execution.enforced ? 'تم التنفيذ' : 'يظهر فقط عند بقاء شاغلين بعد المهلة',
            timestamp: execution.enforcedDate,
            actionLabel: execution.complianceOutcome == ComplianceOutcome.occupantsRemain && !execution.enforced ? 'تنفيذ' : null,
            onAction: (_busy || execution.complianceOutcome != ComplianceOutcome.occupantsRemain || execution.enforced)
                ? null
                : _markEnforced,
            isLast: true,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppButton(
              label: _busy ? 'جارٍ الحفظ...' : 'تسجيل زيارة التحقق الآن',
              icon: Icons.domain_verification_outlined,
              expand: true,
              onPressed: (_busy || execution.postedDate == null || execution.complianceVisitDate != null)
                  ? null
                  : _promptComplianceVisit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow({
    required bool done,
    bool enabled = true,
    required String title,
    required String subtitle,
    DateTime? timestamp,
    DateTime? dueDate,
    String? actionLabel,
    VoidCallback? onAction,
    bool isLast = false,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.success : Colors.transparent,
                border: Border.all(color: done ? AppColors.success : AppColors.borderStrong, width: 2),
              ),
              child: done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (timestamp != null)
              Text(_fmtDateTime(timestamp), style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted))
            else if (dueDate != null)
              Text('مستحقة: ${_fmtDateTime(dueDate)}', style: AppTypography.mono(fontSize: 11, color: AppColors.warning))
            else if (actionLabel != null)
              AppButton(label: actionLabel, dense: true, variant: AppButtonVariant.outline, onPressed: onAction),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            Text(v, style: AppTypography.mono(fontSize: 12, weight: FontWeight.w700, color: AppColors.text)),
          ],
        ),
      );

  double _progress(EvacuationExecution execution) {
    final posted = execution.postedDate;
    if (posted == null) return 0;
    final elapsedMinutes = DateTime.now().difference(posted).inMinutes;
    return (elapsedMinutes / (48 * 60)).clamp(0.0, 1.0);
  }

  String _remainingLabel(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'انتهت المهلة';
    final hours = remaining.inHours;
    if (hours < 1) return 'تبقّى أقل من ساعة';
    if (hours == 1) return 'تبقّى ساعة واحدة فقط';
    if (hours == 2) return 'تبقّى ساعتان فقط';
    if (hours <= 10) return 'تبقّى $hours ساعات فقط';
    return 'تبقّى $hours ساعة فقط';
  }

  String _fmtDateTime(DateTime d) {
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }
}