import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../assessment/models/assessment.dart';
import '../../auth/auth_providers.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider, storageProvider;
import '../../intake/models/case.dart';
import '../../review/models/decision.dart';
import '../../review/models/notice.dart';
import '../models/site_visit.dart';

final siteVisitRepositoryProvider = Provider<SiteVisitRepository>((ref) {
  return SiteVisitRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(storageProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// Everything the Site Visit screen needs to talk to Firestore/Storage.
class SiteVisitRepository {
  SiteVisitRepository({required this.firestore, required this.storage, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseAuth auth;

  Future<Decision?> getDecision(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.decisions).doc(decisionId).get();
    return doc.exists ? Decision.fromFirestore(doc) : null;
  }

  Future<Case?> getCase(String caseId) async {
    final doc = await firestore.collection(FirestorePaths.cases).doc(caseId).get();
    return doc.exists ? Case.fromFirestore(doc) : null;
  }

  /// For display only — shows the reference notice ("إنذار تدعيم —
  /// NOTICE-XXXX") that this visit is verifying compliance against.
  Future<Notice?> getNoticeForDecision(String decisionId) async {
    final snap = await firestore
        .collection(FirestorePaths.notices)
        .where('decisionId', isEqualTo: decisionId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Notice.fromFirestore(snap.docs.first);
  }

  /// Every visit ever recorded against this decision, most recent first —
  /// a decision can legitimately have more than one over time (see the
  /// doc comment on [SiteVisit]).
  Future<List<SiteVisit>> getVisitsForDecision(String decisionId) async {
    final snap = await firestore
        .collection(FirestorePaths.siteVisits)
        .where('decisionId', isEqualTo: decisionId)
        .orderBy('visitedAt', descending: true)
        .get();
    return snap.docs.map(SiteVisit.fromFirestore).toList();
  }

  Future<List<String>> _uploadMedia(String parcelId, String visitId, List<PlatformFile> media) async {
    final urls = <String>[];
    for (var i = 0; i < media.length; i++) {
      final file = media[i];
      final bytes = file.bytes;
      if (bytes == null) continue;
      final ext = file.extension?.toLowerCase() ?? 'jpg';
      final ref = storage.ref('${FirestorePaths.parcels}/$parcelId/attachments/visit_${visitId}_$i.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: _mimeTypeFor(ext)));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  String _mimeTypeFor(String extension) {
    const imageExt = {'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg'};
    const videoExt = {'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm', 'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska', 'm4v': 'video/mp4'};
    return imageExt[extension] ?? videoExt[extension] ?? 'application/octet-stream';
  }

  /// FR-DASH-3/4: records the visit outcome and, when the outcome is
  /// COMPLIED, closes the case in the same atomic [WriteBatch] — so the
  /// system never ends up with a "complied" visit on a case that's still
  /// technically open, or vice versa.
  ///
  /// A NOT_COMPLIED or PARTIAL outcome triggers external assessment
  /// (BR-8) — see [_ensureAssessmentTriggered] — immediately after the
  /// batch commits.
  Future<void> submitVisit({
    required Decision decision,
    required SiteVisitOutcome outcome,
    String? notes,
    required List<PlatformFile> media,
  }) async {
    final visitRef = firestore.collection(FirestorePaths.siteVisits).doc();
    final mediaUrls = media.isEmpty ? <String>[] : await _uploadMedia(decision.parcelId, visitRef.id, media);

    final visit = SiteVisit(
      id: visitRef.id,
      decisionId: decision.id,
      caseId: decision.caseId,
      parcelId: decision.parcelId,
      outcome: outcome,
      notes: notes,
      mediaUrls: mediaUrls,
      inspectorUid: auth.currentUser?.uid ?? '',
    );

    final batch = firestore.batch();
    batch.set(visitRef, visit.toFirestoreCreate());

    // Denormalized onto the Decision so Dashboard can answer "overdue" /
    // "awaiting site visit" with a plain equality query — see the doc
    // comment on Decision.resolved. Set on EVERY visit, regardless of
    // outcome: once a decision has had at least one site visit, it's no
    // longer "awaiting its first site visit" even if that visit came
    // back NOT_COMPLIED or PARTIAL — further follow-up on those outcomes
    // is Assessment/Demolition's job, not another generic site visit.
    final decisionRef = firestore.collection(FirestorePaths.decisions).doc(decision.id);
    batch.update(decisionRef, {'resolved': true});

    if (outcome == SiteVisitOutcome.complied) {
      final caseRef = firestore.collection(FirestorePaths.cases).doc(decision.caseId);
      batch.update(caseRef, {
        'status': CaseStatus.closed.firestoreValue,
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Parcel-level status transition (Appendix B).
    final parcelRef = firestore.collection(FirestorePaths.parcels).doc(decision.parcelId);
    final nextParcelStatus = outcome == SiteVisitOutcome.complied ? ParcelStatus.closedSafe : ParcelStatus.inAssessment;
    batch.update(parcelRef, {'status': nextParcelStatus.firestoreValue, 'updatedAt': FieldValue.serverTimestamp()});

    await batch.commit();

    if (outcome != SiteVisitOutcome.complied) {
      await _ensureAssessmentTriggered(decision);
    }
  }

  /// BR-8: a warning-type decision whose site visit came back
  /// NOT_COMPLIED or PARTIAL must enter external assessment. Creates the
  /// initial, EMPTY Assessment record automatically — see the identical
  /// pattern and reasoning in EvacuationRepository. Idempotent: does
  /// nothing if this decision already has an assessment (e.g. from an
  /// earlier non-compliant visit).
  Future<void> _ensureAssessmentTriggered(Decision decision) async {
    final assessmentRef = firestore.collection(FirestorePaths.assessments).doc(decision.id);
    final existing = await assessmentRef.get();
    if (existing.exists) return;

    final assessment = Assessment(
      id: decision.id,
      decisionId: decision.id,
      caseId: decision.caseId,
      parcelId: decision.parcelId,
      triggerReason: AssessmentTrigger.nonCompliedWarning,
    );
    await assessmentRef.set(assessment.toFirestoreInitial());
  }
}