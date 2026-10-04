import 'package:cloud_firestore/cloud_firestore.dart';

/// What kind of record a parcel-level attachment is (§2.1 item 10: "photos,
/// committee report, external study" — issued notices are their own Notice
/// documents already, so they aren't a category here).
enum AttachmentCategory {
  photo,
  committeeReport,
  externalStudy,
  other;

  String get label => switch (this) {
        AttachmentCategory.photo => 'صورة',
        AttachmentCategory.committeeReport => 'تقرير اللجنة الهندسية',
        AttachmentCategory.externalStudy => 'دراسة خارجية',
        AttachmentCategory.other => 'أخرى',
      };

  String get firestoreValue => name.toUpperCase();

  static AttachmentCategory fromFirestore(String? v) => AttachmentCategory.values.firstWhere(
        (c) => c.firestoreValue == v,
        orElse: () => AttachmentCategory.other,
      );
}

/// A file attached directly to a parcel (`attachments/{id}`, §5.1, §7.11,
/// FR-AUD-1) — distinct from evidence captured as part of a specific
/// workflow step (a complaint's photos, a site visit's photos), which
/// stay on those records. This is for material that belongs to the
/// parcel itself: a committee report, an external engineering study, a
/// general photo, or anything else staff need on file.
class ParcelAttachment {
  const ParcelAttachment({
    required this.id,
    required this.parcelId,
    required this.url,
    required this.fileName,
    required this.contentType,
    required this.category,
    required this.uploaderUid,
    this.uploadedAt,
  });

  final String id;
  final String parcelId;
  final String url;
  final String fileName;
  final String contentType;
  final AttachmentCategory category;
  final String uploaderUid;
  final DateTime? uploadedAt;

  bool get isImage => contentType.startsWith('image/');
  bool get isVideo => contentType.startsWith('video/');
  bool get isPdf => contentType == 'application/pdf';

  factory ParcelAttachment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ParcelAttachment(
      id: doc.id,
      parcelId: d['parcelId'] as String? ?? '',
      url: d['url'] as String? ?? '',
      fileName: d['fileName'] as String? ?? '',
      contentType: d['contentType'] as String? ?? '',
      category: AttachmentCategory.fromFirestore(d['category'] as String?),
      uploaderUid: d['uploaderUid'] as String? ?? '',
      uploadedAt: (d['uploadedAt'] as Timestamp?)?.toDate(),
    );
  }
}