import 'package:cloud_firestore/cloud_firestore.dart';

/// The four enforcement actions a review can resolve to (§6.1, §7.4).
enum DecisionAction {
  evacuation,
  shoringWarning,
  shoringConfirm,
  restorationWarning;

  String get label => switch (this) {
        DecisionAction.evacuation => 'إخلاء (EVACUATION)',
        DecisionAction.shoringWarning => 'إنذار تدعيم (SHORING_WARNING)',
        DecisionAction.shoringConfirm => 'تأكيدي بالتدعيم (SHORING_CONFIRM)',
        DecisionAction.restorationWarning => 'إنذار ترميم (RESTORATION_WARNING)',
      };

  String get subtitle => switch (this) {
        DecisionAction.evacuation => 'خطر انهيار وشيك يستدعي إخلاء فوريًا',
        DecisionAction.shoringWarning => 'مطالبة المالك بتدعيم المبنى خلال مهلة محددة',
        DecisionAction.shoringConfirm => 'يتطلّب وجود إنذار تدعيم سابق على هذا العقار (BR-1)',
        DecisionAction.restorationWarning => 'مطالبة المالك بترميم المبنى خلال مهلة محددة',
      };

  /// The clean Arabic title used on the generated notice document itself
  /// (§8) — no parenthetical English code, unlike [label] which is used
  /// on the Review & Decision radio options.
  String get noticeTitle => switch (this) {
        DecisionAction.evacuation => 'إخلاء',
        DecisionAction.shoringWarning => 'إنذار تدعيم',
        DecisionAction.shoringConfirm => 'تأكيدي بالتدعيم',
        DecisionAction.restorationWarning => 'إنذار ترميم',
      };

  String get firestoreValue => switch (this) {
        DecisionAction.evacuation => 'EVACUATION',
        DecisionAction.shoringWarning => 'SHORING_WARNING',
        DecisionAction.shoringConfirm => 'SHORING_CONFIRM',
        DecisionAction.restorationWarning => 'RESTORATION_WARNING',
      };

  static DecisionAction fromFirestore(String? value) {
    return DecisionAction.values.firstWhere(
      (a) => a.firestoreValue == value,
      orElse: () => DecisionAction.shoringWarning,
    );
  }
}

/// The chosen enforcement action (§6.2–6.3, §7.4, FR-ACT-1..5). Created
/// together with its Review and its Notice, in one atomic write — see
/// ReviewRepository.submitReviewAndDecision.
class Decision {
  const Decision({
    required this.id,
    required this.reviewId,
    required this.caseId,
    required this.parcelId,
    required this.action,
    required this.executionDate,
    required this.createdByUid,
    this.resolved = false,
    this.createdAt,
  });

  final String id;
  final String reviewId;
  final String caseId;
  final String parcelId;
  final DecisionAction action;
  final DateTime executionDate;
  final String createdByUid;

  /// Denormalized on-decision flag: has this decision's compliance check
  /// already happened at least once? Set to true by whichever repository
  /// actually performs that check — EvacuationRepository (a compliance
  /// visit or forced enforcement) or SiteVisitRepository (any recorded
  /// visit, regardless of outcome). Exists specifically so Dashboard can
  /// answer "overdue" and "awaiting site visit" with a plain equality
  /// query instead of an expensive cross-collection join, the same
  /// denormalization technique already used for Complaint.triagedAt.
  final bool resolved;

  final DateTime? createdAt;

  factory Decision.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Decision(
      id: doc.id,
      reviewId: data['reviewId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      action: DecisionAction.fromFirestore(data['action'] as String?),
      executionDate: (data['executionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdByUid: data['createdByUid'] as String? ?? '',
      resolved: data['resolved'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'reviewId': reviewId,
        'caseId': caseId,
        'parcelId': parcelId,
        'action': action.firestoreValue,
        'executionDate': Timestamp.fromDate(executionDate),
        'createdByUid': createdByUid,
        'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}