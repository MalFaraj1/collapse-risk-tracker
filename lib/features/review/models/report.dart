import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a report came from (§6.1, BR-6). Both sources feed the same
/// Review step identically — the only behavioral difference anywhere in
/// the system is BR-6: a URGENT_ONSITE report auto-sets review priority
/// to Urgent.
enum ReportSource {
  committee,
  urgentOnsite;

  String get label => this == ReportSource.committee ? 'اللجنة الهندسية المشتركة' : 'معاينة موقعية عاجلة';
  String get firestoreValue => this == ReportSource.committee ? 'COMMITTEE' : 'URGENT_ONSITE';

  static ReportSource fromFirestore(String? value) =>
      value == 'URGENT_ONSITE' ? ReportSource.urgentOnsite : ReportSource.committee;
}

/// A report feeding a municipal review (§5.1, §7.3, FR-REV-1). Created
/// either from the joint engineering committee's write-up, or from a
/// municipal engineer's fast-track on-site assessment (Triage's URGENT
/// path) — see [ReportSource].
class Report {
  const Report({
    required this.id,
    required this.caseId,
    required this.parcelId,
    required this.source,
    this.reference,
    required this.date,
    required this.summary,
    required this.mediaUrls,
    required this.createdByUid,
    this.createdAt,
  });

  final String id;
  final String caseId;
  final String parcelId;
  final ReportSource source;
  final String? reference;
  final DateTime date;
  final String summary;
  final List<String> mediaUrls; // photos AND videos — see core/widgets/media_thumbnail.dart
  final String createdByUid;
  final DateTime? createdAt;

  factory Report.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Report(
      id: doc.id,
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      source: ReportSource.fromFirestore(data['source'] as String?),
      reference: data['reference'] as String?,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      summary: data['summary'] as String? ?? '',
      mediaUrls: List<String>.from(data['mediaUrls'] as List? ?? const []),
      createdByUid: data['createdByUid'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'caseId': caseId,
        'parcelId': parcelId,
        'source': source.firestoreValue,
        'reference': reference,
        'date': Timestamp.fromDate(date),
        'summary': summary,
        'mediaUrls': mediaUrls,
        'createdByUid': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      };
}