import 'package:cloud_firestore/cloud_firestore.dart';

/// The two possible outcomes of triage (§7.1a, BR-5). Firestore values are
/// uppercase to match the same convention already established for
/// [CaseStatus] — not required by any security rule here, but keeping one
/// consistent convention across the app is worth more than saving a few
/// characters.
enum TriageUrgency {
  urgent,
  notUrgent;

  String get label => this == TriageUrgency.urgent ? 'عاجل' : 'غير عاجل';
  String get firestoreValue => this == TriageUrgency.urgent ? 'URGENT' : 'NOT_URGENT';

  static TriageUrgency fromFirestore(String? value) =>
      value == 'URGENT' ? TriageUrgency.urgent : TriageUrgency.notUrgent;
}

/// Whether a triage record is a real decision or just a saved-for-later
/// draft. A draft does NOT update the linked Case (no referral/dispatch
/// marker is set) — only a submitted triage record does that. See
/// TriageRepository.saveTriage.
enum TriageRecordStatus {
  draft,
  submitted;

  String get firestoreValue => name;

  static TriageRecordStatus fromFirestore(String? value) =>
      value == 'submitted' ? TriageRecordStatus.submitted : TriageRecordStatus.draft;
}

/// The engineering team's urgency decision on a complaint (§7.1a, BR-5,
/// FR-TRI-1..4). Deliberately does NOT carry the on-site engineer's report
/// content — per the approved design, Triage only records the dispatch/
/// referral decision itself; the actual fast-track report is entered
/// later, on the Review & Decision screen, once an engineer has actually
/// visited the site.
class Triage {
  const Triage({
    required this.id,
    required this.complaintId,
    required this.caseId,
    required this.parcelId,
    required this.urgency,
    this.notes,
    required this.triagedByUid,
    this.triagedAt,
    this.status = TriageRecordStatus.submitted,
  });

  final String id;
  final String complaintId;
  final String caseId;
  final String parcelId;
  final TriageUrgency urgency;
  final String? notes;
  final String triagedByUid;
  final DateTime? triagedAt;
  final TriageRecordStatus status;

  factory Triage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Triage(
      id: doc.id,
      complaintId: data['complaintId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      urgency: TriageUrgency.fromFirestore(data['urgency'] as String?),
      notes: data['notes'] as String?,
      triagedByUid: data['triagedByUid'] as String? ?? '',
      triagedAt: (data['triagedAt'] as Timestamp?)?.toDate(),
      status: TriageRecordStatus.fromFirestore(data['status'] as String?),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'complaintId': complaintId,
        'caseId': caseId,
        'parcelId': parcelId,
        'urgency': urgency.firestoreValue,
        'notes': notes,
        'triagedByUid': triagedByUid,
        'triagedAt': FieldValue.serverTimestamp(),
        'status': status.firestoreValue,
      };
}