import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../assessment/models/assessment.dart';
import '../../demolition/models/demolition_order.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/case.dart';
import '../../intake/models/complaint.dart';
import '../../intake/models/parcel.dart';
import '../../review/models/decision.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(firestore: ref.watch(firestoreProvider));
});

class DashboardRepository {
  DashboardRepository({required this.firestore});
  final FirebaseFirestore firestore;

  /// Live query for every complaint that hasn't been triaged yet, oldest
  /// first — the actual "due action" this dashboard can surface right now.
  ///
  /// IMPORTANT: this deliberately does NOT filter with a Firestore-side
  /// `.where('triagedAt', isNull: true)`. That filter only matches
  /// documents where the field EXISTS and equals null — it silently
  /// excludes any document where the field is simply absent, which is
  /// exactly what real complaints created before this field existed look
  /// like. [Complaint.fromFirestore] already treats "missing" and
  /// "explicitly null" identically (both parse to a null [DateTime]), so
  /// filtering here, in Dart, with the same [Complaint.needsTriage] logic
  /// the rest of the app already relies on, is correct for both old and
  /// new documents — the Firestore-side filter was not. This also removes
  /// the need for the composite index that filter would have required.
  Stream<List<Complaint>> watchComplaintsAwaitingTriage() {
    return firestore
        .collection(FirestorePaths.complaints)
        .orderBy('date', descending: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map(Complaint.fromFirestore).where((c) => c.needsTriage).toList());
  }

  /// Live query for every open case that Triage has routed somewhere
  /// (dispatched an engineer, or referred to committee) but which has no
  /// Decision yet — the work Review & Decision is waiting on.
  ///
  /// Filters entirely in Dart, not with Firestore-side `.where()`
  /// equality/orderBy combinations — see [watchComplaintsAwaitingTriage]
  /// for why: older documents predating a denormalized flag would be
  /// silently excluded by a Firestore-side equality filter on it.
  Stream<List<Case>> watchCasesAwaitingReview() {
    return firestore
        .collection(FirestorePaths.cases)
        .orderBy('openedAt', descending: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map(Case.fromFirestore)
            .where((c) => c.status == CaseStatus.open && c.awaitingReview)
            .toList());
  }

  /// Live query for every EVACUATION decision whose compliance check
  /// hasn't happened yet (`resolved == false`) — the work Evacuation
  /// Execution is waiting on. Before this existed, an evacuation decision
  /// had no discoverable path forward at all: Review & Decision only
  /// navigates to Notice Preview after issuing a decision, never to the
  /// screen that actually executes it.
  Stream<List<Decision>> watchEvacuationsInProgress() {
    return firestore
        .collection(FirestorePaths.decisions)
        .orderBy('executionDate', descending: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map(Decision.fromFirestore)
            .where((d) => d.action == DecisionAction.evacuation && !d.resolved)
            .toList());
  }

  /// Live query for every warning-type decision (Shoring Warning,
  /// Confirmatory Shoring, Restoration Warning) that has never had a site
  /// visit recorded yet — the work Site Visit is waiting on. This
  /// replaces the old count-only `countAwaitingSiteVisit`: the same
  /// underlying data, now returned as a real browsable list instead of
  /// just a number with nothing to click into.
  Stream<List<Decision>> watchSiteVisitsNeeded() {
    return firestore
        .collection(FirestorePaths.decisions)
        .orderBy('executionDate', descending: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map(Decision.fromFirestore)
            .where((d) =>
                !d.resolved &&
                (d.action == DecisionAction.shoringWarning ||
                    d.action == DecisionAction.shoringConfirm ||
                    d.action == DecisionAction.restorationWarning))
            .toList());
  }

  /// Live query for every Assessment still waiting on the external firm's
  /// opinion — created automatically by Evacuation or Site Visit (BR-8)
  /// but, until now, with nothing anywhere pointing Engineering at it.
  Stream<List<Assessment>> watchAssessmentsPending() {
    return firestore
        .collection(FirestorePaths.assessments)
        .orderBy('createdAt', descending: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map(Assessment.fromFirestore).where((a) => a.opinion == null).toList());
  }

  /// Live query for every demolition order not yet executed — created
  /// automatically by Assessment's DEMOLISH opinion (BR-9) but, until
  /// now, with no queue anywhere for Police to find it.
  Stream<List<DemolitionOrder>> watchDemolitionsInProgress() {
    return firestore
        .collection(FirestorePaths.demolitionOrders)
        .orderBy('executionDate', descending: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map(DemolitionOrder.fromFirestore).where((o) => !o.executed).toList());
  }

  /// Count of cases closed since the start of the current calendar month.
  /// Purely informational — nothing to click into, so this stays a plain
  /// count rather than a queue.
  ///
  /// NOTE: needs a Firestore composite index (equality on `status` +
  /// range on `closedAt`).
  Future<int> countClosedThisMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final snap = await firestore
        .collection(FirestorePaths.cases)
        .where('status', isEqualTo: 'CLOSED')
        .where('closedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// One parcel, by ID — used to show a real address next to each queue
  /// row instead of just the raw parcel ID. A plain one-off read rather
  /// than a stream, since a dashboard row's parcel rarely changes while
  /// the row itself is on screen.
  Future<Parcel?> getParcelById(String parcelId) async {
    final doc = await firestore.collection(FirestorePaths.parcels).doc(parcelId).get();
    return doc.exists ? Parcel.fromFirestore(doc) : null;
  }
}

/// Live stream of complaints awaiting triage.
final complaintsAwaitingTriageProvider = StreamProvider<List<Complaint>>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchComplaintsAwaitingTriage();
});

/// Live stream of triaged cases with no Decision yet.
final casesAwaitingReviewProvider = StreamProvider<List<Case>>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchCasesAwaitingReview();
});

/// Live stream of evacuation decisions still awaiting their compliance
/// check.
final evacuationsInProgressProvider = StreamProvider<List<Decision>>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchEvacuationsInProgress();
});

/// Live stream of warning-type decisions with no site visit yet. Also the
/// source of the "بانتظار زيارة ميدانية" stat card's count — no separate
/// aggregate query needed, the same reasoning as reading `.length` off
/// the triage queue for its own stat card.
final siteVisitsNeededProvider = StreamProvider<List<Decision>>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchSiteVisitsNeeded();
});

/// Live stream of assessments awaiting the external firm's opinion.
final assessmentsPendingProvider = StreamProvider<List<Assessment>>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchAssessmentsPending();
});

/// Live stream of demolition orders not yet executed.
final demolitionsInProgressProvider = StreamProvider<List<DemolitionOrder>>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchDemolitionsInProgress();
});

/// One parcel by ID, cached per ID by Riverpod's family mechanism.
final parcelByIdProvider = FutureProvider.family<Parcel?, String>((ref, parcelId) {
  return ref.watch(dashboardRepositoryProvider).getParcelById(parcelId);
});

/// `.autoDispose` so a stale failure (e.g. a missing Firestore index on
/// first run) doesn't persist forever — re-entering Dashboard retries
/// fresh. See the in-app error-detail dialog for why this matters.
final closedThisMonthCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(dashboardRepositoryProvider).countClosedThisMonth();
});