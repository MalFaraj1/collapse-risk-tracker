import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../assessment/models/assessment.dart';
import '../demolition/models/demolition_order.dart';
import '../intake/models/case.dart';
import '../intake/models/complaint.dart';
import '../intake/models/parcel.dart';
import '../review/models/decision.dart';
import 'data/dashboard_repository.dart';

/// Due Actions dashboard — "الإجراءات المستحقة" (§7.8, FR-DASH-1..5).
///
/// Six live work queues, one per decision-scoped screen in the app:
/// complaints awaiting triage, triaged cases awaiting review, evacuation
/// decisions awaiting their compliance check, warning decisions awaiting
/// a site visit, assessments awaiting the external firm's opinion, and
/// demolition orders not yet executed. Before this existed, four of
/// those six screens — Evacuation, Site Visit, Assessment, Demolition —
/// had NO discoverable path anywhere in the app: Review & Decision only
/// ever navigates to Notice Preview after issuing a decision, never to
/// the screen that actually carries it out. Each screen was fully built
/// and fully functional, just unreachable without already knowing a
/// Firestore document ID.
///
/// All six queues are genuine Firestore snapshot listeners, visible to
/// every signed-in role — the same way Triage's and Review's queues
/// always have been. Role-based filtering (so a Call Center account
/// doesn't see Police's Evacuation/Demolition queues, say) is a
/// reasonable next step, but doing it only for the four new queues while
/// leaving the original two universally visible would be an inconsistent
/// half-measure; it belongs with Admin Settings' eventual user/role
/// directory (see the Reports Hub's R4 note for the identical gap).
///
/// "إجراءات متأخرة" (overdue) and "بانتظار زيارة ميدانية" are both
/// DERIVED from the queues themselves — `.length` and an
/// executionDate-in-the-past filter respectively — rather than separate
/// aggregate count queries. This removes two of the three Firestore
/// composite-index requirements this screen used to have.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  // Scroll anchors so the stat cards can jump to their queue.
  final _triageKey = GlobalKey();
  final _reviewKey = GlobalKey();
  final _evacuationKey = GlobalKey();
  final _siteVisitKey = GlobalKey();
  final _assessmentKey = GlobalKey();
  final _demolitionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(complaintsAwaitingTriageProvider);
    ref.invalidate(casesAwaitingReviewProvider);
    ref.invalidate(evacuationsInProgressProvider);
    ref.invalidate(siteVisitsNeededProvider);
    ref.invalidate(assessmentsPendingProvider);
    ref.invalidate(demolitionsInProgressProvider);
    ref.invalidate(closedThisMonthCountProvider);
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final awaitingAsync = ref.watch(complaintsAwaitingTriageProvider);
    final awaitingReviewAsync = ref.watch(casesAwaitingReviewProvider);
    final evacuationsAsync = ref.watch(evacuationsInProgressProvider);
    final siteVisitsAsync = ref.watch(siteVisitsNeededProvider);
    final assessmentsAsync = ref.watch(assessmentsPendingProvider);
    final demolitionsAsync = ref.watch(demolitionsInProgressProvider);
    final closedThisMonthAsync = ref.watch(closedThisMonthCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'الإجراءات المستحقة',
          subtitle: 'قائمة العمل الحية لكل فريق — الشكاوى والحالات والقرارات التي تنتظر إجراءً.',
          actions: [
            AppButton(
              label: 'تحديث',
              icon: Icons.refresh,
              variant: AppButtonVariant.outline,
              onPressed: _refreshAll,
            ),
            AppButton(
              label: 'شكوى جديدة',
              icon: Icons.add,
              onPressed: () => context.go('/intake/new'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildStatRow(
          awaitingAsync: awaitingAsync,
          evacuationsAsync: evacuationsAsync,
          siteVisitsAsync: siteVisitsAsync,
          closedThisMonthAsync: closedThisMonthAsync,
        ),
        const SizedBox(height: 28),
        _buildQueuesToolbar(),
        const SizedBox(height: 14),
        _queueCard<Complaint>(
          key: _triageKey,
          title: 'بانتظار الفرز',
          icon: Icons.rule_outlined,
          async: awaitingAsync,
          errorMessage: 'تعذّر تحميل الشكاوى بانتظار الفرز',
          parcelIdOf: (c) => c.parcelId,
          extraSearchOf: (c) => c.narrative,
          isOverdue: _isTriageOverdue,
          emptyIcon: Icons.task_alt,
          emptyTitle: 'لا توجد شكاوى بانتظار الفرز',
          emptyDescription: 'ستظهر هنا أي شكوى جديدة فور تسجيلها.',
          columns: const [
            DataColumn(label: Text('العقار')),
            DataColumn(label: Text('تاريخ البلاغ')),
            DataColumn(label: Text('القناة')),
            DataColumn(label: Text('وصف الشكوى')),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('')),
          ],
          rowBuilder: _buildTriageRow,
        ),
        const SizedBox(height: 16),
        _queueCard<Case>(
          key: _reviewKey,
          title: 'بانتظار المراجعة',
          icon: Icons.fact_check_outlined,
          async: awaitingReviewAsync,
          errorMessage: 'تعذّر تحميل الحالات بانتظار المراجعة',
          parcelIdOf: (c) => c.parcelId,
          isOverdue: (c) => c.dispatchedOnsiteAt != null,
          emptyIcon: Icons.fact_check_outlined,
          emptyTitle: 'لا توجد حالات بانتظار المراجعة',
          emptyDescription: 'ستظهر هنا أي حالة بعد فرزها وإيفاد مهندس أو إحالتها إلى اللجنة الهندسية.',
          columns: const [
            DataColumn(label: Text('العقار')),
            DataColumn(label: Text('نوع الإحالة')),
            DataColumn(label: Text('تاريخ الإحالة')),
            DataColumn(label: Text('')),
          ],
          rowBuilder: _buildReviewRow,
        ),
        const SizedBox(height: 16),
        _queueCard<Decision>(
          key: _evacuationKey,
          title: 'إخلاءات قيد التنفيذ',
          icon: Icons.exit_to_app_outlined,
          async: evacuationsAsync,
          errorMessage: 'تعذّر تحميل قرارات الإخلاء',
          parcelIdOf: (d) => d.parcelId,
          isOverdue: _isDecisionOverdue,
          emptyIcon: Icons.checklist_rtl_outlined,
          emptyTitle: 'لا توجد إخلاءات قيد التنفيذ',
          emptyDescription: 'ستظهر هنا أي قرار إخلاء فور صدوره من شاشة المراجعة والقرار.',
          columns: _decisionColumns,
          rowBuilder: (d) => _buildDecisionRow(d, 'متابعة الإخلاء', '/evacuation'),
        ),
        const SizedBox(height: 16),
        _queueCard<Decision>(
          key: _siteVisitKey,
          title: 'بانتظار زيارة ميدانية',
          icon: Icons.domain_verification_outlined,
          async: siteVisitsAsync,
          errorMessage: 'تعذّر تحميل الحالات بانتظار زيارة ميدانية',
          parcelIdOf: (d) => d.parcelId,
          isOverdue: _isDecisionOverdue,
          emptyIcon: Icons.checklist_rtl_outlined,
          emptyTitle: 'لا توجد حالات بانتظار زيارة ميدانية',
          emptyDescription: 'ستظهر هنا أي إنذار تدعيم أو ترميم فور صدوره، إلى حين تسجيل نتيجة الزيارة.',
          columns: _decisionColumns,
          rowBuilder: (d) => _buildDecisionRow(d, 'تسجيل زيارة', '/sitevisits'),
        ),
        const SizedBox(height: 16),
        _queueCard<Assessment>(
          key: _assessmentKey,
          title: 'بانتظار التقييم الخارجي',
          icon: Icons.assignment_outlined,
          async: assessmentsAsync,
          errorMessage: 'تعذّر تحميل حالات التقييم',
          parcelIdOf: (a) => a.parcelId,
          emptyIcon: Icons.assignment_turned_in_outlined,
          emptyTitle: 'لا توجد حالات بانتظار التقييم الخارجي',
          emptyDescription: 'ستظهر هنا أي حالة فور إخلاء مبنى بالكامل أو عدم الامتثال لإنذار سابق (BR-8).',
          columns: const [
            DataColumn(label: Text('العقار')),
            DataColumn(label: Text('سبب الإحالة')),
            DataColumn(label: Text('تاريخ إرسال الأمر')),
            DataColumn(label: Text('')),
          ],
          rowBuilder: _buildAssessmentRow,
        ),
        const SizedBox(height: 16),
        _queueCard<DemolitionOrder>(
          key: _demolitionKey,
          title: 'أوامر هدم قيد التنفيذ',
          icon: Icons.domain_disabled_outlined,
          async: demolitionsAsync,
          errorMessage: 'تعذّر تحميل أوامر الهدم',
          parcelIdOf: (o) => o.parcelId,
          isOverdue: (o) => o.executionDate.isBefore(DateTime.now()),
          emptyIcon: Icons.domain_disabled_outlined,
          emptyTitle: 'لا توجد أوامر هدم قيد التنفيذ',
          emptyDescription: 'يُنشأ أمر الهدم تلقائيًا فقط عند صدور رأي "هدم" من الجهة الخارجية في شاشة التقييم والترميم.',
          columns: const [
            DataColumn(label: Text('العقار')),
            DataColumn(label: Text('تنسيق الجهة الخارجية')),
            DataColumn(label: Text('تاريخ التنفيذ المجدول')),
            DataColumn(label: Text('')),
          ],
          rowBuilder: _buildDemolitionRow,
        ),
      ],
    );
  }

  // ==========================================================================
  // Queues toolbar — one search box that filters every queue below by
  // parcel number or address.
  // ==========================================================================
  Widget _buildQueuesToolbar() {
    final title = Text('قوائم العمل', style: Theme.of(context).textTheme.headlineMedium);
    final search = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'ابحث برقم العقار أو العنوان...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'مسح البحث',
                onPressed: _searchController.clear,
              ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 10), search],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            SizedBox(width: 340, child: search),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // Generic queue card — every queue shares the same loading/error/empty
  // handling, search filtering, and full-width table layout.
  // ==========================================================================
  Widget _queueCard<T>({
    required Key key,
    required String title,
    required IconData icon,
    required AsyncValue<List<T>> async,
    required String errorMessage,
    required String Function(T) parcelIdOf,
    String Function(T)? extraSearchOf,
    bool Function(T)? isOverdue,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyDescription,
    required List<DataColumn> columns,
    required DataRow Function(T) rowBuilder,
  }) {
    final items = async.valueOrNull;
    final hasOverdue = isOverdue != null && (items?.any(isOverdue) ?? false);
    final filtered = items?.where((item) => _matches(parcelIdOf(item), extra: extraSearchOf?.call(item))).toList();

    String? trailing;
    if (items != null && items.isNotEmpty) {
      trailing = _search.isEmpty ? 'الأقدم أولًا' : '${filtered!.length} مطابقة';
    }

    const padded = EdgeInsets.symmetric(horizontal: 22, vertical: 18);

    return AppCardWithHeader(
      key: key,
      title: title,
      icon: icon,
      count: items?.length,
      countColor: hasOverdue ? AppColors.danger : AppColors.navy,
      trailing: trailing,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))),
        ),
        error: (error, stack) => Padding(
          padding: padded,
          child: AppAlert(
            kind: AppAlertKind.danger,
            title: 'تعذّر التحميل',
            message: describeFirebaseError(error, errorMessage),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            return Padding(
              padding: padded,
              child: AppEmptyState(compact: true, icon: emptyIcon, title: emptyTitle, description: emptyDescription),
            );
          }
          if (filtered!.isEmpty) {
            return const Padding(
              padding: padded,
              child: AppEmptyState(compact: true, icon: Icons.search_off, title: 'لا نتائج مطابقة لبحثك في هذه القائمة'),
            );
          }
          return _table(columns: columns, rows: filtered.map(rowBuilder).toList());
        },
      ),
    );
  }

  /// A [DataTable] that fills the card's width (instead of shrinking to its
  /// content) and still scrolls horizontally when the window is too narrow.
  Widget _table({required List<DataColumn> columns, required List<DataRow> rows}) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            showCheckboxColumn: false,
            horizontalMargin: 22,
            columnSpacing: 28,
            headingRowHeight: 42,
            dataRowMinHeight: 58,
            dataRowMaxHeight: 64,
            columns: columns,
            rows: rows,
          ),
        ),
      ),
    );
  }

  bool _matches(String parcelId, {String? extra}) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    final address = ref.watch(parcelByIdProvider(parcelId)).valueOrNull?.address ?? '';
    return parcelId.toLowerCase().contains(q) ||
        address.toLowerCase().contains(q) ||
        (extra?.toLowerCase().contains(q) ?? false);
  }

  // ==========================================================================
  // Stat cards
  // ==========================================================================
  Widget _buildStatRow({
    required AsyncValue<List<Complaint>> awaitingAsync,
    required AsyncValue<List<Decision>> evacuationsAsync,
    required AsyncValue<List<Decision>> siteVisitsAsync,
    required AsyncValue<int> closedThisMonthAsync,
  }) {
    final evacuationOverdue = evacuationsAsync.valueOrNull?.any(_isDecisionOverdue) ?? false;
    final overdueCount = _combinedOverdueCount(evacuationsAsync, siteVisitsAsync);

    final cards = [
      _statCardFor(
        value: awaitingAsync.valueOrNull?.length,
        error: awaitingAsync.hasError ? awaitingAsync.error : null,
        fallbackMessage: 'تعذّر تحميل عدد الشكاوى بانتظار الفرز',
        label: 'بانتظار الفرز',
        icon: Icons.rule_outlined,
        iconColor: AppColors.warning,
        iconBackground: AppColors.warningBg,
        onTap: () => _scrollTo(_triageKey),
      ),
      _statCardFor(
        value: overdueCount,
        error: evacuationsAsync.hasError ? evacuationsAsync.error : (siteVisitsAsync.hasError ? siteVisitsAsync.error : null),
        fallbackMessage: 'تعذّر تحميل عدد الإجراءات المتأخرة',
        label: 'إجراءات متأخرة',
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerBg,
        highlight: (overdueCount ?? 0) > 0,
        onTap: () => _scrollTo(evacuationOverdue ? _evacuationKey : _siteVisitKey),
      ),
      _statCardFor(
        value: siteVisitsAsync.valueOrNull?.length,
        error: siteVisitsAsync.hasError ? siteVisitsAsync.error : null,
        fallbackMessage: 'تعذّر تحميل عدد الحالات بانتظار زيارة ميدانية',
        label: 'بانتظار زيارة ميدانية',
        icon: Icons.domain_verification_outlined,
        iconColor: AppColors.info,
        iconBackground: AppColors.infoBg,
        onTap: () => _scrollTo(_siteVisitKey),
      ),
      _statCardFor(
        value: closedThisMonthAsync.valueOrNull,
        error: closedThisMonthAsync.hasError ? closedThisMonthAsync.error : null,
        fallbackMessage: 'تعذّر تحميل عدد الحالات المُغلقة هذا الشهر',
        label: 'أُغلقت هذا الشهر',
        icon: Icons.task_alt,
        iconColor: AppColors.success,
        iconBackground: AppColors.successBg,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 480 ? 2 : 1);
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }

  int? _combinedOverdueCount(AsyncValue<List<Decision>> a, AsyncValue<List<Decision>> b) {
    final aList = a.valueOrNull;
    final bList = b.valueOrNull;
    if (aList == null || bList == null) return null;
    return aList.where(_isDecisionOverdue).length + bList.where(_isDecisionOverdue).length;
  }

  Widget _statCardFor({
    required int? value,
    required Object? error,
    required String fallbackMessage,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    bool highlight = false,
    VoidCallback? onTap,
  }) {
    if (error != null) {
      return StatCard(
        value: '—',
        label: label,
        icon: Icons.error_outline,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerBg,
        onTap: () => _showErrorDetail(context: context, title: label, error: error, fallbackMessage: fallbackMessage),
        trailing: const Tooltip(
          message: 'اضغط لعرض التفاصيل',
          child: Icon(Icons.info_outline, size: 16, color: AppColors.danger),
        ),
      );
    }
    return StatCard(
      value: value?.toString(),
      label: label,
      icon: icon,
      iconColor: iconColor,
      iconBackground: iconBackground,
      highlight: highlight,
      onTap: onTap,
      trailing: onTap == null ? null : const Icon(Icons.arrow_forward_ios, size: 13, color: AppColors.textFaint),
    );
  }

  void _showErrorDetail({
    required BuildContext context,
    required String title,
    required Object error,
    required String fallbackMessage,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعذّر تحميل: $title'),
        content: SingleChildScrollView(
          child: Text(describeFirebaseError(error, fallbackMessage), style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _refreshAll();
            },
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Row builders
  // ==========================================================================
  static bool _isTriageOverdue(Complaint c) => DateTime.now().difference(c.date) > const Duration(hours: 24);

  static bool _isDecisionOverdue(Decision d) => d.executionDate.isBefore(DateTime.now());

  static const _decisionColumns = [
    DataColumn(label: Text('العقار')),
    DataColumn(label: Text('الإجراء')),
    DataColumn(label: Text('تاريخ الاستحقاق')),
    DataColumn(label: Text('')),
  ];

  DataRow _row(String route, List<DataCell> cells) {
    return DataRow(onSelectChanged: (_) => context.go(route), cells: cells);
  }

  DataRow _buildTriageRow(Complaint complaint) {
    final overdue = _isTriageOverdue(complaint);
    final parcelAsync = ref.watch(parcelByIdProvider(complaint.parcelId));
    final route = '/triage/${complaint.id}';

    return _row(route, [
      DataCell(_parcelCell(parcelAsync, complaint.parcelId)),
      DataCell(Text(_fmt(complaint.date), style: AppTypography.mono(fontSize: 12))),
      DataCell(Text(complaint.channel.label, style: const TextStyle(fontSize: 12.5))),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            complaint.narrative.isEmpty ? '(لا يوجد وصف)' : complaint.narrative,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: complaint.narrative.isEmpty ? AppColors.textFaint : AppColors.textBody,
            ),
          ),
        ),
      ),
      DataCell(
        overdue
            ? _overduePill('متأخر ${_elapsed(complaint.date)}')
            : const Pill(label: 'بانتظار الفرز', color: AppColors.warning, backgroundColor: AppColors.warningBg, borderColor: AppColors.warningBorder),
      ),
      DataCell(_actionButton('بدء الفرز', route, primary: overdue)),
    ]);
  }

  DataRow _buildReviewRow(Case caseRecord) {
    final isUrgent = caseRecord.dispatchedOnsiteAt != null;
    final referralDate = isUrgent ? caseRecord.dispatchedOnsiteAt! : caseRecord.referredToCommitteeAt!;
    final parcelAsync = ref.watch(parcelByIdProvider(caseRecord.parcelId));
    final route = '/review/${caseRecord.id}';

    return _row(route, [
      DataCell(_parcelCell(parcelAsync, caseRecord.parcelId)),
      DataCell(
        isUrgent
            ? const Pill.solid(label: 'معاينة عاجلة', backgroundColor: AppColors.danger)
            : const Pill(label: 'اللجنة الهندسية', color: AppColors.info, backgroundColor: AppColors.infoBg, borderColor: AppColors.infoBorder),
      ),
      DataCell(Text(_fmt(referralDate), style: AppTypography.mono(fontSize: 12))),
      DataCell(_actionButton('بدء المراجعة', route, primary: isUrgent)),
    ]);
  }

  DataRow _buildDecisionRow(Decision decision, String actionLabel, String baseRoute) {
    final overdue = _isDecisionOverdue(decision);
    final parcelAsync = ref.watch(parcelByIdProvider(decision.parcelId));
    final route = '$baseRoute/${decision.id}';

    return _row(route, [
      DataCell(_parcelCell(parcelAsync, decision.parcelId)),
      DataCell(Text(decision.action.noticeTitle, style: const TextStyle(fontSize: 12.5))),
      DataCell(_dueDate(decision.executionDate, overdue)),
      DataCell(_actionButton(actionLabel, route, primary: overdue)),
    ]);
  }

  DataRow _buildAssessmentRow(Assessment assessment) {
    final parcelAsync = ref.watch(parcelByIdProvider(assessment.parcelId));
    final orderSent = assessment.orderSentDate != null;
    final route = '/assessment/${assessment.id}';

    return _row(route, [
      DataCell(_parcelCell(parcelAsync, assessment.parcelId)),
      DataCell(Text(assessment.triggerReason.label, style: const TextStyle(fontSize: 12.5))),
      DataCell(
        orderSent
            ? Text(_fmt(assessment.orderSentDate!), style: AppTypography.mono(fontSize: 12))
            : const Pill(label: 'لم يُرسَل بعد', color: AppColors.warning, backgroundColor: AppColors.warningBg, borderColor: AppColors.warningBorder),
      ),
      DataCell(_actionButton('متابعة التقييم', route)),
    ]);
  }

  DataRow _buildDemolitionRow(DemolitionOrder order) {
    final overdue = order.executionDate.isBefore(DateTime.now());
    final parcelAsync = ref.watch(parcelByIdProvider(order.parcelId));
    final route = '/demolition/${order.id}';

    return _row(route, [
      DataCell(_parcelCell(parcelAsync, order.parcelId)),
      DataCell(
        order.externalCoordinated
            ? const Pill(label: 'تم التنسيق', color: AppColors.success, backgroundColor: AppColors.successBg, borderColor: AppColors.successBorder)
            : const Pill(label: 'بانتظار التنسيق', color: AppColors.warning, backgroundColor: AppColors.warningBg, borderColor: AppColors.warningBorder),
      ),
      DataCell(_dueDate(order.executionDate, overdue)),
      DataCell(_actionButton('متابعة الهدم', route, primary: overdue)),
    ]);
  }

  // ==========================================================================
  // Shared cell helpers
  // ==========================================================================
  Widget _parcelCell(AsyncValue<Parcel?> parcelAsync, String parcelId) {
    final parcel = parcelAsync.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (parcel != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(parcel.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
          ),
        Text(parcelId, style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _dueDate(DateTime date, bool overdue) {
    if (!overdue) return Text(_fmt(date), style: AppTypography.mono(fontSize: 12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _overduePill('متأخر ${_elapsed(date)}'),
        const SizedBox(height: 3),
        Text(_fmt(date), style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _overduePill(String label) => Pill.solid(label: label, backgroundColor: AppColors.danger);

  Widget _actionButton(String label, String route, {bool primary = false}) {
    return AppButton(
      label: label,
      variant: primary ? AppButtonVariant.primary : AppButtonVariant.outline,
      dense: true,
      onPressed: () => context.go(route),
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _elapsed(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 1) return '${diff.inDays} ${diff.inDays == 1 ? "يوم" : "أيام"}';
    return '${diff.inHours} ساعة';
  }
}
