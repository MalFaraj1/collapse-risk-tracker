import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../demolition/models/demolition_order.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/case.dart';
import '../../review/models/decision.dart';
import '../models/assessment.dart';
import '../models/funding_candidate.dart';
import '../models/restoration_study.dart';

final assessmentRepositoryProvider = Provider<AssessmentRepository>((ref) {
  return AssessmentRepository(firestore: ref.watch(firestoreProvider));
});

/// Everything the Assessment screen needs to talk to Firestore.
class AssessmentRepository {
  AssessmentRepository({required this.firestore});

  final FirebaseFirestore firestore;

  Future<Decision?> getDecision(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.decisions).doc(decisionId).get();
    return doc.exists ? Decision.fromFirestore(doc) : null;
  }

  Future<Case?> getCase(String caseId) async {
    final doc = await firestore.collection(FirestorePaths.cases).doc(caseId).get();
    return doc.exists ? Case.fromFirestore(doc) : null;
  }

  /// Gets this decision's assessment record, or null if BR-8's trigger
  /// hasn't fired yet (see EvacuationRepository / SiteVisitRepository).
  /// Deliberately does NOT create one here — an assessment should only
  /// ever come into existence via the automatic trigger, never by simply
  /// opening this screen.
  Future<Assessment?> getAssessment(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.assessments).doc(decisionId).get();
    return doc.exists ? Assessment.fromFirestore(doc) : null;
  }

  Future<RestorationStudy?> getRestorationStudy(String assessmentId) async {
    final doc = await firestore.collection(FirestorePaths.restorationStudies).doc(assessmentId).get();
    return doc.exists ? RestorationStudy.fromFirestore(doc) : null;
  }

  /// Municipality-wide funding candidates list (§7.6a) — deliberately not
  /// scoped to one parcel, this is a cross-case view so staff can see the
  /// whole slate of buildings ready to propose to third-party funders.
  Future<List<FundingCandidate>> getMunicipalFundingCandidates({int limit = 20}) async {
    final snap = await firestore
        .collection(FirestorePaths.fundingCandidates)
        .orderBy('proposedDate', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(FundingCandidate.fromFirestore).toList();
  }

  /// FR-ASM-2: records the external firm's order/opinion. An opinion of
  /// DEMOLISH automatically creates the initial DemolitionOrder record —
  /// the same automatic-trigger pattern already used for this screen's
  /// own creation from Evacuation/Site Visit.
  Future<void> saveExternalAssessment(
    Assessment assessment, {
    DateTime? orderSentDate,
    DateTime? opinionReceivedDate,
    ExternalOpinion? opinion,
  }) async {
    await firestore.collection(FirestorePaths.assessments).doc(assessment.id).update({
      if (orderSentDate != null) 'orderSentDate': Timestamp.fromDate(orderSentDate),
      if (opinionReceivedDate != null) 'opinionReceivedDate': Timestamp.fromDate(opinionReceivedDate),
      if (opinion != null) 'opinion': opinion.firestoreValue,
    });

    if (opinion == ExternalOpinion.demolish) {
      await _ensureDemolitionTriggered(assessment);
    } else if (opinion == ExternalOpinion.restore) {
      // Parcel-level status transition (Appendix B) — DEMOLISH's own
      // transition happens inside _ensureDemolitionTriggered, alongside
      // the DemolitionOrder it creates.
      await firestore.collection(FirestorePaths.parcels).doc(assessment.parcelId).update({
        'status': ParcelStatus.restorationOrdered.firestoreValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// BR-9: once the external firm's opinion is DEMOLISH, the case must
  /// enter the demolition track. Creates the initial DemolitionOrder with
  /// steps 1–2 already resolved: `postedDate` = now, `executionDate` =
  /// postedDate + 30 days.
  ///
  /// TODO: that 30-day default is the same hardcoded BR-4-style period
  /// used in Review & Decision, pending the same Admin Settings screen
  /// that should make it configurable per action type. Flagging this
  /// here rather than silently duplicating the assumption unexplained.
  ///
  /// Idempotent: does nothing if a demolition order already exists for
  /// this decision.
  Future<void> _ensureDemolitionTriggered(Assessment assessment) async {
    final orderRef = firestore.collection(FirestorePaths.demolitionOrders).doc(assessment.decisionId);
    final existing = await orderRef.get();
    if (existing.exists) return;

    final postedDate = DateTime.now();
    final order = DemolitionOrder(
      id: assessment.decisionId,
      decisionId: assessment.decisionId,
      caseId: assessment.caseId,
      parcelId: assessment.parcelId,
      postedDate: postedDate,
      executionDate: postedDate.add(const Duration(days: 30)),
    );
    await orderRef.set(order.toFirestoreInitial());

    // Parcel-level status transition (Appendix B).
    await firestore.collection(FirestorePaths.parcels).doc(assessment.parcelId).update({
      'status': ParcelStatus.demolitionPending.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Ensures a restoration study document exists for this assessment
  /// (created empty, on first access — only meaningful once opinion is
  /// RESTORE, enforced by the screen, not this method).
  Future<RestorationStudy> getOrCreateStudy(Assessment assessment) async {
    final ref = firestore.collection(FirestorePaths.restorationStudies).doc(assessment.id);
    final doc = await ref.get();
    if (doc.exists) return RestorationStudy.fromFirestore(doc);

    final fresh = RestorationStudy(
      id: assessment.id,
      assessmentId: assessment.id,
      caseId: assessment.caseId,
      parcelId: assessment.parcelId,
    );
    await ref.set(fresh.toFirestoreInitial());
    return fresh;
  }

  /// FR-RST-1/2/3: saves the study, then FR-RST-4's exact condition —
  /// engineering-approved AND owner cannot bear the cost — creates the
  /// funding candidate if one doesn't already exist.
  ///
  /// Deliberately checks existence first rather than a single
  /// merge-write: a merge write would reset `proposedDate` to a fresh
  /// server timestamp every time an already-qualifying study is saved
  /// again, silently losing the real original proposal date.
  Future<void> saveRestorationStudy(
    RestorationStudy study, {
    DateTime? submittedDate,
    required bool engineeringApproved,
    OwnerCostCapacity? ownerCostCapacity,
  }) async {
    final studyRef = firestore.collection(FirestorePaths.restorationStudies).doc(study.id);
    await studyRef.update({
      if (submittedDate != null) 'submittedDate': Timestamp.fromDate(submittedDate),
      'engineeringApproved': engineeringApproved,
      if (ownerCostCapacity != null) 'ownerCostCapacity': ownerCostCapacity.firestoreValue,
    });

    final qualifies = engineeringApproved && ownerCostCapacity == OwnerCostCapacity.cannotBear;
    if (!qualifies) return;

    final candidateRef = firestore.collection(FirestorePaths.fundingCandidates).doc(study.id);
    final existing = await candidateRef.get();
    if (existing.exists) return;

    final candidate = FundingCandidate(
      id: study.id,
      restorationStudyId: study.id,
      caseId: study.caseId,
      parcelId: study.parcelId,
    );
    await candidateRef.set(candidate.toFirestoreCreate());

    // Parcel-level status transition (Appendix B).
    await firestore.collection(FirestorePaths.parcels).doc(study.parcelId).update({
      'status': ParcelStatus.fundingPending.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}