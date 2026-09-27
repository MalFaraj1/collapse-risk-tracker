import 'package:cloud_firestore/cloud_firestore.dart';

/// (§5.1, BR-10, FR-RST-3).
enum OwnerCostCapacity {
  canBear,
  cannotBear;

  String get label => this == OwnerCostCapacity.canBear ? 'قادر على تحمّل الكلفة (CAN_BEAR)' : 'غير قادر على تحمّل الكلفة (CANNOT_BEAR)';
  String get firestoreValue => this == OwnerCostCapacity.canBear ? 'CAN_BEAR' : 'CANNOT_BEAR';

  static OwnerCostCapacity? fromFirestore(String? value) {
    if (value == null) return null;
    return value == 'CAN_BEAR' ? OwnerCostCapacity.canBear : OwnerCostCapacity.cannotBear;
  }
}

/// The owner-submitted restoration study and engineering's approval of it
/// (§5.1, §7.6a, BR-10, FR-RST-1/2/3). Only meaningful once the linked
/// [Assessment]'s opinion is RESTORE. One per assessment — its document ID
/// is deliberately the SAME as the Assessment's ID (the same 1:1 technique
/// used throughout this app).
class RestorationStudy {
  const RestorationStudy({
    required this.id,
    required this.assessmentId,
    required this.caseId,
    required this.parcelId,
    this.submittedDate,
    this.engineeringApproved = false,
    this.ownerCostCapacity,
    this.createdAt,
  });

  final String id;
  final String assessmentId;
  final String caseId;
  final String parcelId;
  final DateTime? submittedDate;
  final bool engineeringApproved;
  final OwnerCostCapacity? ownerCostCapacity;
  final DateTime? createdAt;

  /// FR-RST-4: the exact condition that makes a building a funding
  /// candidate — paperwork complete (approved) AND owner cannot bear cost.
  bool get isFundingCandidate => engineeringApproved && ownerCostCapacity == OwnerCostCapacity.cannotBear;

  factory RestorationStudy.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return RestorationStudy(
      id: doc.id,
      assessmentId: data['assessmentId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      submittedDate: (data['submittedDate'] as Timestamp?)?.toDate(),
      engineeringApproved: data['engineeringApproved'] as bool? ?? false,
      ownerCostCapacity: OwnerCostCapacity.fromFirestore(data['ownerCostCapacity'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreInitial() => {
        'assessmentId': assessmentId,
        'caseId': caseId,
        'parcelId': parcelId,
        'submittedDate': null,
        'engineeringApproved': false,
        'ownerCostCapacity': null,
        'createdAt': FieldValue.serverTimestamp(),
      };
}