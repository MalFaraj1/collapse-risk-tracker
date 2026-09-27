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
import '../intake/models/complaint.dart';
import 'data/triage_repository.dart';
import 'models/triage.dart';

/// Urgency Triage — "فرز الأولوية" (§7.1a, BR-5, FR-TRI-1..4).
///
/// Engineering's first look at a logged complaint: review its narrative
/// and attached media (photos AND videos — see [MediaThumbnail]), then
/// decide whether this needs an immediate on-site engineer visit (Urgent)
/// or can be routed through the standard joint committee process (Not
/// Urgent). That single decision is what BR-6 later reads to auto-set an
/// Urgent review priority — see the Review & Decision screen once built.
///
/// This screen always operates on one specific complaint — there is no
/// meaningful way to "triage" without knowing which complaint. It's
/// reached with a complaint ID as a route parameter (`/triage/:complaintId`);
/// reaching it without one (e.g. the bare sidebar link) shows a short
/// explanatory empty state instead of a broken form.
class TriageScreen extends ConsumerStatefulWidget {
  const TriageScreen({super.key, this.complaintId});

  final String? complaintId;

  @override
  ConsumerState<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends ConsumerState<TriageScreen> {
  Complaint? _complaint;
  bool _loading = true;
  String? _loadError;

  bool _busy = false;
  String? _error;
  TriageUrgency _urgency = TriageUrgency.urgent;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.complaintId != null) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final complaint = await ref.read(triageRepositoryProvider).getComplaint(widget.complaintId!);
      if (!mounted) return;
      setState(() {
        _complaint = complaint;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = describeFirebaseError(e, 'تعذّر تحميل الشكوى');
          _loading = false;
        });
      }
    }
  }

  Future<void> _save({required bool isDraft}) async {
    final complaint = _complaint;
    if (complaint == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(triageRepositoryProvider).saveTriage(
            complaint: complaint,
            urgency: _urgency,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            isDraft: isDraft,
          );
      if (!mounted) return;
      if (isDraft) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ المسودة.')),
        );
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر حفظ الفرز'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.complaintId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('فرز الأولوية', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد شكوى للفرز',
              message:
                  'افتح هذه الشاشة من لوحة الإجراءات المستحقة أو من صفحة تفاصيل العقار لشكوى معيّنة — '
                  'لا يمكن فرز الأولوية دون معرفة الشكوى المقصودة.',
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _complaint == null) {
      return AppCard(
        child: AppAlert(
          kind: AppAlertKind.danger,
          title: 'تعذّر تحميل الشكوى',
          message: _loadError ?? 'الشكوى غير موجودة.',
        ),
      );
    }

    final complaint = _complaint!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('فرز الأولوية', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'مراجعة صور الشكوى وتحديد مسار المعالجة (BR-5, FR-TRI-1..4).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final mainCard = AppCard(child: _buildForm(complaint));
            final sidePanel = _buildSidePanel();
            if (!isWide) {
              return Column(children: [mainCard, const SizedBox(height: 18), sidePanel]);
            }
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

  Widget _buildForm(Complaint complaint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('العقار', complaint.parcelId),
        _kv('تاريخ البلاغ', _fmt(complaint.date)),
        _kv('قناة البلاغ', complaint.channel.label),
        const Divider(height: 32),
        const Text('وصف الشكوى', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
        const SizedBox(height: 8),
        Text(
          complaint.narrative.isEmpty ? '(لا يوجد وصف)' : complaint.narrative,
          style: const TextStyle(fontSize: 13, color: AppColors.textBody, height: 1.7),
        ),
        const SizedBox(height: 20),
        Text(
          'الصور والفيديوهات المرفقة (${complaint.photoUrls.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text),
        ),
        const SizedBox(height: 10),
        if (complaint.photoUrls.isEmpty)
          const Text('لم يتم إرفاق أي وسائط مع هذه الشكوى.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final url in complaint.photoUrls) MediaThumbnail(url: url, size: 100)],
          ),
        const Divider(height: 32),
        if (_error != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _error!),
          const SizedBox(height: 16),
        ],
        const Text('تقييم الأولوية *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
        const SizedBox(height: 10),
        _urgencyOption(
          value: TriageUrgency.urgent,
          title: 'عاجل (URGENT)',
          subtitle: 'إيفاد مهندس بلدي للمعاينة الفورية في الموقع',
        ),
        const SizedBox(height: 10),
        _urgencyOption(
          value: TriageUrgency.notUrgent,
          title: 'غير عاجل (NOT_URGENT)',
          subtitle: 'إحالة إلى اللجنة الهندسية المشتركة',
        ),
        const SizedBox(height: 18),
        const Text('ملاحظات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'أي ملاحظات إضافية تدعم القرار...'),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'حفظ كمسودة',
              variant: AppButtonVariant.outline,
              onPressed: _busy ? null : () => _save(isDraft: true),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: _busy
                  ? 'جارٍ الحفظ...'
                  : (_urgency == TriageUrgency.urgent ? 'تأكيد وإيفاد مهندس' : 'تأكيد الإحالة'),
              icon: _urgency == TriageUrgency.urgent ? Icons.bolt : Icons.check,
              onPressed: _busy ? null : () => _save(isDraft: false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _urgencyOption({required TriageUrgency value, required String title, required String subtitle}) {
    final selected = _urgency == value;
    return InkWell(
      onTap: () => setState(() => _urgency = value),
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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Indicators of potential danger" in the approved design reads like an
  /// automated finding from the photos ("the attached photos show
  /// structural cracks..."). This project has no image-analysis capability
  /// to actually back that claim, so this is deliberately reworded into an
  /// honest reviewer prompt instead of implying automated detection that
  /// doesn't exist.
  Widget _buildSidePanel() {
    final isUrgent = _urgency == TriageUrgency.urgent;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppAlert(
            kind: AppAlertKind.danger,
            title: 'تذكير',
            message:
                'راجع الصور والفيديوهات المرفقة بعناية — التشققات الإنشائية الواضحة أو ميل المبنى '
                'مؤشرات شائعة تستدعي تصنيف الحالة كعاجلة.',
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text('ماذا يحدث بعد ذلك؟', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
          const SizedBox(height: 12),
          TimelineRail(
            items: [
              TimelineRailItem(
                state: RailItemState.current,
                icon: isUrgent ? Icons.bolt : Icons.groups_outlined,
                title: isUrgent ? 'عاجل → إيفاد مهندس بلدي' : 'غير عاجل → إحالة إلى اللجنة الهندسية',
                body: isUrgent
                    ? 'تقرير المعاينة السريعة يغذّي المراجعة بأولوية عاجلة تلقائيًا (BR-6).'
                    : 'ينتظر تقرير اللجنة الهندسية المشتركة — عملية اللجنة الداخلية خارج نطاق هذا النظام (§2.2).',
              ),
              const TimelineRailItem(state: RailItemState.pending, icon: Icons.more_horiz, title: 'المراجعة والقرار'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            Flexible(
              child: Text(
                v,
                textAlign: TextAlign.end,
                style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: AppColors.text),
              ),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}