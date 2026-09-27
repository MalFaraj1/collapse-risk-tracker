import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../assessment/models/assessment.dart';
import '../../demolition/models/demolition_order.dart';
import '../../evacuation/models/evacuation_execution.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/case.dart';
import '../../intake/models/complaint.dart';
import '../../intake/models/parcel.dart';
import '../../review/models/decision.dart';
import '../../review/models/notice.dart';
import '../../sitevisits/models/site_visit.dart';

final parcelsRepositoryProvider = Provider<ParcelsRepository>((ref) {
  return ParcelsRepository(firestore: ref.watch(firestoreProvider));
});

/// Everything the Parcel Registry (list + detail) needs to talk to
/// Firestore.
///
/// IMPORTANT — this replaces a previous version of this file built
/// against a separate, richer Parcel model (neighborhoods, buildings,
/// per-building condition) from earlier, paused work. That model was
/// never written to by any real workflow screen — Intake, Triage,
/// Review, Evacuation, Site Visit, Assessment, and Demolition all read
/// and write the SAME simpler Parcel model this file now uses.
class ParcelsRepository {
  ParcelsRepository({required this.firestore});
  final FirebaseFirestore firestore;

  /// Live list of every parcel, most recently updated first. A real
  /// production deployment would paginate this; for this POC's expected
  /// scale (§10, NFR-5: "low thousands of parcels") one bounded live
  /// query is the pragmatic choice.
  Stream<List<Parcel>> watchAllParcels({int limit = 200}) {
    return firestore
        .collection(FirestorePaths.parcels)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Parcel.fromFirestore).toList());
  }

  Future<Parcel?> getParcel(String parcelId) async {
    final doc = await firestore.collection(FirestorePaths.parcels).doc(parcelId).get();
    return doc.exists ? Parcel.fromFirestore(doc) : null;
  }

  /// FR-PAR-1: creates a parcel directly from the registry, independent
  /// of a complaint. Uses the exact same deterministic-ID technique as
  /// Intake, so a parcel created here and one later found by Intake for
  /// the same (parcel_no, cadastral_zone) are guaranteed to be the same
  /// document — never two competing records for one real building.
  Future<Parcel> createParcel({
    required String parcelNo,
    required String cadastralZone,
    required String address,
    int buildingCount = 1,
  }) async {
    final id = Parcel.buildId(parcelNo, cadastralZone);
    final ref = firestore.collection(FirestorePaths.parcels).doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      throw StateError('عقار بهذا الرقم والمنطقة العقارية مسجَّل بالفعل.');
    }
    final parcel = Parcel(
      id: id,
      parcelNo: parcelNo.trim(),
      cadastralZone: cadastralZone.trim().toUpperCase(),
      address: address.trim(),
      buildingCount: buildingCount,
      status: ParcelStatus.newCase,
    );
    await ref.set(parcel.toFirestoreCreate());
    return parcel;
  }

  // --- Parcel Detail: the full timeline (FR-PAR-3) ----------------------------
  //
  // Every entity Dashboard now surfaces across its six work queues is
  // represented here too: cases, complaints, decisions, and notices (the
  // original four), plus evacuation executions, site visits, assessments,
  // and demolition orders — closing the exact gap this file used to
  // document as "not included yet."

  Future<List<Case>> _getCases(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.cases)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('openedAt', descending: true)
        .get();
    return snap.docs.map(Case.fromFirestore).toList();
  }

  Future<List<Complaint>> _getComplaints(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.complaints)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('date', descending: true)
        .get();
    return snap.docs.map(Complaint.fromFirestore).toList();
  }

  Future<List<Decision>> _getDecisions(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.decisions)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(Decision.fromFirestore).toList();
  }

  Future<List<Notice>> _getNotices(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.notices)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(Notice.fromFirestore).toList();
  }

  Future<List<EvacuationExecution>> _getEvacuations(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.evacuationExecutions)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(EvacuationExecution.fromFirestore).toList();
  }

  Future<List<SiteVisit>> _getSiteVisits(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.siteVisits)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('visitedAt', descending: true)
        .get();
    return snap.docs.map(SiteVisit.fromFirestore).toList();
  }

  Future<List<Assessment>> _getAssessments(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.assessments)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(Assessment.fromFirestore).toList();
  }

  Future<List<DemolitionOrder>> _getDemolitionOrders(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.demolitionOrders)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(DemolitionOrder.fromFirestore).toList();
  }

  /// Fetches all eight sources in parallel and merges them into one
  /// chronologically sorted list, newest first.
  ///
  /// NOTE: each of the eight queries above needs its own Firestore
  /// composite index (equality on `parcelId` + orderBy a date field) —
  /// the same first-run index-link behavior as every other compound
  /// query in this project. Opening a parcel with a long history for the
  /// first time may surface several of these links at once; each is a
  /// one-click fix, same as always.
  Future<List<ParcelTimelineEntry>> getTimeline(String parcelId) async {
    final results = await Future.wait([
      _getCases(parcelId),
      _getComplaints(parcelId),
      _getDecisions(parcelId),
      _getNotices(parcelId),
      _getEvacuations(parcelId),
      _getSiteVisits(parcelId),
      _getAssessments(parcelId),
      _getDemolitionOrders(parcelId),
    ]);
    final cases = results[0] as List<Case>;
    final complaints = results[1] as List<Complaint>;
    final decisions = results[2] as List<Decision>;
    final notices = results[3] as List<Notice>;
    final evacuations = results[4] as List<EvacuationExecution>;
    final siteVisits = results[5] as List<SiteVisit>;
    final assessments = results[6] as List<Assessment>;
    final demolitionOrders = results[7] as List<DemolitionOrder>;

    final entries = <ParcelTimelineEntry>[
      for (final c in cases)
        ParcelTimelineEntry(
          timestamp: c.openedAt,
          icon: Icons.folder_open,
          title: c.status == CaseStatus.closed ? 'أُغلقت الحالة' : 'فُتحت حالة جديدة',
          subtitle: c.id,
        ),
      for (final c in complaints)
        ParcelTimelineEntry(
          timestamp: c.date,
          icon: Icons.report_gmailerrorred_outlined,
          title: 'شكوى — ${c.channel.label}',
          subtitle: c.narrative.isEmpty ? '(لا يوجد وصف)' : c.narrative,
          complainantContact: c.complainantContact,
          mediaUrls: c.photoUrls,
        ),
      for (final d in decisions)
        ParcelTimelineEntry(
          timestamp: d.createdAt ?? d.executionDate,
          icon: Icons.gavel_outlined,
          title: 'قرار — ${d.action.noticeTitle}',
          subtitle: 'تاريخ التنفيذ: ${_fmt(d.executionDate)}',
        ),
      for (final n in notices)
        ParcelTimelineEntry(
          timestamp: n.createdAt ?? DateTime.now(),
          icon: Icons.description_outlined,
          title: 'إشعار صادر',
          subtitle: n.source.firestoreValue,
          noticeId: n.id,
        ),
      for (final e in evacuations) ..._evacuationEntries(e),
      for (final v in siteVisits)
        ParcelTimelineEntry(
          timestamp: v.visitedAt ?? DateTime.now(),
          icon: Icons.domain_verification_outlined,
          title: 'زيارة ميدانية — ${v.outcome.label}',
          subtitle: (v.notes == null || v.notes!.isEmpty) ? v.outcome.subtitle : v.notes!,
          mediaUrls: v.mediaUrls,
        ),
      for (final a in assessments)
        ParcelTimelineEntry(
          timestamp: a.createdAt ?? DateTime.now(),
          icon: Icons.assignment_outlined,
          title: 'تقييم خارجي',
          subtitle: a.opinion != null ? 'الرأي: ${a.opinion!.label}' : 'بانتظار رأي الجهة الخارجية (${a.triggerReason.label})',
        ),
      for (final o in demolitionOrders)
        ParcelTimelineEntry(
          timestamp: o.postedDate,
          icon: Icons.domain_disabled_outlined,
          title: 'أمر هدم',
          subtitle: o.executed
              ? 'تم التنفيذ بتاريخ ${o.actualExecutionDate != null ? _fmt(o.actualExecutionDate!) : _fmt(o.executionDate)}'
              : 'مجدول لتاريخ ${_fmt(o.executionDate)}',
        ),
    ];
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  /// One evacuation can produce up to two meaningful timeline moments:
  /// when the order was posted (starting BR-7's 48h clock), and — once it
  /// happened — the compliance outcome (voluntary or forced). Kept as two
  /// separate entries rather than one, since they can be days apart and
  /// each is independently worth seeing on the timeline.
  List<ParcelTimelineEntry> _evacuationEntries(EvacuationExecution e) {
    final entries = <ParcelTimelineEntry>[];
    if (e.postedDate != null) {
      entries.add(ParcelTimelineEntry(
        timestamp: e.postedDate!,
        icon: Icons.exit_to_app_outlined,
        title: 'نُشر أمر الإخلاء على المبنى',
        subtitle: (e.familyCount != null && e.individualCount != null)
            ? '${e.familyCount} عائلات — ${e.individualCount} أفراد'
            : 'بدأت مهلة الامتثال 48 ساعة',
      ));
    }
    if (e.enforced && e.enforcedDate != null) {
      entries.add(ParcelTimelineEntry(
        timestamp: e.enforcedDate!,
        icon: Icons.gavel,
        title: 'تنفيذ الإخلاء قسريًا',
        subtitle: 'بقي شاغلون بعد انتهاء المهلة القانونية',
      ));
    } else if (e.complianceVisitDate != null && e.complianceOutcome != null) {
      entries.add(ParcelTimelineEntry(
        timestamp: e.complianceVisitDate!,
        icon: Icons.fact_check_outlined,
        title: 'نتيجة التحقق من الإخلاء',
        subtitle: e.complianceOutcome!.label,
      ));
    }
    return entries;
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// One entry in a parcel's merged timeline (FR-PAR-3) — a plain, generic
/// shape rather than a union type per source collection, since the screen
/// only ever needs to render "icon + title + subtitle + when", regardless
/// of which collection an entry actually came from.
///
/// [complainantContact] is only ever populated for complaint entries.
/// [mediaUrls] is populated for both complaint entries (Intake's photo/
/// video evidence) and site visit entries (an inspector's own photos) —
/// [MediaThumbnail] renders either correctly regardless of source.
class ParcelTimelineEntry {
  const ParcelTimelineEntry({
    required this.timestamp,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.noticeId,
    this.complainantContact,
    this.mediaUrls = const [],
  });

  final DateTime timestamp;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Only set for notice entries — lets the timeline row link straight to
  /// Notice Preview.
  final String? noticeId;

  /// Only set for complaint entries (Complaint.complainantContact).
  final String? complainantContact;

  /// Set for complaint entries (Complaint.photoUrls) and site visit
  /// entries (SiteVisit.mediaUrls) — despite the differing field names on
  /// each source model, both hold photos AND videos; see MediaThumbnail,
  /// which auto-detects which is which per URL.
  final List<String> mediaUrls;
}