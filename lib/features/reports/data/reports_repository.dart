import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../assessment/models/funding_candidate.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/case.dart';
import '../../intake/models/parcel.dart';
import '../../review/models/decision.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(firestore: ref.watch(firestoreProvider));
});

/// A report's data, already shaped as a plain table — every export path
/// (PDF via [buildReportPdf], Excel via [buildExcelWorkbook]) takes
/// exactly this shape, so a report's data-fetching logic is written once
/// and never needs to know which export format will consume it.
class ReportResult {
  const ReportResult({required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;
}

/// Data aggregation for the five reports that are actually buildable from
/// data this project has (§9: R1, R2, R3, R5, R7). R4 (per-team workload)
/// and R6 (full audit trail) are NOT implemented here — see the Reports
/// Hub screen's own doc comment for exactly why each is blocked by
/// missing infrastructure rather than simply unbuilt by choice.
class ReportsRepository {
  ReportsRepository({required this.firestore});
  final FirebaseFirestore firestore;

  String _fmt(DateTime? d) => d == null ? '—' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// R1 — Parcel/case status summary: current status and last-updated
  /// date per parcel (§9). Optional zone/status filters, matching the
  /// spec's stated filter set for this report exactly.
  Future<ReportResult> buildR1ParcelStatusSummary({String? zone, ParcelStatus? status}) async {
    final snap = await firestore.collection(FirestorePaths.parcels).orderBy('updatedAt', descending: true).limit(500).get();
    final parcels = snap.docs.map(Parcel.fromFirestore).where((p) {
      final matchesZone = zone == null || zone.isEmpty || p.cadastralZone == zone;
      final matchesStatus = status == null || p.status == status;
      return matchesZone && matchesStatus;
    }).toList();

    return ReportResult(
      headers: const ['العقار', 'المنطقة العقارية', 'العنوان', 'الحالة', 'آخر تحديث'],
      rows: [
        for (final p in parcels) [p.id, p.cadastralZone, p.address, p.status.label, _fmt(p.updatedAt)],
      ],
    );
  }

  /// R2 — Parcels grouped by current stage (§9). A single aggregate
  /// count table across all [ParcelStatus] values, always in the same
  /// order as the enum itself so the state-machine's natural progression
  /// reads top to bottom.
  Future<ReportResult> buildR2ParcelsByStage({String? zone}) async {
    final snap = await firestore.collection(FirestorePaths.parcels).limit(2000).get();
    final parcels = snap.docs.map(Parcel.fromFirestore).where((p) => zone == null || zone.isEmpty || p.cadastralZone == zone);

    final counts = {for (final s in ParcelStatus.values) s: 0};
    for (final p in parcels) {
      counts[p.status] = (counts[p.status] ?? 0) + 1;
    }

    return ReportResult(
      headers: const ['الحالة', 'عدد العقارات'],
      rows: [
        for (final s in ParcelStatus.values) [s.label, counts[s].toString()],
      ],
    );
  }

  /// R3 — Overdue and upcoming actions (§9). "Due soon" is a 7-day
  /// look-ahead window; unresolved decisions are split into two labeled
  /// groups within one table rather than two separate reports, since a
  /// single work list ordered soonest-first is what a team actually
  /// scans through.
  Future<ReportResult> buildR3OverdueAndUpcoming() async {
    final snap = await firestore.collection(FirestorePaths.decisions).orderBy('executionDate', descending: false).limit(500).get();
    final decisions = snap.docs.map(Decision.fromFirestore).where((d) => !d.resolved).toList();

    final now = DateTime.now();
    final dueSoonCutoff = now.add(const Duration(days: 7));
    final relevant = decisions.where((d) => d.executionDate.isBefore(dueSoonCutoff)).toList()
      ..sort((a, b) => a.executionDate.compareTo(b.executionDate));

    final parcels = await _resolveParcels(relevant.map((d) => d.parcelId).toSet());

    return ReportResult(
      headers: const ['العقار', 'الإجراء', 'تاريخ الاستحقاق', 'الحالة'],
      rows: [
        for (final d in relevant)
          [
            parcels[d.parcelId]?.address ?? d.parcelId,
            d.action.noticeTitle,
            _fmt(d.executionDate),
            d.executionDate.isBefore(now) ? 'متأخر' : 'مستحق قريبًا',
          ],
      ],
    );
  }

  /// R5 — One-page monthly council roll-up (§9): new cases, actions
  /// issued by type, evacuations, demolitions, and open-vs-closed counts
  /// for the given month. Shaped as a plain indicator/value table since
  /// its metrics are heterogeneous, not one homogeneous list of records.
  Future<ReportResult> buildR5MonthlyRollup(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    bool inMonth(DateTime? d) => d != null && !d.isBefore(start) && d.isBefore(end);

    final casesSnap = await firestore.collection(FirestorePaths.cases).orderBy('openedAt', descending: true).limit(1000).get();
    final cases = casesSnap.docs.map(Case.fromFirestore).toList();
    final newCases = cases.where((c) => inMonth(c.openedAt)).length;
    final closedThisMonth = cases.where((c) => inMonth(c.closedAt)).length;
    final openNow = cases.where((c) => c.status == CaseStatus.open).length;

    final decisionsSnap = await firestore.collection(FirestorePaths.decisions).orderBy('createdAt', descending: true).limit(1000).get();
    final decisions = decisionsSnap.docs.map(Decision.fromFirestore).where((d) => inMonth(d.createdAt)).toList();
    final evacuations = decisions.where((d) => d.action == DecisionAction.evacuation).length;
    final shoringWarnings = decisions.where((d) => d.action == DecisionAction.shoringWarning).length;
    final shoringConfirms = decisions.where((d) => d.action == DecisionAction.shoringConfirm).length;
    final restorationWarnings = decisions.where((d) => d.action == DecisionAction.restorationWarning).length;

    final demolitionSnap = await firestore.collection(FirestorePaths.demolitionOrders).limit(1000).get();
    final demolitionsThisMonth = demolitionSnap.docs
        .where((doc) => inMonth((doc.data()['actualExecutionDate'] as Timestamp?)?.toDate()))
        .length;

    final monthLabel = '${month.year}-${month.month.toString().padLeft(2, '0')}';

    return ReportResult(
      headers: const ['المؤشر', 'القيمة'],
      rows: [
        ['الشهر', monthLabel],
        ['حالات جديدة', newCases.toString()],
        ['أوامر إخلاء صادرة', evacuations.toString()],
        ['إنذارات تدعيم صادرة', shoringWarnings.toString()],
        ['تأكيدات تدعيم صادرة', shoringConfirms.toString()],
        ['إنذارات ترميم صادرة', restorationWarnings.toString()],
        ['عمليات هدم منفَّذة', demolitionsThisMonth.toString()],
        ['حالات أُغلقت خلال الشهر', closedThisMonth.toString()],
        ['حالات مفتوحة حاليًا (إجمالي)', openNow.toString()],
      ],
    );
  }

  /// R7 — Restoration funding candidates (§9): reuses the exact
  /// municipality-wide query already built for the Assessment screen's
  /// side panel — this is the same data, just exported as a full report
  /// instead of a preview list.
  Future<ReportResult> buildR7FundingCandidates({FundingCandidateStatus? status}) async {
    final snap = await firestore.collection(FirestorePaths.fundingCandidates).orderBy('proposedDate', descending: true).limit(500).get();
    final candidates = snap.docs.map(FundingCandidate.fromFirestore).where((c) => status == null || c.status == status).toList();
    final parcels = await _resolveParcels(candidates.map((c) => c.parcelId).toSet());

    return ReportResult(
      headers: const ['العقار', 'الحالة', 'جهة التمويل', 'تاريخ الاقتراح'],
      rows: [
        for (final c in candidates)
          [parcels[c.parcelId]?.address ?? c.parcelId, c.status.label, c.funder ?? '—', _fmt(c.proposedDate)],
      ],
    );
  }

  Future<Map<String, Parcel>> _resolveParcels(Set<String> parcelIds) async {
    final results = await Future.wait(parcelIds.map((id) async {
      final doc = await firestore.collection(FirestorePaths.parcels).doc(id).get();
      return doc.exists ? Parcel.fromFirestore(doc) : null;
    }));
    return {for (final p in results) if (p != null) p.id: p};
  }
}