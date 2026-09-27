import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a Case (spec §6.1). Stored as an UPPERCASE string in
/// Firestore to match `firestore.rules` exactly, which checks
/// `resource.data.status != 'CLOSED'` on the `cases` collection — this is
/// the server-side half of Business Rule BR-2 (a closed case is never
/// written to again). If this enum's values ever change, update the
/// security rules in the same commit, or BR-2's server-side enforcement
/// silently stops working.
enum CaseStatus {
  open,
  closed;

  String get label => this == CaseStatus.open ? 'مفتوحة' : 'مغلقة';

  String get firestoreValue => this == CaseStatus.open ? 'OPEN' : 'CLOSED';

  static CaseStatus fromFirestore(String? value) =>
      value == 'CLOSED' ? CaseStatus.closed : CaseStatus.open;
}

/// A follow-up thread on a parcel (§6.1). A parcel can have more than one
/// Case over its lifetime — Business Rule BR-2: a CLOSED case is never
/// reopened; a later complaint always opens a NEW case, and every prior
/// case remains on the parcel's timeline as permanent history (BR-3).
class Case {
  const Case({
    required this.id,
    required this.parcelId,
    required this.status,
    required this.openedAt,
    this.closedAt,
    this.referredToCommitteeAt,
    this.dispatchedOnsiteAt,
    this.reviewed = false,
  });

  final String id;
  final String parcelId;
  final CaseStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;

  /// Set by Triage (BR-5) when a NOT_URGENT complaint is referred to the
  /// joint engineering committee. The committee's own internal process
  /// (assignment, site visit) happens outside this system — this field
  /// just records that the referral happened and when.
  final DateTime? referredToCommitteeAt;

  /// Set by Triage (BR-5) when a URGENT complaint results in a municipal
  /// engineer being dispatched on-site. The resulting fast-track report
  /// itself is recorded later, on the Review & Decision screen, once the
  /// engineer has actually visited — not here.
  final DateTime? dispatchedOnsiteAt;

  /// Denormalized on-case flag: has a Decision already been submitted for
  /// this case? Set to true by ReviewRepository.submitReviewAndDecision,
  /// in the same atomic batch as the Review/Decision/Notice it creates.
  /// Exists specifically so Dashboard can list "cases awaiting review" —
  /// triaged (dispatched or referred) but not yet decided — with a plain
  /// equality query, the same denormalization technique already used for
  /// Complaint.triagedAt and Decision.resolved.
  final bool reviewed;

  /// True once Triage has routed this case somewhere (dispatched an
  /// engineer or referred it to committee) but no Decision exists yet —
  /// exactly the state Dashboard's "بانتظار المراجعة" queue is for.
  bool get awaitingReview => !reviewed && (referredToCommitteeAt != null || dispatchedOnsiteAt != null);

  factory Case.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Case(
      id: doc.id,
      parcelId: data['parcelId'] as String? ?? '',
      status: CaseStatus.fromFirestore(data['status'] as String?),
      openedAt: (data['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      referredToCommitteeAt: (data['referredToCommitteeAt'] as Timestamp?)?.toDate(),
      dispatchedOnsiteAt: (data['dispatchedOnsiteAt'] as Timestamp?)?.toDate(),
      reviewed: data['reviewed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'parcelId': parcelId,
        'status': CaseStatus.open.firestoreValue,
        'openedAt': FieldValue.serverTimestamp(),
        'closedAt': null,
        'reviewed': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}