import 'package:cloud_firestore/cloud_firestore.dart';

/// (§7.3, BR-6, FR-REV-4). URGENT is auto-set, never user-chosen, when the
/// underlying report's source is URGENT_ONSITE — see ReviewScreen for
/// where that's enforced.
enum ReviewPriority {
  low,
  medium,
  high,
  urgent;

  String get label => switch (this) {
        ReviewPriority.low => 'منخفض',
        ReviewPriority.medium => 'متوسط',
        ReviewPriority.high => 'مرتفع',
        ReviewPriority.urgent => 'عاجل',
      };

  String get firestoreValue => name.toUpperCase();

  static ReviewPriority fromFirestore(String? value) {
    return ReviewPriority.values.firstWhere(
      (p) => p.firestoreValue == value,
      orElse: () => ReviewPriority.medium,
    );
  }
}

/// Mirrors TriageRecordStatus's draft/submitted distinction — a draft
/// review is just a saved-for-later snapshot; only a submitted one is
/// paired with a real Decision and Notice.
enum ReviewRecordStatus {
  draft,
  submitted;

  String get firestoreValue => name;

  static ReviewRecordStatus fromFirestore(String? value) =>
      value == 'submitted' ? ReviewRecordStatus.submitted : ReviewRecordStatus.draft;
}

/// The internal municipal review of a report (§7.3, FR-REV-2). Resolves to
/// exactly one Decision — see decision.dart — created together in the
/// same atomic write, never separately.
class Review {
  const Review({
    required this.id,
    required this.reportId,
    required this.caseId,
    required this.parcelId,
    required this.reviewerUid,
    required this.priority,
    this.status = ReviewRecordStatus.submitted,
    this.reviewedAt,
  });

  final String id;
  final String reportId;
  final String caseId;
  final String parcelId;
  final String reviewerUid;
  final ReviewPriority priority;
  final ReviewRecordStatus status;
  final DateTime? reviewedAt;

  factory Review.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Review(
      id: doc.id,
      reportId: data['reportId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      reviewerUid: data['reviewerUid'] as String? ?? '',
      priority: ReviewPriority.fromFirestore(data['priority'] as String?),
      status: ReviewRecordStatus.fromFirestore(data['status'] as String?),
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'reportId': reportId,
        'caseId': caseId,
        'parcelId': parcelId,
        'reviewerUid': reviewerUid,
        'priority': priority.firestoreValue,
        'status': status.firestoreValue,
        'reviewedAt': FieldValue.serverTimestamp(),
      };
}