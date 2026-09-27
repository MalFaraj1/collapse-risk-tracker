import 'package:cloud_firestore/cloud_firestore.dart';

/// The outcome of the post-48h compliance visit (§6.2, BR-7).
enum ComplianceOutcome {
  vacated,
  occupantsRemain;

  String get label => this == ComplianceOutcome.vacated ? 'تم إخلاء المبنى بالكامل' : 'ما زال هناك شاغلون';
  String get firestoreValue => this == ComplianceOutcome.vacated ? 'VACATED' : 'OCCUPANTS_REMAIN';

  static ComplianceOutcome? fromFirestore(String? value) {
    if (value == null) return null;
    return value == 'VACATED' ? ComplianceOutcome.vacated : ComplianceOutcome.occupantsRemain;
  }
}

/// Police's execution of an EVACUATION decision, tracked as four
/// sequential sub-tasks (§6.2, §7.5, BR-7, FR-EVC-1..6). One document per
/// evacuation decision — its Firestore document ID is deliberately the
/// SAME as the originating Decision's ID (see EvacuationRepository), a
/// 1:1 relationship, the same deterministic-ID technique used for Parcel.
class EvacuationExecution {
  const EvacuationExecution({
    required this.id,
    required this.decisionId,
    required this.caseId,
    required this.parcelId,
    this.postedDate,
    this.residentsDataCollected = false,
    this.residentsDataCollectedDate,
    this.familyCount,
    this.individualCount,
    this.residentsDataSentToRelief = false,
    this.residentsDataSentDate,
    this.complianceVisitDate,
    this.complianceOutcome,
    this.enforced = false,
    this.enforcedDate,
    this.createdAt,
  });

  final String id;
  final String decisionId;
  final String caseId;
  final String parcelId;

  /// Step 1 (FR-EVC-2). Starts the 48-hour compliance clock — the
  /// deadline is always DERIVED as postedDate + 48h, never stored
  /// separately, so it can never drift out of sync with when the order
  /// was actually posted.
  final DateTime? postedDate;

  /// Step 2 (FR-EVC-3).
  final bool residentsDataCollected;
  final DateTime? residentsDataCollectedDate;
  final int? familyCount;
  final int? individualCount;

  /// Step 3 (FR-EVC-4) — sent to هيئة الإغاثة العليا for compensation.
  final bool residentsDataSentToRelief;
  final DateTime? residentsDataSentDate;

  /// Step 4 (FR-EVC-5).
  final DateTime? complianceVisitDate;
  final ComplianceOutcome? complianceOutcome;

  /// Step 5, only if occupants remained after the compliance visit.
  final bool enforced;
  final DateTime? enforcedDate;

  final DateTime? createdAt;

  DateTime? get complianceDeadline => postedDate?.add(const Duration(hours: 48));

  bool get isFullyVacated => complianceOutcome == ComplianceOutcome.vacated || enforced;

  factory EvacuationExecution.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return EvacuationExecution(
      id: doc.id,
      decisionId: data['decisionId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      postedDate: (data['postedDate'] as Timestamp?)?.toDate(),
      residentsDataCollected: data['residentsDataCollected'] as bool? ?? false,
      residentsDataCollectedDate: (data['residentsDataCollectedDate'] as Timestamp?)?.toDate(),
      familyCount: (data['familyCount'] as num?)?.toInt(),
      individualCount: (data['individualCount'] as num?)?.toInt(),
      residentsDataSentToRelief: data['residentsDataSentToRelief'] as bool? ?? false,
      residentsDataSentDate: (data['residentsDataSentDate'] as Timestamp?)?.toDate(),
      complianceVisitDate: (data['complianceVisitDate'] as Timestamp?)?.toDate(),
      complianceOutcome: ComplianceOutcome.fromFirestore(data['complianceOutcome'] as String?),
      enforced: data['enforced'] as bool? ?? false,
      enforcedDate: (data['enforcedDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreInitial() => {
        'decisionId': decisionId,
        'caseId': caseId,
        'parcelId': parcelId,
        'postedDate': null,
        'residentsDataCollected': false,
        'residentsDataCollectedDate': null,
        'familyCount': null,
        'individualCount': null,
        'residentsDataSentToRelief': false,
        'residentsDataSentDate': null,
        'complianceVisitDate': null,
        'complianceOutcome': null,
        'enforced': false,
        'enforcedDate': null,
        'createdAt': FieldValue.serverTimestamp(),
      };
}