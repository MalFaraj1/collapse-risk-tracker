import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../assessment/models/assessment.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../review/models/decision.dart';
import '../models/evacuation_execution.dart';

final evacuationRepositoryProvider = Provider<EvacuationRepository>((ref) {
  return EvacuationRepository(firestore: ref.watch(firestoreProvider));
});

/// Everything the Evacuation Execution screen needs to talk to Firestore.
class EvacuationRepository {
  EvacuationRepository({required this.firestore});

  final FirebaseFirestore firestore;

  Future<Decision?> getDecision(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.decisions).doc(decisionId).get();
    return doc.exists ? Decision.fromFirestore(doc) : null;
  }

  /// Gets the execution record for this decision, creating an empty one
  /// on first access if none exists yet — its document ID is deliberately
  /// the SAME as the Decision's ID (a real 1:1 relationship), so this is
  /// a direct `get()` by ID, never a query.
  Future<EvacuationExecution> getOrCreate(Decision decision) async {
    final ref = firestore.collection(FirestorePaths.evacuationExecutions).doc(decision.id);
    final doc = await ref.get();
    if (doc.exists) return EvacuationExecution.fromFirestore(doc);

    final fresh = EvacuationExecution(
      id: decision.id,
      decisionId: decision.id,
      caseId: decision.caseId,
      parcelId: decision.parcelId,
    );
    await ref.set(fresh.toFirestoreInitial());
    return fresh;
  }

  DocumentReference<Map<String, dynamic>> _ref(String id) =>
      firestore.collection(FirestorePaths.evacuationExecutions).doc(id);

  /// FR-EVC-2: step 1 — posting the order starts the 48h compliance clock.
  Future<void> markPosted(String id) => _ref(id).update({'postedDate': FieldValue.serverTimestamp()});

  /// FR-EVC-3: step 2.
  Future<void> markResidentsDataCollected(String id, {required int families, required int individuals}) =>
      _ref(id).update({
        'residentsDataCollected': true,
        'residentsDataCollectedDate': FieldValue.serverTimestamp(),
        'familyCount': families,
        'individualCount': individuals,
      });

  /// FR-EVC-4: step 3.
  Future<void> markSentToRelief(String id) => _ref(id).update({
        'residentsDataSentToRelief': true,
        'residentsDataSentDate': FieldValue.serverTimestamp(),
      });

  /// FR-EVC-5: step 4 — the post-48h compliance visit.
  Future<void> recordComplianceVisit(String id, {required ComplianceOutcome outcome}) async {
    await _ref(id).update({
      'complianceVisitDate': FieldValue.serverTimestamp(),
      'complianceOutcome': outcome.firestoreValue,
    });
    await _markDecisionResolved(id);
    if (outcome == ComplianceOutcome.vacated) {
      final execution = await _ref(id).get();
      await _ensureAssessmentTriggered(id, execution.data());
    }
  }

  /// Step 5 — only reachable if the compliance visit found occupants
  /// remaining.
  Future<void> markEnforced(String id) async {
    await _ref(id).update({'enforced': true, 'enforcedDate': FieldValue.serverTimestamp()});
    await _markDecisionResolved(id);
    final execution = await _ref(id).get();
    await _ensureAssessmentTriggered(id, execution.data());
  }

  /// Denormalized onto the Decision itself so Dashboard can answer
  /// "overdue" / "awaiting site visit" with a plain equality query — see
  /// the doc comment on [Decision.resolved]. The evacuation execution's
  /// own document ID IS the decision's ID (the established 1:1 chain), so
  /// no extra lookup is needed here.
  Future<void> _markDecisionResolved(String decisionId) {
    return firestore.collection(FirestorePaths.decisions).doc(decisionId).update({'resolved': true});
  }

  /// BR-8: once a building is confirmed vacated (or forcibly enforced),
  /// it must enter external assessment. This creates the initial,
  /// EMPTY Assessment record automatically — the actual order-sent and
  /// opinion-received fields are filled in later by Engineering on the
  /// Assessment screen; nothing here contacts the external firm itself,
  /// which is explicitly out of this POC's scope (§2.2).
  ///
  /// Idempotent: does nothing if an assessment already exists for this
  /// decision (e.g. markEnforced firing after recordComplianceVisit
  /// already triggered one for the same decision).
  Future<void> _ensureAssessmentTriggered(String decisionId, Map<String, dynamic>? executionData) async {
    if (executionData == null) return;
    final assessmentRef = firestore.collection(FirestorePaths.assessments).doc(decisionId);
    final existing = await assessmentRef.get();
    if (existing.exists) return;

    final assessment = Assessment(
      id: decisionId,
      decisionId: decisionId,
      caseId: executionData['caseId'] as String? ?? '',
      parcelId: executionData['parcelId'] as String? ?? '',
      triggerReason: AssessmentTrigger.evacuation,
    );
    await assessmentRef.set(assessment.toFirestoreInitial());
  }
}