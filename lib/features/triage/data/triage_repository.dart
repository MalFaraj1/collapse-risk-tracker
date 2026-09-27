import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../auth/auth_providers.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/complaint.dart';
import '../models/triage.dart';

final triageRepositoryProvider = Provider<TriageRepository>((ref) {
  return TriageRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// Everything the Triage screen needs to talk to Firestore.
class TriageRepository {
  TriageRepository({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Loads the one complaint being triaged.
  Future<Complaint?> getComplaint(String complaintId) async {
    final doc = await firestore.collection(FirestorePaths.complaints).doc(complaintId).get();
    return doc.exists ? Complaint.fromFirestore(doc) : null;
  }

  /// Saves a triage decision.
  ///
  /// [isDraft] = true only ever writes the `triage` document itself, with
  /// status = draft — it does NOT touch the linked case, since a draft
  /// isn't a real decision yet and shouldn't trigger BR-5's referral/
  /// dispatch state change.
  ///
  /// [isDraft] = false (a real submission) does two writes atomically in
  /// one [WriteBatch]: the `triage` document (status = submitted) AND the
  /// case update — either `referredToCommitteeAt` (NOT_URGENT) or
  /// `dispatchedOnsiteAt` (URGENT). Atomic so the system can never end up
  /// with a submitted triage decision whose case wasn't actually updated
  /// to match, or vice versa.
  Future<void> saveTriage({
    required Complaint complaint,
    required TriageUrgency urgency,
    String? notes,
    required bool isDraft,
  }) async {
    final triageRef = firestore.collection(FirestorePaths.triage).doc();
    final triage = Triage(
      id: triageRef.id,
      complaintId: complaint.id,
      caseId: complaint.caseId,
      parcelId: complaint.parcelId,
      urgency: urgency,
      notes: notes,
      triagedByUid: auth.currentUser?.uid ?? '',
      status: isDraft ? TriageRecordStatus.draft : TriageRecordStatus.submitted,
    );

    if (isDraft) {
      await triageRef.set(triage.toFirestoreCreate());
      return;
    }

    final batch = firestore.batch();
    batch.set(triageRef, triage.toFirestoreCreate());

    final caseRef = firestore.collection(FirestorePaths.cases).doc(complaint.caseId);
    batch.update(caseRef, {
      if (urgency == TriageUrgency.urgent) 'dispatchedOnsiteAt': FieldValue.serverTimestamp(),
      if (urgency == TriageUrgency.notUrgent) 'referredToCommitteeAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Denormalize onto the complaint so the dashboard's triage queue drops it.
    final complaintRef = firestore.collection(FirestorePaths.complaints).doc(complaint.id);
    batch.update(complaintRef, {'triagedAt': FieldValue.serverTimestamp()});

    await batch.commit();
  }
}