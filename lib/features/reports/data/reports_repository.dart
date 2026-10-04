import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../../core/constants/roles.dart';
import '../../../core/models/report_section.dart';
import '../../admin/models/app_user.dart';
import '../../admin/models/follow_up_settings.dart';
import '../../assessment/models/funding_candidate.dart';
import '../../demolition/models/demolition_order.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/case.dart';
import '../../intake/models/parcel.dart';
import '../../parcels/data/parcels_repository.dart';
import '../../review/models/decision.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(firestore: ref.watch(firestoreProvider));
});

/// The filters a report can take (§9's "typical filters"). One shared bag
/// of optional values — each report simply reads the ones that apply to it
/// and ignores the rest, and the filter dialog only offers the applicable
/// ones.
class ReportFilters {
  ReportFilters({
    this.zone,
    this.status,
    this.from,
    this.to,
    this.team,
    this.parcelId,
    this.month,
    this.fundingStatus,
    this.windowDays,
  });

  String? zone;
  ParcelStatus? status;
  DateTime? from;
  DateTime? to;
  AppRole? team;
  String? parcelId;
  DateTime? month;
  FundingCandidateStatus? fundingStatus;
  int? windowDays;

  ReportFilters copy() => ReportFilters(
        zone: zone,
        status: status,
        from: from,
        to: to,
        team: team,
        parcelId: parcelId,
        month: month,
        fundingStatus: fundingStatus,
        windowDays: windowDays,
      );

  bool get isEmpty =>
      zone == null &&
      status == null &&
      from == null &&
      to == null &&
      team == null &&
      parcelId == null &&
      month == null &&
      fundingStatus == null &&
      windowDays == null;

  static String _d(DateTime? d) => d == null ? '…' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// A one-line description of the active filters — shown on the report
  /// card and printed under the title of the exported file.
  String describe() {
    final parts = <String>[
      if (zone != null) 'المنطقة: $zone',
      if (status != null) 'الحالة: ${status!.label}',
      if (from != null || to != null) 'الفترة: ${_d(from)} ← ${_d(to)}',
      if (team != null) 'الفريق: ${team!.label}',
      if (parcelId != null) 'العقار: $parcelId',
      if (month != null) 'الشهر: ${month!.year}-${month!.month.toString().padLeft(2, '0')}',
      if (fundingStatus != null) 'حالة التمويل: ${fundingStatus!.label}',
      if (windowDays != null) 'النافذة: $windowDays يومًا',
    ];
    return parts.join('  ·  ');
  }
}

/// Data aggregation for the seven management reports (§9, R1–R7). Each
/// `buildRN` returns a [ReportResult] — plain tables that both export
/// paths (PDF and Excel) consume identically, so a report's data logic is
/// written once and never knows which format will render it.
///
/// Every query here is a single-field `orderBy` (or none) with filtering
/// done in Dart, so none of the reports needs a composite Firestore index.
class ReportsRepository {
  ReportsRepository({required this.firestore});
  final FirebaseFirestore firestore;

  String _fmt(DateTime? d) => d == null ? '—' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime? d) =>
      d == null ? '—' : '${_fmt(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Inclusive on both ends, by calendar day. With no bounds set, everything
  /// (even an undated record) is in range.
  bool _inRange(DateTime? d, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    if (d == null) return false;
    if (from != null && d.isBefore(DateTime(from.year, from.month, from.day))) return false;
    if (to != null && !d.isBefore(DateTime(to.year, to.month, to.day + 1))) return false;
    return true;
  }

  String _parcelText(Parcel? p, String fallbackId) {
    if (p == null) return fallbackId;
    return p.address.isEmpty ? '${p.parcelNo} — ${p.cadastralZone}' : '${p.parcelNo} — ${p.cadastralZone} — ${p.address}';
  }

  /// Every parcel, most recently updated first. At this POC's scale
  /// (NFR-5: low thousands) one bounded read is the pragmatic choice.
  Future<List<Parcel>> listParcels({int limit = 2000}) async {
    final snap = await firestore.collection(FirestorePaths.parcels).orderBy('updatedAt', descending: true).limit(limit).get();
    return snap.docs.map(Parcel.fromFirestore).toList();
  }

  /// The user directory as uid → profile. Never throws: if it can't be
  /// read, reports still work — people just show as unregistered.
  Future<Map<String, AppUserProfile>> _loadUsers() async {
    try {
      final snap = await firestore.collection(FirestorePaths.users).get();
      return {for (final d in snap.docs) d.id: AppUserProfile.fromFirestore(d)};
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // R1 — Parcel status summary: current status AND last action per parcel.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR1(ReportFilters f) async {
    final parcels = (await listParcels()).where((p) {
      return (f.zone == null || p.cadastralZone == f.zone) && (f.status == null || p.status == f.status);
    }).toList();

    final decisionsSnap = await firestore.collection(FirestorePaths.decisions).orderBy('createdAt', descending: true).limit(2000).get();
    final lastByParcel = <String, Decision>{};
    for (final doc in decisionsSnap.docs) {
      final d = Decision.fromFirestore(doc);
      lastByParcel.putIfAbsent(d.parcelId, () => d); // newest first, so the first seen is the latest
    }

    return ReportResult.single(
      headers: const ['رقم العقار', 'المنطقة', 'العنوان', 'الحالة الحالية', 'آخر إجراء', 'تاريخ آخر إجراء', 'آخر تحديث'],
      rows: [
        for (final p in parcels)
          [
            p.parcelNo,
            p.cadastralZone,
            p.address.isEmpty ? '—' : p.address,
            p.status.label,
            lastByParcel[p.id]?.action.noticeTitle ?? '—',
            _fmt(lastByParcel[p.id]?.createdAt),
            _fmt(p.updatedAt),
          ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // R2 — Parcels by stage: counts by status AND by action type.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR2(ReportFilters f) async {
    final parcels = await listParcels();
    final byId = {for (final p in parcels) p.id: p};
    final zoneOk = (Parcel? p) => f.zone == null || p?.cadastralZone == f.zone;

    final inScope = parcels.where((p) => zoneOk(p) && _inRange(p.updatedAt, f.from, f.to)).toList();
    final statusRows = [
      for (final s in ParcelStatus.values) [s.label, inScope.where((p) => p.status == s).length.toString()],
      ['الإجمالي', inScope.length.toString()],
    ];

    final decisionsSnap = await firestore.collection(FirestorePaths.decisions).orderBy('createdAt', descending: true).limit(2000).get();
    final decisions = decisionsSnap.docs
        .map(Decision.fromFirestore)
        .where((d) => zoneOk(byId[d.parcelId]) && _inRange(d.createdAt, f.from, f.to))
        .toList();
    final actionRows = [
      for (final a in DecisionAction.values) [a.noticeTitle, decisions.where((d) => d.action == a).length.toString()],
      ['الإجمالي', decisions.length.toString()],
    ];

    return ReportResult([
      ReportSection(title: 'العقارات حسب الحالة', headers: const ['الحالة', 'عدد العقارات'], rows: statusRows),
      ReportSection(title: 'الإجراءات الصادرة حسب النوع', headers: const ['نوع الإجراء', 'العدد'], rows: actionRows),
    ]);
  }

  // ---------------------------------------------------------------------------
  // R3 — Overdue & upcoming actions: the dashboard's dated work, as a report.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR3(ReportFilters f) async {
    final settings = await FollowUpSettings.load(firestore);
    final window = f.windowDays ?? settings.dueSoonWindowDays;
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: window));
    final byId = {for (final p in await listParcels()) p.id: p};

    final items = <_DueItem>[];

    // Decisions still waiting on their follow-up (evacuation compliance
    // check / warning site visit). Filtered in Dart — see the Firestore
    // "missing field" note on Decision.resolved.
    final decisionsSnap = await firestore.collection(FirestorePaths.decisions).orderBy('executionDate').limit(500).get();
    for (final doc in decisionsSnap.docs) {
      final d = Decision.fromFirestore(doc);
      if (d.resolved) continue;
      items.add(_DueItem(
        parcelId: d.parcelId,
        due: d.executionDate,
        label: d.action == DecisionAction.evacuation ? 'إخلاء — التحقق من الامتثال' : 'زيارة ميدانية — ${d.action.noticeTitle}',
      ));
    }

    final demolitionSnap = await firestore.collection(FirestorePaths.demolitionOrders).orderBy('executionDate').limit(500).get();
    for (final doc in demolitionSnap.docs) {
      final o = DemolitionOrder.fromFirestore(doc);
      if (o.executed) continue;
      items.add(_DueItem(parcelId: o.parcelId, due: o.executionDate, label: 'تنفيذ أمر الهدم'));
    }

    final rows = items
        .where((i) => i.due.isBefore(cutoff) && (f.zone == null || byId[i.parcelId]?.cadastralZone == f.zone))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    return ReportResult.single(
      headers: const ['العقار', 'المنطقة', 'الإجراء', 'الفريق المسؤول', 'تاريخ الاستحقاق', 'الحالة'],
      rows: [
        for (final i in rows)
          [
            _parcelText(byId[i.parcelId], i.parcelId),
            byId[i.parcelId]?.cadastralZone ?? '—',
            i.label,
            AppRole.police.label,
            _fmt(i.due),
            i.due.isBefore(now) ? 'متأخر' : 'مستحق قريبًا',
          ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // R4 — Per-team workload & activity over a period.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR4(ReportFilters f) async {
    final users = await _loadUsers();
    final events = <_Activity>[];

    Future<void> collect(String collection, String dateField, String uidField, _Kind kind, {bool Function(Map<String, dynamic>)? where}) async {
      final snap = await firestore.collection(collection).orderBy(dateField, descending: true).limit(2000).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (where != null && !where(data)) continue;
        final at = (data[dateField] as Timestamp?)?.toDate();
        if (!_inRange(at, f.from, f.to)) continue;
        events.add(_Activity((data[uidField] as String?) ?? '', kind));
      }
    }

    await Future.wait([
      collect(FirestorePaths.complaints, 'createdAt', 'createdByUid', _Kind.complaints),
      collect(FirestorePaths.triage, 'triagedAt', 'triagedByUid', _Kind.triage, where: (d) => d['status'] == 'submitted'),
      collect(FirestorePaths.reports, 'createdAt', 'createdByUid', _Kind.reports),
      collect(FirestorePaths.reviews, 'reviewedAt', 'reviewerUid', _Kind.reviews, where: (d) => d['status'] == 'submitted'),
      collect(FirestorePaths.decisions, 'createdAt', 'createdByUid', _Kind.decisions),
      collect(FirestorePaths.siteVisits, 'visitedAt', 'inspectorUid', _Kind.siteVisits),
    ]);

    final perUid = <String, Map<_Kind, int>>{};
    for (final e in events) {
      final counts = perUid.putIfAbsent(e.uid, () => {for (final k in _Kind.values) k: 0});
      counts[e.kind] = counts[e.kind]! + 1;
    }
    // Everyone in the directory appears, even with zero activity.
    for (final uid in users.keys) {
      perUid.putIfAbsent(uid, () => {for (final k in _Kind.values) k: 0});
    }

    AppRole? roleOf(String uid) => users[uid]?.role;
    bool teamOk(String uid) => f.team == null || roleOf(uid) == f.team;

    List<String> countCells(Map<_Kind, int> c) => [
          for (final k in _Kind.values) c[k].toString(),
          c.values.fold<int>(0, (a, b) => a + b).toString(),
        ];
    final headers = [for (final k in _Kind.values) k.label, 'الإجمالي'];

    // --- by team
    final byTeam = <String, Map<_Kind, int>>{};
    for (final entry in perUid.entries) {
      if (!teamOk(entry.key)) continue;
      final team = roleOf(entry.key)?.label ?? 'غير محدد';
      final acc = byTeam.putIfAbsent(team, () => {for (final k in _Kind.values) k: 0});
      for (final k in _Kind.values) {
        acc[k] = acc[k]! + entry.value[k]!;
      }
    }
    final teamOrder = [...AppRole.values.map((r) => r.label), 'غير محدد'];
    final teamRows = [
      for (final t in teamOrder)
        if (byTeam.containsKey(t)) [t, ...countCells(byTeam[t]!)],
    ];

    // --- by user
    String nameOf(String uid) {
      final u = users[uid];
      if (u != null) return u.displayName.isEmpty ? u.email : u.displayName;
      if (uid.isEmpty) return 'غير مسجَّل';
      return 'مستخدم غير مسجَّل في الدليل (${uid.length > 6 ? uid.substring(0, 6) : uid}…)';
    }

    final userEntries = perUid.entries.where((e) => teamOk(e.key)).toList()
      ..sort((a, b) {
        final ta = a.value.values.fold<int>(0, (x, y) => x + y);
        final tb = b.value.values.fold<int>(0, (x, y) => x + y);
        return tb.compareTo(ta);
      });
    final userRows = [
      for (final e in userEntries) [nameOf(e.key), roleOf(e.key)?.label ?? 'غير محدد', ...countCells(e.value)],
    ];

    return ReportResult([
      ReportSection(title: 'حسب الفريق', headers: ['الفريق', ...headers], rows: teamRows),
      ReportSection(title: 'حسب المستخدم', headers: ['المستخدم', 'الفريق', ...headers], rows: userRows),
    ]);
  }

  // ---------------------------------------------------------------------------
  // R5 — One-page monthly council roll-up.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR5(ReportFilters f) async {
    final month = f.month ?? DateTime.now();
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    bool inMonth(DateTime? d) => d != null && !d.isBefore(start) && d.isBefore(end);

    final casesSnap = await firestore.collection(FirestorePaths.cases).orderBy('openedAt', descending: true).limit(2000).get();
    final cases = casesSnap.docs.map(Case.fromFirestore).toList();
    final newCases = cases.where((c) => inMonth(c.openedAt)).length;
    final closedThisMonth = cases.where((c) => inMonth(c.closedAt)).length;
    final openNow = cases.where((c) => c.status == CaseStatus.open).length;

    final decisionsSnap = await firestore.collection(FirestorePaths.decisions).orderBy('createdAt', descending: true).limit(2000).get();
    final decisions = decisionsSnap.docs.map(Decision.fromFirestore).where((d) => inMonth(d.createdAt)).toList();
    int countOf(DecisionAction a) => decisions.where((d) => d.action == a).length;

    final demolitionSnap = await firestore.collection(FirestorePaths.demolitionOrders).limit(2000).get();
    final demolitionsThisMonth =
        demolitionSnap.docs.where((doc) => inMonth((doc.data()['actualExecutionDate'] as Timestamp?)?.toDate())).length;

    return ReportResult.single(
      headers: const ['المؤشر', 'القيمة'],
      rows: [
        ['الشهر', '${month.year}-${month.month.toString().padLeft(2, '0')}'],
        ['حالات جديدة', newCases.toString()],
        ['أوامر إخلاء صادرة', countOf(DecisionAction.evacuation).toString()],
        ['إنذارات تدعيم صادرة', countOf(DecisionAction.shoringWarning).toString()],
        ['تأكيدات تدعيم صادرة', countOf(DecisionAction.shoringConfirm).toString()],
        ['إنذارات ترميم صادرة', countOf(DecisionAction.restorationWarning).toString()],
        ['عمليات هدم منفَّذة', demolitionsThisMonth.toString()],
        ['حالات أُغلقت خلال الشهر', closedThisMonth.toString()],
        ['حالات مفتوحة حاليًا (إجمالي)', openNow.toString()],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // R6 — Full history of one parcel: timeline with who did what.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR6(ReportFilters f) async {
    final parcelId = f.parcelId;
    if (parcelId == null) throw StateError('اختر عقارًا لإصدار السجلّ الكامل.');

    final parcelsRepo = ParcelsRepository(firestore: firestore);
    final parcel = await parcelsRepo.getParcel(parcelId);
    if (parcel == null) throw StateError('العقار المحدد غير موجود.');
    final timeline = await parcelsRepo.getTimeline(parcelId);
    final users = await _loadUsers();

    String actor(String? uid) {
      if (uid == null || uid.isEmpty) return '—';
      final u = users[uid];
      if (u == null) return 'غير مسجَّل في الدليل';
      return u.displayName.isEmpty ? u.email : u.displayName;
    }

    return ReportResult([
      ReportSection(
        title: 'بيانات العقار',
        headers: const ['الحقل', 'القيمة'],
        rows: [
          ['رقم العقار', parcel.parcelNo],
          ['المنطقة العقارية', parcel.cadastralZone],
          ['العنوان', parcel.address.isEmpty ? '—' : parcel.address],
          ['الحالة الحالية', parcel.status.label],
          ['تاريخ التسجيل', _fmt(parcel.createdAt)],
          ['آخر تحديث', _fmt(parcel.updatedAt)],
        ],
      ),
      ReportSection(
        title: 'الخط الزمني الكامل',
        note: 'يُعرض المنفِّذ حيثما سُجِّل في السجلّ الأصلي (الشكاوى، القرارات، الزيارات الميدانية). '
            'القيم قبل/بعد كل تعديل غير متوفرة: تتطلب مجموعة سجلّ تدقيق (AuditLog) غير مُطبَّقة في هذه النسخة.',
        headers: const ['التاريخ', 'الحدث', 'التفاصيل', 'المنفِّذ'],
        rows: [
          for (final e in timeline) [_fmtDateTime(e.timestamp), e.title, e.subtitle, actor(e.actorUid)],
        ],
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // R7 — Restoration funding candidates.
  // ---------------------------------------------------------------------------
  Future<ReportResult> buildR7(ReportFilters f) async {
    final snap = await firestore.collection(FirestorePaths.fundingCandidates).orderBy('proposedDate', descending: true).limit(1000).get();
    final candidates = snap.docs.map(FundingCandidate.fromFirestore).where((c) => f.fundingStatus == null || c.status == f.fundingStatus).toList();
    final byId = {for (final p in await listParcels()) p.id: p};
    final filtered = candidates.where((c) => f.zone == null || byId[c.parcelId]?.cadastralZone == f.zone).toList();

    return ReportResult.single(
      headers: const ['العقار', 'المنطقة', 'الحالة', 'جهة التمويل', 'تاريخ الاقتراح'],
      rows: [
        for (final c in filtered)
          [
            _parcelText(byId[c.parcelId], c.parcelId),
            byId[c.parcelId]?.cadastralZone ?? '—',
            c.status.label,
            c.funder ?? '—',
            _fmt(c.proposedDate),
          ],
      ],
    );
  }
}

class _DueItem {
  _DueItem({required this.parcelId, required this.due, required this.label});
  final String parcelId;
  final DateTime due;
  final String label;
}

enum _Kind {
  complaints('شكاوى مسجّلة'),
  triage('عمليات فرز'),
  reports('تقارير مسجّلة'),
  reviews('مراجعات'),
  decisions('قرارات صادرة'),
  siteVisits('زيارات ميدانية');

  const _Kind(this.label);
  final String label;
}

class _Activity {
  _Activity(this.uid, this.kind);
  final String uid;
  final _Kind kind;
}
