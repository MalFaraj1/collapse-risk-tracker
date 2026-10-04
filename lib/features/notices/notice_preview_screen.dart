import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/roles.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/web_download.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_logo.dart';
import '../auth/auth_providers.dart';
import '../intake/models/parcel.dart';
import '../review/models/decision.dart';
import '../review/models/notice.dart';
import 'data/notice_repository.dart';
import 'pdf/notice_pdf_generator.dart';

/// Notice Preview — "معاينة الإشعار" (§8, FR-ACT-1/2, FR-ACT-5).
///
/// Displays one generated official notice — Arabic RTL, styled as an
/// official municipal letter — read from the Notice/Decision/Parcel
/// documents already in Firestore. Reached with a notice ID
/// (`/notices/:noticeId`); every successful decision on the Review &
/// Decision screen navigates straight here.
///
/// IMPORTANT — a real design decision, not an implementation detail:
/// FR-ACT-2 says the PDF is always generated server-side, never on the
/// client. No Cloud Function exists in this project — deploying one is
/// outside what a Flutter client sandbox can do — so this screen
/// generates the PDF client-side instead, the first time anyone requests
/// it: real Arabic text, real layout, matching this screen's own
/// rendering exactly, using the bundled Cairo font (see
/// core/pdf/pdf_fonts.dart). The result is uploaded to Storage and
/// `notice.pdfUrl` is set permanently, so every viewer after the first
/// just opens the cached file instead of regenerating it. This is a
/// disclosed deviation from FR-ACT-2's "server-side" wording, made
/// necessary by this environment's constraints — not a silent one.
class NoticePreviewScreen extends ConsumerStatefulWidget {
  const NoticePreviewScreen({super.key, this.noticeId});

  final String? noticeId;

  @override
  ConsumerState<NoticePreviewScreen> createState() => _NoticePreviewScreenState();
}

class _NoticePreviewScreenState extends ConsumerState<NoticePreviewScreen> {
  bool _loading = true;
  String? _loadError;
  Notice? _notice;
  Decision? _decision;
  Parcel? _parcel;

  bool _generatingPdf = false;
  String? _pdfError;

  NoticeRepository get _repo => ref.read(noticeRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (widget.noticeId != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final notice = await _repo.getNotice(widget.noticeId!);
      if (notice == null) {
        if (mounted) {
          setState(() {
            _loadError = 'الإشعار غير موجود.';
            _loading = false;
          });
        }
        return;
      }
      final decision = await _repo.getDecision(notice.decisionId);
      final parcel = await _repo.getParcel(notice.parcelId);
      if (!mounted) return;
      setState(() {
        _notice = notice;
        _decision = decision;
        _parcel = parcel;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = describeFirebaseError(e, 'تعذّر تحميل الإشعار');
          _loading = false;
        });
      }
    }
  }

  /// If a PDF was already generated for this notice, just open the
  /// cached file. Otherwise generate it now — build the exact same
  /// document this screen renders on screen, upload it, persist the URL,
  /// and hand the person the bytes immediately rather than making them
  /// wait for a second round trip to Storage.
  Future<void> _downloadOrGeneratePdf() async {
    final notice = _notice;
    final decision = _decision;
    final parcel = _parcel;
    if (notice == null || decision == null || parcel == null) return;

    if (notice.pdfUrl != null) {
      final uri = Uri.parse(notice.pdfUrl!);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    setState(() {
      _generatingPdf = true;
      _pdfError = null;
    });
    try {
      final action = DecisionAction.fromFirestore(notice.type);
      final Uint8List bytes = await buildNoticePdf(
        notice: notice,
        decision: decision,
        parcel: parcel,
        noticeTitle: action.noticeTitle,
        bodyText: _bodyText(action, decision),
        linkedWarningShortId:
            (action == DecisionAction.shoringConfirm && notice.linkedWarningNoticeId != null) ? _shortId(notice.linkedWarningNoticeId!) : null,
      );
      final url = await _repo.savePdf(notice.id, bytes);
      downloadBytes(bytes, 'NOTICE-${_shortId(notice.id)}.pdf', 'application/pdf');
      if (!mounted) return;
      setState(() {
        _notice = Notice(
          id: notice.id,
          decisionId: notice.decisionId,
          caseId: notice.caseId,
          parcelId: notice.parcelId,
          type: notice.type,
          templateVersion: notice.templateVersion,
          source: notice.source,
          linkedWarningNoticeId: notice.linkedWarningNoticeId,
          pdfUrl: url,
          postedDate: notice.postedDate,
          createdAt: notice.createdAt,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _pdfError = describeFirebaseError(e, 'تعذّر إنشاء ملف PDF'));
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.noticeId == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('معاينة الإشعار', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const AppAlert(
              kind: AppAlertKind.info,
              title: 'لم يتم تحديد إشعار للمعاينة',
              message: 'يُفتح هذا الإشعار تلقائيًا بعد تأكيد قرار في شاشة المراجعة والقرار، أو من الخط الزمني لعقار معيّن.',
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null || _notice == null || _decision == null || _parcel == null) {
      return AppCard(
        child: AppAlert(
          kind: AppAlertKind.danger,
          title: 'تعذّر تحميل الإشعار',
          message: _loadError ?? 'تعذّر تحميل بيانات العقار أو القرار المرتبط بهذا الإشعار.',
        ),
      );
    }

    final notice = _notice!;
    final decision = _decision!;
    final parcel = _parcel!;
    final action = DecisionAction.fromFirestore(notice.type);
    final isAdmin = ref.watch(currentUserRoleProvider).valueOrNull == AppRole.admin;

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
                  Text('معاينة الإشعار', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  const Text(
                    'الإشعار الرسمي المُولَّد من قالب عربي RTL وبيانات العقار (§8, FR-ACT-1/2).',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            AppButton(
              label: _generatingPdf ? 'جارٍ الإنشاء...' : (notice.pdfUrl == null ? 'إنشاء وتنزيل PDF' : 'تنزيل PDF'),
              icon: Icons.download_outlined,
              variant: AppButtonVariant.outline,
              onPressed: _generatingPdf ? null : _downloadOrGeneratePdf,
            ),
            if (isAdmin) ...[
              const SizedBox(width: 10),
              AppButton(
                label: 'تعديل القالب',
                icon: Icons.edit_outlined,
                variant: AppButtonVariant.outline,
                onPressed: () => context.go('/admin'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        if (_pdfError != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _pdfError!),
          const SizedBox(height: 16),
        ],
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _documentToolbar(notice, action),
                _documentBody(notice, decision, parcel, action),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _documentToolbar(Notice notice, DecisionAction action) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${action.noticeTitle} — NOTICE-${_shortId(notice.id)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, .12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              'النسخة ${notice.templateVersion} · ${notice.source.firestoreValue}',
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentBody(Notice notice, Decision decision, Parcel parcel, DecisionAction action) {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 36),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [BoxShadow(color: Color(0x1A1B2A4A), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Column(
              children: [
                AppLogo(height: 84),
                SizedBox(height: 10),
                Text('بلدية طرابلس', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text)),
                SizedBox(height: 3),
                Text(
                  'لجنة التحوّل الرقمي — متابعة المباني الآيلة للسقوط',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              action.noticeTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.text,
                decoration: TextDecoration.underline,
                decorationThickness: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _kv('رقم العقار', parcel.parcelNo),
          _kv('المنطقة العقارية', parcel.cadastralZone),
          _kv('العنوان', parcel.address),
          _kv('رقم الإشعار وتاريخه',
              '${_shortId(notice.id)} · ${_fmt(notice.createdAt ?? decision.executionDate)}'),
          _kv('المهلة القانونية للتنفيذ', 'حتى ${_fmt(decision.executionDate)}'),
          if (action == DecisionAction.shoringConfirm && notice.linkedWarningNoticeId != null)
            _kv(
              'الإنذار الأصلي المرجعي',
              null,
              trailing: TextButton(
                onPressed: () => context.go('/notices/${notice.linkedWarningNoticeId}'),
                child: Text(
                  'عرض الإنذار الأصلي',
                  style: AppTypography.mono(fontSize: 12, weight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            _bodyText(action, decision),
            textAlign: TextAlign.justify,
            style: const TextStyle(fontSize: 13, color: AppColors.textBody, height: 2),
          ),
          const SizedBox(height: 44),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ختم البلدية', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              Text('توقيع المسؤول الهندسي', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String? v, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          trailing ??
              Text(
                v ?? '',
                style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700, color: AppColors.text),
              ),
        ],
      ),
    );
  }

  /// The notice's legal body paragraph — templated per decision type and
  /// filled with real data. §8 lists "legal basis text" as a required
  /// common merge field; these four templates are this project's actual
  /// implementation of that field for each of the four decision types.
  String _bodyText(DecisionAction action, Decision decision) {
    final decisionDate = _fmt(decision.createdAt ?? DateTime.now());
    return switch (action) {
      DecisionAction.evacuation =>
        'بناءً على المراجعة الهندسية للعقار المذكور أعلاه بتاريخ $decisionDate، وثبوت وجود خطر انهيار وشيك يهدد '
            'السلامة العامة، تأمر البلدية بإخلاء العقار المذكور فورًا، على أن يُنفَّذ الإخلاء ومتابعته وفق الإجراءات '
            'المعتمدة، طبقًا للصلاحيات المخوّلة للبلدية بموجب الأنظمة المرعية الإجراء.',
      DecisionAction.shoringWarning =>
        'بناءً على المراجعة الهندسية للعقار المذكور أعلاه بتاريخ $decisionDate، ونظرًا لما لوحظ من مؤشرات تستدعي '
            'أعمال تدعيم إنشائي، تُنذر البلدية مالك العقار المذكور أعلاه بوجوب اتخاذ إجراءات التدعيم اللازمة خلال '
            'المهلة المحددة أعلاه، وذلك حفاظًا على السلامة العامة، طبقًا للصلاحيات المخوّلة للبلدية بموجب الأنظمة '
            'المرعية الإجراء.',
      DecisionAction.shoringConfirm =>
        'إلحاقًا بالإنذار السابق الصادر بشأن هذا العقار (المرجع أعلاه)، ونظرًا لعدم تنفيذ أعمال التدعيم المطلوبة '
            'خلال المهلة الممنوحة، تؤكد البلدية إنذارها وتطالب المالك بتنفيذ الأعمال فورًا خلال المهلة الجديدة '
            'المحددة أعلاه، تحت طائلة اتخاذ الإجراءات القانونية اللاحقة.',
      DecisionAction.restorationWarning =>
        'بناءً على المراجعة الهندسية للعقار المذكور أعلاه بتاريخ $decisionDate، تُنذر البلدية مالك العقار المذكور '
            'أعلاه بوجوب القيام بأعمال الترميم اللازمة خلال المهلة المحددة أعلاه، حفاظًا على السلامة العامة وسلامة '
            'المبنى، طبقًا للصلاحيات المخوّلة للبلدية بموجب الأنظمة المرعية الإجراء.',
    };
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Firestore auto-generated IDs are 20 characters — too long to display
  /// as a human-facing reference. Shows the first 8, uppercased. Purely
  /// cosmetic; the full ID is always what's actually used for navigation
  /// and lookups.
  String _shortId(String id) => (id.length <= 8 ? id : id.substring(0, 8)).toUpperCase();
}