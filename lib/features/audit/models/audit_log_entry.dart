import 'package:cloud_firestore/cloud_firestore.dart';

/// One immutable record in the audit trail (`auditLogs/{id}`, NFR-3,
/// FR-AUD-2/3): "every create/update/status-change: actor, role, entity,
/// before/after, timestamp."
///
/// [actorUid] is stored alone — not a denormalized display name or role.
/// The viewer resolves both by looking the uid up in the `users`
/// directory at read time (the exact pattern R4/R6 already use for
/// "who did this"), rather than copying that data onto every single log
/// entry as it's written.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.parcelId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.summary,
    required this.actorUid,
    this.beforeValue,
    this.afterValue,
    this.timestamp,
  });

  final String id;

  /// Denormalized for the same reason every other per-parcel collection in
  /// this project denormalizes it: a plain equality query, no composite
  /// index, no join.
  final String parcelId;

  /// Which kind of record changed — e.g. 'DECISION', 'PARCEL', 'ATTACHMENT'.
  final String entityType;

  /// The changed record's own document id, so a log entry can link
  /// straight back to it.
  final String entityId;

  /// A short machine-stable code for the kind of change — e.g.
  /// 'DECISION_ISSUED', 'STATUS_CHANGED', 'ATTACHMENT_UPLOADED'.
  final String action;

  /// A human-readable Arabic sentence describing what happened — what's
  /// actually shown in the audit trail UI.
  final String summary;

  final String actorUid;

  /// Single-value before/after, where the change is naturally one value
  /// (e.g. a status code). Not a full field-by-field object diff — for a
  /// POC-scale audit trail, "what changed" in plain language (via
  /// [summary]) plus the one value that mattered is far more readable
  /// than a raw JSON diff, and it's what every write site in this project
  /// can supply without extra bookkeeping.
  final String? beforeValue;
  final String? afterValue;

  final DateTime? timestamp;

  factory AuditLogEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AuditLogEntry(
      id: doc.id,
      parcelId: d['parcelId'] as String? ?? '',
      entityType: d['entityType'] as String? ?? '',
      entityId: d['entityId'] as String? ?? '',
      action: d['action'] as String? ?? '',
      summary: d['summary'] as String? ?? '',
      actorUid: d['actorUid'] as String? ?? '',
      beforeValue: d['beforeValue'] as String?,
      afterValue: d['afterValue'] as String?,
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}