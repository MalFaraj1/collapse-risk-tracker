import 'package:cloud_firestore/cloud_firestore.dart';

enum NoticeSource {
  system,
  imported;

  String get firestoreValue => this == NoticeSource.system ? 'SYSTEM' : 'IMPORTED';

  static NoticeSource fromFirestore(String? value) =>
      value == 'IMPORTED' ? NoticeSource.imported : NoticeSource.system;
}

/// A generated official notice instance (§8, FR-ACT-1/2/5).
///
/// NOTE: this model currently lives under features/review/ because Review
/// & Decision is the first feature that creates notices. Evacuation and
/// Demolition will need to create notices too once built — at that point
/// this model (and the notice-generation logic) should move to a shared
/// location rather than staying "owned" by Review. Flagging this now, same
/// as the Parcel-model duplication note in features/intake/models/parcel.dart.
class Notice {
  const Notice({
    required this.id,
    required this.decisionId,
    required this.caseId,
    required this.parcelId,
    required this.type,
    this.templateVersion = '1',
    this.source = NoticeSource.system,
    this.linkedWarningNoticeId,
    this.pdfUrl,
    this.postedDate,
    this.createdAt,
  });

  final String id;
  final String decisionId;
  final String caseId;
  final String parcelId;

  /// Matches the originating Decision's action — each decision maps to
  /// exactly one notice type at creation time.
  final String type;
  final String templateVersion;
  final NoticeSource source;

  /// FR-ACT-5: for a SHORING_CONFIRM notice, the original SHORING_WARNING
  /// notice it confirms. Null for every other notice type.
  final String? linkedWarningNoticeId;

  /// Null until a server-side process (a Cloud Function — not yet built in
  /// this project) actually renders the PDF. The Notice Preview screen
  /// must treat a null pdfUrl as "generation pending," not as an error —
  /// see FR-ACT-2: the PDF is always generated server-side, never on the
  /// client, so this field legitimately starts empty.
  final String? pdfUrl;

  final DateTime? postedDate;
  final DateTime? createdAt;

  factory Notice.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Notice(
      id: doc.id,
      decisionId: data['decisionId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      templateVersion: data['templateVersion'] as String? ?? '1',
      source: NoticeSource.fromFirestore(data['source'] as String?),
      linkedWarningNoticeId: data['linkedWarningNoticeId'] as String?,
      pdfUrl: data['pdfUrl'] as String?,
      postedDate: (data['postedDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'decisionId': decisionId,
        'caseId': caseId,
        'parcelId': parcelId,
        'type': type,
        'templateVersion': templateVersion,
        'source': source.firestoreValue,
        'linkedWarningNoticeId': linkedWarningNoticeId,
        'pdfUrl': null,
        'postedDate': null,
        'createdAt': FieldValue.serverTimestamp(),
      };
}