import 'package:cloud_firestore/cloud_firestore.dart';

enum ComplaintChannel {
  phone,
  walkIn,
  officialReferral;

  String get label => switch (this) {
        ComplaintChannel.phone => 'اتصال هاتفي',
        ComplaintChannel.walkIn => 'حضور شخصي',
        ComplaintChannel.officialReferral => 'إحالة من جهة رسمية',
      };

  String get firestoreValue => name;

  static ComplaintChannel fromFirestore(String? value) {
    return ComplaintChannel.values.firstWhere(
      (c) => c.name == value,
      orElse: () => ComplaintChannel.phone,
    );
  }
}

/// A logged citizen complaint (§7.1, FR-INT-1). Always linked to a Case,
/// never directly to a Parcel — the Case is what BR-2's open/closed
/// lifecycle actually governs; the Complaint is just one event within it.
class Complaint {
  const Complaint({
    required this.id,
    required this.caseId,
    required this.parcelId,
    required this.date,
    required this.channel,
    required this.narrative,
    this.complainantContact,
    required this.photoUrls,
    this.createdAt,
    required this.createdByUid,
    this.triagedAt,
    this.updatedAt,
  });

  final String id;
  final String caseId;
  final String parcelId; // denormalized, for easier querying/display
  final DateTime date;
  final ComplaintChannel channel;
  final String narrative;
  final String? complainantContact;
  final List<String> photoUrls;
  final DateTime? createdAt;
  final String createdByUid;

  /// Denormalized from the submitted Triage record so the dashboard can
  /// find untriaged complaints without a join. Null (or absent, for older
  /// documents) means no triage has been submitted yet. Drafts don't set it.
  final DateTime? triagedAt;

  /// Set only when the complaint has been edited after its initial
  /// submission — null on a never-edited complaint. Purely informational
  /// (e.g. an optional "last edited" note in the UI); nothing currently
  /// branches on it.
  final DateTime? updatedAt;

  bool get needsTriage => triagedAt == null;

  factory Complaint.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Complaint(
      id: doc.id,
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      channel: ComplaintChannel.fromFirestore(data['channel'] as String?),
      narrative: data['narrative'] as String? ?? '',
      complainantContact: data['complainantContact'] as String?,
      photoUrls: List<String>.from(data['photoUrls'] as List? ?? const []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdByUid: data['createdByUid'] as String? ?? '',
      triagedAt: (data['triagedAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'caseId': caseId,
        'parcelId': parcelId,
        'date': Timestamp.fromDate(date),
        'channel': channel.firestoreValue,
        'narrative': narrative,
        'complainantContact': complainantContact,
        'photoUrls': photoUrls,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': createdByUid,
      };

  /// Fields an edit is allowed to change. Deliberately excludes
  /// `caseId`, `parcelId`, `createdAt`, `createdByUid`, `triagedAt`, and
  /// — per your explicit instruction — `photoUrls`: editing a complaint's
  /// text/channel/date/contact never moves it to a different case or
  /// parcel, rewrites who first logged it or when, un-triages it, or
  /// touches its existing photos. Used with Firestore's partial
  /// `.update()`, not `.set()`, so any key left out of this map is simply
  /// never touched on the stored document.
  Map<String, dynamic> toFirestoreUpdate() => {
        'date': Timestamp.fromDate(date),
        'channel': channel.firestoreValue,
        'narrative': narrative,
        'complainantContact': complainantContact,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}