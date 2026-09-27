import 'package:cloud_firestore/cloud_firestore.dart';

/// The three possible outcomes of a compliance site visit (§7.8, FR-DASH-3/4).
enum SiteVisitOutcome {
  complied,
  notComplied,
  partial;

  String get label => switch (this) {
        SiteVisitOutcome.complied => 'تم الامتثال (COMPLIED)',
        SiteVisitOutcome.notComplied => 'لم يتم الامتثال (NOT_COMPLIED)',
        SiteVisitOutcome.partial => 'امتثال جزئي (PARTIAL)',
      };

  String get subtitle => switch (this) {
        SiteVisitOutcome.complied => 'الأعمال المطلوبة نُفّذت بالكامل — تُغلق الحالة كآمنة',
        SiteVisitOutcome.notComplied => 'تُحال الحالة إلى التقييم الخارجي',
        SiteVisitOutcome.partial => 'تنفيذ جزء من الأعمال المطلوبة فقط',
      };

  String get firestoreValue => switch (this) {
        SiteVisitOutcome.complied => 'COMPLIED',
        SiteVisitOutcome.notComplied => 'NOT_COMPLIED',
        SiteVisitOutcome.partial => 'PARTIAL',
      };

  static SiteVisitOutcome fromFirestore(String? value) {
    return SiteVisitOutcome.values.firstWhere(
      (o) => o.firestoreValue == value,
      orElse: () => SiteVisitOutcome.notComplied,
    );
  }
}

/// A compliance-verification visit against a warning-type decision (§7.8,
/// FR-DASH-3/4). Deliberately a plain, repeatable record linked to a
/// Decision by a simple foreign key — NOT a 1:1 relationship like
/// [EvacuationExecution] — because a decision can legitimately have more
/// than one visit over time if an earlier one was inconclusive (PARTIAL)
/// or if compliance needs re-checking later.
class SiteVisit {
  const SiteVisit({
    required this.id,
    required this.decisionId,
    required this.caseId,
    required this.parcelId,
    required this.outcome,
    this.notes,
    required this.mediaUrls,
    required this.inspectorUid,
    this.visitedAt,
  });

  final String id;
  final String decisionId;
  final String caseId;
  final String parcelId;
  final SiteVisitOutcome outcome;
  final String? notes;
  final List<String> mediaUrls; // photos AND videos — see core/widgets/media_thumbnail.dart
  final String inspectorUid;
  final DateTime? visitedAt;

  factory SiteVisit.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SiteVisit(
      id: doc.id,
      decisionId: data['decisionId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      outcome: SiteVisitOutcome.fromFirestore(data['outcome'] as String?),
      notes: data['notes'] as String?,
      mediaUrls: List<String>.from(data['mediaUrls'] as List? ?? const []),
      inspectorUid: data['inspectorUid'] as String? ?? '',
      visitedAt: (data['visitedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'decisionId': decisionId,
        'caseId': caseId,
        'parcelId': parcelId,
        'outcome': outcome.firestoreValue,
        'notes': notes,
        'mediaUrls': mediaUrls,
        'inspectorUid': inspectorUid,
        'visitedAt': FieldValue.serverTimestamp(),
      };
}