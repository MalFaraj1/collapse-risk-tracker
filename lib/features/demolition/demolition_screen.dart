import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../review/models/decision.dart';
import 'data/demolition_repository.dart';
import 'models/demolition_order.dart';

/// Demolition Orders — "أوامر الهدم" (§6.6, §7.7, BR-9, FR-DEM-1..3).
///
/// The final stage for a building that cannot be saved. Reached with a
/// decision ID (`/demolition/:decisionId`) — a demolition order only ever
/// exists because Assessment's DEMOLISH opinion already triggered it
/// automatically; this screen never creates the initial order itself.
///
/// LAYOUT NOTE, matching the approved design precisely: unlike every other
/// checklist-style screen in this app (Evacuation's actionable checklist
/// is the main/right panel), here the roles are reversed — the read-only
/// step checklist is the main (right) panel, and the actionable form
/// (coordination, contractor, execution) sits in the narrower (left) side
/// panel. Steps 1–2 (posting the notice, scheduling the execution date)
/// are always already complete by the time this screen is opened, since
/// they're resolved automatically at trigger time — this screen's own
/// job is only steps 3–4.
class DemolitionScreen extends ConsumerStatefulWidget {
  const DemolitionScreen({super.key, this.decisionId});

  final String? decisionId;

  @override
  ConsumerState<DemolitionScreen> createState() => _DemolitionScreenState();
}

class _DemolitionScreenState extends ConsumerState<DemolitionScreen> {
  bool _loading = true;
  String? _loadError;
  Decision? _decision;
  DemolitionOrder? _order;

  bool _savingCoordination = false;
  final _contractorController = TextEditingController();
  DateTime? _actualExecutionDate;
  late final TextEditingController _actualExecutionDateController;
  bool _confirming = false;
  String? _actionError;

  DemolitionRepository get _repo => ref.read(demolitionRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _actualExecutionDateController = TextEditingController();
    if (widget.decisionId != null) _load();
  }

  @override
  void dispose() {
    _contractorController.dispose();
    _actualExecutionDateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final decision = await _repo.getDecision(widget.decisionId!);
      if (decision == null) {
        if (mounted) {
          setState(() {
            _loadError = 'القرار غير موجود.';
            _loading = false;
          });
        }
        return;
      }
      final order = await _repo.getOrder(decision.id);
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _order = order;
        _contractorController.text = order?.contractorReference ?? '';
        _actualExecutionDate = order?.actualExecutionDate;
        _actualExecutionDateController.text = _actualExecutionDate == null ? '' : _fmt(_actualExecutionDate!);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = describeFirebaseError(e, 'تعذّر تحميل أمر الهدم');
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleCoordination(bool value) async {
    if (_order == null) return;
    setState(() => _savingCoordination = true);
    try {
      await _repo.setCoordinated(_order!.id, value);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _actionError = describeFirebaseError(e, 'تعذّر حفظ التنسيق'));
    } finally {
      if (mounted) setState(() => _savingCoordination = false);
    }
  }

  Future<void> _pickActualExecutionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _actualExecutionDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _actualExecutionDate = picked;
        _actualExecutionDateController.text = _fmt(picked);
      });
    }
  }

  bool get _canConfirm =>
      _order != null &&
      !_order!.executed &&
      _order!.externalCoordinated &&
      _contractorController.text.trim().isNotEmpty &&
      _actualExecutionDate != null;

  Future<void> _confirmExecution() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد تنفيذ الهدم'),
        content: const Text(
          'هذا الإجراء نهائي ولا يمكن التراجع عنه. سيتم تسجيل تنفيذ الهدم وإغلاق الحالة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _confirming = true;
      _actionError = null;
    });
    try {
      await _repo.confirmExecution(
        _order!,
        contractorReference: _contractorController.text.trim(),
        actualExecutionDate: _actualExecutionDate!,
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _actionError = describeFirebaseError(e, 'تعذّر تأكيد تنفيذ الهدم'));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decisionId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('أوامر الهدم', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد قرار للهدم',
              message: 'افتح هذه الشاشة من لوحة الإجراءات المستحقة أو من صفحة تفاصيل العقار لقرار معيّن.',
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

    if (_order == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('أوامر الهدم', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لا يوجد أمر هدم على هذه الحالة',
              message: 'يُنشأ أمر الهدم تلقائيًا فقط عند صدور رأي "هدم" من الجهة الخارجية في شاشة التقييم والترميم (BR-8/BR-9).',
            ),
          ],
        ),
      );
    }

    final order = _order!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('أوامر الهدم', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'متابعة تنفيذ الهدم بعد التنسيق مع الجهة الخارجية والمتعهد (BR-9, FR-DEM-1..3, §6.6).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        if (order.executed) ...[
          const AppAlert(kind: AppAlertKind.success, title: 'تم تنفيذ الهدم', message: 'أُغلقت الحالة. لا حاجة لأي إجراء إضافي.'),
          const SizedBox(height: 16),
        ],
        if (_actionError != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _actionError!),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final checklist = AppCardWithHeader(
              title: 'خطوات التنفيذ',
              icon: Icons.checklist_outlined,
              contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
              child: _buildChecklist(order),
            );
            final formPanel = AppCard(child: _buildForm(order));
            if (!isWide) return Column(children: [checklist, const SizedBox(height: 18), formPanel]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: checklist),
                const SizedBox(width: 18),
                Expanded(child: formPanel),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildChecklist(DemolitionOrder order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRow(
          done: true,
          title: 'نشر إشعار الهدم على المبنى',
          timestamp: order.postedDate,
        ),
        _stepRow(
          done: true,
          title: 'تحديد تاريخ التنفيذ',
          timestamp: order.postedDate,
          subLabel: _fmt(order.executionDate),
        ),
        _stepRow(
          done: order.externalCoordinated,
          title: 'تنسيق حضور الجهة الخارجية (خطيب وعلمي)',
          timestamp: order.externalCoordinatedDate,
        ),
        _stepRow(
          done: order.executed,
          title: 'تكليف المتعهد (أمر مباشرة) وتنفيذ الهدم',
          timestamp: order.actualExecutionDate,
          subLabel: order.executed ? order.contractorReference : null,
          isLast: true,
        ),
      ],
    );
  }

  Widget _stepRow({required bool done, required String title, DateTime? timestamp, String? subLabel, bool isLast = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                if (subLabel != null && subLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subLabel, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          if (timestamp != null)
            Text(_fmt(timestamp), style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildForm(DemolitionOrder order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('بيانات التنفيذ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.text)),
        const SizedBox(height: 16),
        InkWell(
          onTap: (_savingCoordination || order.executed) ? null : () => _toggleCoordination(!order.externalCoordinated),
          child: Row(
            children: [
              Checkbox(
                value: order.externalCoordinated,
                onChanged: (_savingCoordination || order.executed) ? null : (v) => _toggleCoordination(v ?? false),
                activeColor: AppColors.navy,
              ),
              const Expanded(
                child: Text('تنسيق حضور الجهة الخارجية الخارجية', style: TextStyle(fontSize: 12.5, color: AppColors.text)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text('تم التنسيق', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 18),
        TextField(
          controller: _contractorController,
          enabled: !order.executed,
          decoration: const InputDecoration(labelText: 'المتعهد المكلّف', hintText: 'اسم الشركة أو المرجع'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextField(
          readOnly: true,
          enabled: !order.executed,
          controller: _actualExecutionDateController,
          decoration: const InputDecoration(labelText: 'تاريخ التنفيذ الفعلي'),
          onTap: order.executed ? null : _pickActualExecutionDate,
        ),
        const SizedBox(height: 22),
        AppButton(
          label: order.executed ? 'تم التنفيذ' : (_confirming ? 'جارٍ الحفظ...' : 'تأكيد تنفيذ الهدم'),
          icon: Icons.dangerous_outlined,
          expand: true,
          variant: order.executed ? AppButtonVariant.outline : AppButtonVariant.danger,
          onPressed: (order.executed || _confirming || !_canConfirm) ? null : _confirmExecution,
        ),
        if (!order.executed && !order.externalCoordinated) ...[
          const SizedBox(height: 10),
          const Text(
            'يجب إتمام التنسيق مع الجهة الخارجية أولًا قبل تأكيد التنفيذ (BR-9).',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}