import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../models/audit_log_entry.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(firestore: ref.watch(firestoreProvider));
});

/// Live audit trail for one parcel, for Parcel Detail.
final parcelAuditLogProvider = StreamProvider.family<List<AuditLogEntry>, String>((ref, parcelId) {
  return ref.watch(auditLogRepositoryProvider).watchForParcel(parcelId);
});

/// FR-AUD-2/3, NFR-3: an immutable, append-only log of every state-
/// changing write.
///
/// IMPORTANT — the honest limitation of this implementation: FR-AUD-2
/// calls for entries written by "a trusted backend using the Admin SDK,"
/// which is what a real audit log needs for true tamper-evidence (no
/// client, however careful, can guarantee it never skips a log entry the
/// way a server-side trigger can). This project has no Cloud Function
/// infrastructure, so entries are written here, client-side, by the same
/// repositories that make the change — the same disclosed trade-off
/// already made for PDF generation elsewhere in this app. The Storage/
/// Firestore rules that make this possible intentionally trade the
/// stronger guarantee for a working POC-level log; the delivery message
/// that shipped this file explains exactly what changed and why.
class AuditLogRepository {
  AuditLogRepository({required this.firestore});
  final FirebaseFirestore firestore;

  /// Appends one entry to [batch] — ALWAYS call this inside the same
  /// atomic [WriteBatch] as the change it describes, never as a separate
  /// `.commit()`. That way a log entry can never exist without its
  /// change, or vice versa, even if the app crashes mid-write.
  void logInBatch(
    WriteBatch batch, {
    required String parcelId,
    required String entityType,
    required String entityId,
    required String action,
    required String summary,
    required String actorUid,
    String? beforeValue,
    String? afterValue,
  }) {
    final ref = firestore.collection(FirestorePaths.auditLogs).doc();
    batch.set(ref, {
      'parcelId': parcelId,
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'summary': summary,
      'actorUid': actorUid,
      'beforeValue': beforeValue,
      'afterValue': afterValue,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Every entry for one parcel, newest first (FR-AUD-3: "View the audit
  /// trail per parcel").
  Stream<List<AuditLogEntry>> watchForParcel(String parcelId) {
    return firestore
        .collection(FirestorePaths.auditLogs)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(AuditLogEntry.fromFirestore).toList());
  }
}