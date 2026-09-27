import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../intake/models/case.dart';
import '../review/models/decision.dart';
import 'data/assessment_repository.dart';
import 'models/assessment.dart';
import 'models/funding_candidate.dart';
import 'models/restoration_study.dart';

enum _Tab { external, restoration, funding }

/// External Assessment, Restoration & Funding — "التقييم والترميم"
/// (§6.4, §7.6, §7.6a, BR-8, BR-10, FR-ASM-1..3, FR-RST-1..5).
///
/// The longest branch in the whole process. Reached with a decision ID
/// (`/assessment/:decisionId`) — an Assessment record only ever exists
/// because BR-8's trigger already fired automatically from Evacuation
/// (fully vacated) or Site Visit (Not-Complied/Partial); this screen never
/// creates the initial record itself, it only reads and progresses one
/// that already exists. If none exists yet for the given decision, that
/// means BR-8 hasn't triggered — shown as a clear state, not an error.
///
/// A NOTE ON THE APPROVED DESIGN'S MOCKUP: the reference screenshot shows
/// the external-opinion fields and the restoration-study fields together
/// in a single view under one highlighted tab. Read literally that would
/// mean the three tabs are cosmetic labels over one continuous form. This
/// implementation instead treats them as genuinely separate, since the
/// restoration study is only meaningful after an opinion of RESTORE is
/// saved, and the funding-candidates tab shows a fundamentally different,
/// municipality-wide dataset unrelated to this one case. The Restoration
/// tab is visibly present but disabled with an explanatory message until
/// its precondition is met, rather than hidden or force-combined into tab
/// one — a deliberate, disclosed reading of an otherwise ambiguous mockup.
class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({super.key, this.decisionId});

  final String? decisionId;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  bool _loading = true;
  String? _loadError;
  Decision? _decision;
  Case? _caseRecord;
  Assessment? _assessment;
  RestorationStudy? _study;
  List<FundingCandidate> _fundingCandidates = [];

  _Tab _activeTab = _Tab.external;

  DateTime? _orderSentDate;
  DateTime? _opinionReceivedDate;
  ExternalOpinion? _opinion;
  bool _savingExternal = false;
  String? _externalError;

  DateTime? _submittedDate;
  bool _engineeringApproved = false;
  OwnerCostCapacity? _ownerCostCapacity;
  bool _savingStudy = false;
  String? _studyError;

  AssessmentRepository get _repo => ref.read(assessmentRepositoryProvider);

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
        if (mounted) {
          setState(() {
            _loadError = 'القرار غير موجود.';
            _loading = false;
          });
        }
        return;
      }
      final caseRecord = await _repo.getCase(decision.caseId);
      final assessment = await _repo.getAssessment(decision.id);
      RestorationStudy? study;
      if (assessment?.opinion == ExternalOpinion.restore) {
        study = await _repo.getOrCreateStudy(assessment!);
      }
      final candidates = await _repo.getMunicipalFundingCandidates();
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _caseRecord = caseRecord;
        _assessment = assessment;
        _study = study;
        _fundingCandidates = candidates;
        _orderSentDate = assessment?.orderSentDate;
        _opinionReceivedDate = assessment?.opinionReceivedDate;
        _opinion = assessment?.opinion;
        _submittedDate = study?.submittedDate;
        _engineeringApproved = study?.engineeringApproved ?? false;
        _ownerCostCapacity = study?.ownerCostCapacity;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = describeFirebaseError(e, 'تعذّر تحميل بيانات التقييم');
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveExternal() async {
    setState(() {
      _savingExternal = true;
      _externalError = null;
    });
    try {
      await _repo.saveExternalAssessment(
        _assessment!,
        orderSentDate: _orderSentDate,
        opinionReceivedDate: _opinionReceivedDate,
        opinion: _opinion,
      );
      await _load();
    } catch (e) {
      if (mounted)
        setState(() =>
            _externalError = describeFirebaseError(e, 'تعذّر حفظ التقييم'));
    } finally {
      if (mounted) setState(() => _savingExternal = false);
    }
  }

  Future<void> _saveStudy() async {
    setState(() {
      _savingStudy = true;
      _studyError = null;
    });
    try {
      await _repo.saveRestorationStudy(
        _study!,
        submittedDate: _submittedDate,
        engineeringApproved: _engineeringApproved,
        ownerCostCapacity: _ownerCostCapacity,
      );
      await _load();
    } catch (e) {
      if (mounted)
        setState(() =>
            _studyError = describeFirebaseError(e, 'تعذّر حفظ دراسة الترميم'));
    } finally {
      if (mounted) setState(() => _savingStudy = false);
    }
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decisionId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('التقييم والترميم',
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد حالة للتقييم',
              message:
                  'افتح هذه الشاشة من لوحة الإجراءات المستحقة أو من صفحة تفاصيل العقار لحالة معيّنة.',
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(60),
          child: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null || _decision == null) {
      return AppCard(
          child: AppAlert(
              kind: AppAlertKind.danger,
              title: 'تعذّر التحميل',
              message: _loadError ?? ''));
    }

    if (_assessment == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('التقييم والترميم',
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لا يوجد تقييم مطلوب على هذه الحالة',
              message:
                  'يُنشأ التقييم تلقائيًا فقط عند إخلاء مبنى بالكامل أو عند عدم الامتثال لإنذار سابق (BR-8). '
                  'لم يتحقق أي من الشرطين بعد لهذا القرار.',
            ),
          ],
        ),
      );
    }

    final assessment = _assessment!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('التقييم والترميم',
            style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'متابعة رأي الجهة الخارجية ومسار الترميم أو التمويل (§6.4, §7.6, BR-8, BR-10).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        _tabBar(),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final mainCard = AppCard(child: _buildTabContent(assessment));
            final sidePanel = _buildSidePanel();
            if (!isWide)
              return Column(
                  children: [mainCard, const SizedBox(height: 18), sidePanel]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: mainCard),
                const SizedBox(width: 18),
                Expanded(child: sidePanel),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _tabBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _tabButton(_Tab.external, 'التقييم الخارجي'),
        const SizedBox(width: 22),
        _tabButton(_Tab.restoration, 'دراسة الترميم'),
        const SizedBox(width: 22),
        _tabButton(_Tab.funding, 'مرشّحو التمويل'),
      ],
    );
  }

  Widget _tabButton(_Tab tab, String label) {
    final selected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: selected ? AppColors.navy : Colors.transparent,
                  width: 2.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: selected ? AppColors.navy : AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _buildTabContent(Assessment assessment) {
    return switch (_activeTab) {
      _Tab.external => _externalTab(assessment),
      _Tab.restoration => _restorationTab(assessment),
      _Tab.funding => _fundingTab(),
    };
  }

  Widget _externalTab(Assessment assessment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.assignment_outlined,
                size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('أمر التقييم — شركة خطيب وعلمي',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AppColors.text)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kv('سبب الإحالة', assessment.triggerReason.label),
        const SizedBox(height: 16),
        if (_externalError != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _externalError!),
          const SizedBox(height: 16),
        ],
        _dateField('تاريخ إرسال الأمر', _orderSentDate,
            (d) => setState(() => _orderSentDate = d)),
        const SizedBox(height: 14),
        _dateField('تاريخ استلام الرأي', _opinionReceivedDate,
            (d) => setState(() => _opinionReceivedDate = d)),
        const SizedBox(height: 18),
        const Text('رأي الجهة الخارجية *',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.text)),
        const SizedBox(height: 10),
        for (final opinion in ExternalOpinion.values) ...[
          _radioOption(
            selected: _opinion == opinion,
            title: opinion.label,
            subtitle: opinion.subtitle,
            onTap: () => setState(() => _opinion = opinion),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: _savingExternal ? 'جارٍ الحفظ...' : 'حفظ التحديثات',
            icon: Icons.save_outlined,
            onPressed: _savingExternal ? null : _saveExternal,
          ),
        ),
      ],
    );
  }

  Widget _restorationTab(Assessment assessment) {
    if (assessment.opinion != ExternalOpinion.restore) {
      return AppAlert(
        kind: AppAlertKind.info,
        title: 'يتوفر هذا القسم بعد اختيار رأي "ترميم"',
        message: assessment.opinion == ExternalOpinion.demolish
            ? 'رأي الجهة الخارجية المسجَّل هو "هدم" — لا تنطبق دراسة الترميم على هذه الحالة.'
            : 'احفظ رأي الجهة الخارجية في تبويب "التقييم الخارجي" أولًا، واختر "ترميم" لفتح هذا القسم.',
      );
    }

    final study = _study;
    if (study == null) {
      return const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('دراسة الترميم (BR-10)',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.text)),
        const SizedBox(height: 16),
        if (_studyError != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _studyError!),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _dateField('تاريخ تقديم الدراسة', _submittedDate,
                    (d) => setState(() => _submittedDate = d))),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<bool>(
                value: _engineeringApproved,
                decoration:
                    const InputDecoration(labelText: 'موافقة الفريق الهندسي'),
                items: const [
                  DropdownMenuItem(value: true, child: Text('معتمدة')),
                  DropdownMenuItem(value: false, child: Text('قيد المراجعة')),
                ],
                onChanged: (v) => setState(
                    () => _engineeringApproved = v ?? _engineeringApproved),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('قدرة المالك المالية *',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.text)),
        const SizedBox(height: 10),
        for (final capacity in OwnerCostCapacity.values) ...[
          _radioOption(
            selected: _ownerCostCapacity == capacity,
            title: capacity.label,
            subtitle: '',
            onTap: () => setState(() => _ownerCostCapacity = capacity),
          ),
          const SizedBox(height: 10),
        ],
        if (_engineeringApproved &&
            _ownerCostCapacity == OwnerCostCapacity.cannotBear) ...[
          const SizedBox(height: 6),
          const AppAlert(
            kind: AppAlertKind.info,
            message:
                'سيُضاف تلقائيًا إلى قائمة مرشّحي التمويل — لأن الأوراق مكتملة والمالك غير قادر على تحمّل الكلفة.',
          ),
        ],
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: _savingStudy ? 'جارٍ الحفظ...' : 'حفظ التحديثات',
            icon: Icons.save_outlined,
            onPressed: _savingStudy ? null : _saveStudy,
          ),
        ),
      ],
    );
  }

  Widget _fundingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('مرشّحو التمويل — القائمة الكاملة',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.text)),
        const SizedBox(height: 6),
        const Text(
          'قائمة على مستوى البلدية بجميع المباني الجاهزة للترميم والتي لا يقدر أصحابها على تحمّل الكلفة.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        if (_fundingCandidates.isEmpty)
          const Text('لا يوجد مرشّحو تمويل حاليًا.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted))
        else
          for (final c in _fundingCandidates)
            _fundingCandidateRow(c, dense: false),
      ],
    );
  }

  Widget _buildSidePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('مرشّحو التمويل — قائمة البلدية',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.text)),
              const SizedBox(height: 10),
              if (_fundingCandidates.isEmpty)
                const Text('لا يوجد مرشّحون بعد.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              else
                for (final c in _fundingCandidates.take(5))
                  _fundingCandidateRow(c, dense: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تذكير',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.text)),
              SizedBox(height: 8),
              Text(
                'في حال عدم استكمال الترميم بعد المهلة المحددة تُحال الحالة تلقائيًا إلى مسار الهدم (FR-RST-5).',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textMuted, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fundingCandidateRow(FundingCandidate c, {required bool dense}) {
    final (icon, color) = switch (c.status) {
      FundingCandidateStatus.proposed => (
          Icons.hourglass_empty,
          AppColors.warning
        ),
      FundingCandidateStatus.selected => (
          Icons.check_circle_outline,
          AppColors.info
        ),
      FundingCandidateStatus.funded => (Icons.check_circle, AppColors.success),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 10 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.parcelId,
                    style: AppTypography.mono(
                        fontSize: dense ? 11.5 : 12.5,
                        weight: FontWeight.w700,
                        color: AppColors.text)),
                Text(c.status.label,
                    style: TextStyle(
                        fontSize: dense ? 10.5 : 11.5,
                        color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(
      String label, DateTime? value, ValueChanged<DateTime?> onPicked) {
    final controller =
        TextEditingController(text: value == null ? '' : _fmt(value));
    return TextField(
      readOnly: true,
      controller: controller,
      decoration: InputDecoration(labelText: label),
      onTap: () async {
        final picked = await _pickDate(value);
        if (picked != null) onPicked(picked);
      },
    );
  }

  Widget _radioOption(
      {required bool selected,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(9),
          color: selected ? AppColors.iceTint : AppColors.surface,
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.navy : AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: AppColors.text)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600)),
            Text(v,
                style: AppTypography.mono(
                    fontSize: 12.5,
                    weight: FontWeight.w700,
                    color: AppColors.text)),
          ],
        ),
      );

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
