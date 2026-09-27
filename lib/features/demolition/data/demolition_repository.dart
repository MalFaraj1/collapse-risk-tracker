import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../intake/models/case.dart';
import '../../review/models/decision.dart';
import '../models/demolition_order.dart';

final demolitionRepositoryProvider = Provider<DemolitionRepository>((ref) {
  return DemolitionRepository(firestore: ref.watch(firestoreProvider));
});

/// Everything the Demolition screen needs to talk to Firestore.
class DemolitionRepository {
  DemolitionRepository({required this.firestore});

  final FirebaseFirestore firestore;

  Future<Decision?> getDecision(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.decisions).doc(decisionId).get();
    return doc.exists ? Decision.fromFirestore(doc) : null;
  }

  /// Deliberately does NOT create an order — same reasoning as
  /// AssessmentRepository.getAssessment: an order should only ever come
  /// into existence via the automatic BR-8 trigger, never by simply
  /// opening this screen. Null means demolition hasn't been triggered for
  /// this decision yet.
  Future<DemolitionOrder?> getOrder(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.demolitionOrders).doc(decisionId).get();
    return doc.exists ? DemolitionOrder.fromFirestore(doc) : null;
  }

  /// FR-DEM-2, BR-9: records coordination with the external entity,
  /// independently of the final execution — in practice this happens
  /// days ahead of the actual demolition, not in the same action.
  Future<void> setCoordinated(String orderId, bool value) {
    return firestore.collection(FirestorePaths.demolitionOrders).doc(orderId).update({
      'externalCoordinated': value,
      'externalCoordinatedDate': value ? FieldValue.serverTimestamp() : null,
    });
  }

  /// FR-DEM-3: the terminal action — contractor assignment and execution
  /// confirmation. Closes the case AND sets the parcel's terminal
  /// DEMOLISHED status (distinct from CLOSED_SAFE) in the SAME atomic
  /// [WriteBatch] — the system never ends up with an executed demolition
  /// whose case/parcel weren't updated to match.
  Future<void> confirmExecution(
    DemolitionOrder order, {
    required String contractorReference,
    required DateTime actualExecutionDate,
  }) async {
    final orderRef = firestore.collection(FirestorePaths.demolitionOrders).doc(order.id);
    final batch = firestore.batch();
    batch.update(orderRef, {
      'contractorReference': contractorReference,
      'actualExecutionDate': Timestamp.fromDate(actualExecutionDate),
      'executed': true,
    });

    final caseRef = firestore.collection(FirestorePaths.cases).doc(order.caseId);
    batch.update(caseRef, {
      'status': CaseStatus.closed.firestoreValue,
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final parcelRef = firestore.collection(FirestorePaths.parcels).doc(order.parcelId);
    batch.update(parcelRef, {
      'status': ParcelStatus.demolished.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}