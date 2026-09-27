import 'package:cloud_firestore/cloud_firestore.dart';

/// A police-posted demolition order and its execution (§5.1, §6.6, §7.7,
/// BR-9, FR-DEM-1..3). One per originating decision — its document ID is
/// deliberately the SAME as the Decision's ID, continuing the same 1:1
/// chain already used for [EvacuationExecution] and Assessment: a
/// decision whose path ends in demolition has Decision.id == Assessment.id
/// == DemolitionOrder.id.
///
/// Created automatically (steps 1–2 pre-filled) the moment BR-8's
/// assessment resolves to DEMOLISH — see the trigger added to
/// AssessmentRepository. This screen never creates the initial order
/// itself, it only progresses one that already exists.
class DemolitionOrder {
  const DemolitionOrder({
    required this.id,
    required this.decisionId,
    required this.caseId,
    required this.parcelId,
    required this.postedDate,
    required this.executionDate,
    this.externalCoordinated = false,
    this.externalCoordinatedDate,
    this.contractorReference,
    this.actualExecutionDate,
    this.executed = false,
    this.createdAt,
  });

  final String id;
  final String decisionId;
  final String caseId;
  final String parcelId;

  /// Step 1 (FR-DEM-1) — always set at creation time, since the order
  /// only ever comes into existence via the automatic BR-8 trigger.
  final DateTime postedDate;

  /// Step 2 (FR-DEM-1) — the SCHEDULED execution date, set at creation
  /// time (postedDate + a default period, mirroring BR-4's pattern
  /// elsewhere — see the TODO on the trigger in AssessmentRepository).
  final DateTime executionDate;

  /// Step 3 (FR-DEM-2, BR-9) — coordination with the external entity to
  /// attend on the execution date. Deliberately its own boolean with its
  /// own timestamp, saved independently of the final execution — in
  /// practice coordination happens days before the actual demolition, not
  /// in the same action.
  final bool externalCoordinated;
  final DateTime? externalCoordinatedDate;

  /// Step 4 (FR-DEM-3) — contractor assignment via direct order (أمر
  /// مباشرة) and the terminal execution confirmation.
  final String? contractorReference;
  final DateTime? actualExecutionDate;
  final bool executed;

  final DateTime? createdAt;

  factory DemolitionOrder.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DemolitionOrder(
      id: doc.id,
      decisionId: data['decisionId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      postedDate: (data['postedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      executionDate: (data['executionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      externalCoordinated: data['externalCoordinated'] as bool? ?? false,
      externalCoordinatedDate: (data['externalCoordinatedDate'] as Timestamp?)?.toDate(),
      contractorReference: data['contractorReference'] as String?,
      actualExecutionDate: (data['actualExecutionDate'] as Timestamp?)?.toDate(),
      executed: data['executed'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreInitial() => {
        'decisionId': decisionId,
        'caseId': caseId,
        'parcelId': parcelId,
        'postedDate': Timestamp.fromDate(postedDate),
        'executionDate': Timestamp.fromDate(executionDate),
        'externalCoordinated': false,
        'externalCoordinatedDate': null,
        'contractorReference': null,
        'actualExecutionDate': null,
        'executed': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}