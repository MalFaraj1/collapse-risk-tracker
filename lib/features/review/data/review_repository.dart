import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../admin/models/notice_template.dart';
import '../../audit/data/audit_log_repository.dart';
import '../../auth/auth_providers.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider, storageProvider;
import '../../intake/models/case.dart';
import '../models/decision.dart';
import '../models/notice.dart';
import '../models/report.dart';
import '../models/review.dart';


final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(storageProvider),
    auth: ref.watch(firebaseAuthProvider),
    auditLog: ref.watch(auditLogRepositoryProvider),
  );
});

/// Everything the Review & Decision screen needs to talk to Firestore/Storage.
class ReviewRepository {
  ReviewRepository({required this.firestore, required this.storage, required this.auth, required this.auditLog});

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseAuth auth;
  final AuditLogRepository auditLog;

  Future<Case?> getCase(String caseId) async {
    final doc = await firestore.collection(FirestorePaths.cases).doc(caseId).get();
    return doc.exists ? Case.fromFirestore(doc) : null;
  }

  /// The most recent report already recorded for this case, if any.
  Future<Report?> getLatestReportForCase(String caseId) async {
    final snap = await firestore
        .collection(FirestorePaths.reports)
        .where('caseId', isEqualTo: caseId)
        .orderBy('date', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Report.fromFirestore(snap.docs.first);
  }

  /// FR-REV-1: records the report that feeds this review. `source` is
  /// derived from the case's own triage outcome (dispatched-on-site vs
  /// referred-to-committee) — the person recording the report doesn't
  /// choose it freely, it reflects what actually happened (BR-5).
  Future<Report> createReport({
    required Case caseRecord,
    String? reference,
    required DateTime date,
    required String summary,
    required List<PlatformFile> media,
  }) async {
    final ref = firestore.collection(FirestorePaths.reports).doc();
    final mediaUrls = media.isEmpty ? <String>[] : await _uploadMedia(caseRecord.parcelId, ref.id, media);

    final source =
        caseRecord.dispatchedOnsiteAt != null ? ReportSource.urgentOnsite : ReportSource.committee;

    final report = Report(
      id: ref.id,
      caseId: caseRecord.id,
      parcelId: caseRecord.parcelId,
      source: source,
      reference: reference,
      date: date,
      summary: summary,
      mediaUrls: mediaUrls,
      createdByUid: auth.currentUser?.uid ?? '',
    );
    await ref.set(report.toFirestoreCreate());
    return report;
  }

  /// Uploads under the SAME Storage path the security rules already
  /// authorize for parcel attachments (`parcels/{parcelId}/attachments/`),
  /// so no new Storage rule is needed for photos/PDFs — only for video,
  /// which required a rules change; see the note shipped alongside this
  /// screen's delivery.
  Future<List<String>> _uploadMedia(String parcelId, String reportId, List<PlatformFile> media) async {
    final urls = <String>[];
    for (var i = 0; i < media.length; i++) {
      final file = media[i];
      final bytes = file.bytes;
      if (bytes == null) continue;
      final ext = file.extension?.toLowerCase() ?? 'jpg';
      final ref = storage.ref('${FirestorePaths.parcels}/$parcelId/attachments/report_${reportId}_$i.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: _mimeTypeFor(ext)));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  String _mimeTypeFor(String extension) {
    const imageExt = {'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg'};
    const videoExt = {'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm', 'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska', 'm4v': 'video/mp4'};
    return imageExt[extension] ?? videoExt[extension] ?? 'application/octet-stream';
  }

  /// BR-1's read side: does a prior SHORING_WARNING notice already exist
  /// on this parcel (system-issued OR legacy-imported)?
  ///
  /// IMPORTANT — this is a CLIENT-SIDE check only, used to decide what the
  /// UI shows (disable/enable the Confirmatory Shoring option). It is NOT
  /// real enforcement: a client could in principle be modified to skip
  /// this check and write a SHORING_CONFIRM decision directly. Real
  /// enforcement requires a Cloud Function triggered on `decisions`
  /// writes that re-checks this same condition server-side and rejects
  /// the write if it fails — that function does not exist yet in this
  /// project. Flagging this honestly rather than implying this client
  /// check is sufficient on its own.
  Future<bool> hasPriorShoringWarning(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.notices)
        .where('parcelId', isEqualTo: parcelId)
        .where('type', isEqualTo: DecisionAction.shoringWarning.firestoreValue)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<String?> _findLatestShoringWarningNoticeId(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.notices)
        .where('parcelId', isEqualTo: parcelId)
        .where('type', isEqualTo: DecisionAction.shoringWarning.firestoreValue)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  /// Saves a draft — a snapshot of the reviewer's in-progress choices,
  /// NOT a real decision. Does not create a Decision or Notice, and does
  /// not re-check BR-1, mirroring TriageRepository's draft behavior: a
  /// draft has no downstream side effects, only a submitted review does.
  Future<void> saveDraft({
    required Report report,
    required ReviewPriority priority,
  }) async {
    final ref = firestore.collection(FirestorePaths.reviews).doc();
    final review = Review(
      id: ref.id,
      reportId: report.id,
      caseId: report.caseId,
      parcelId: report.parcelId,
      reviewerUid: auth.currentUser?.uid ?? '',
      priority: priority,
      status: ReviewRecordStatus.draft,
    );
    await ref.set(review.toFirestoreCreate());
  }

  /// FR-REV-2, BR-1, BR-6: the real submission. Creates Review, Decision,
  /// and Notice together in one atomic [WriteBatch] — a Review is never
  /// left pointing at a Decision that failed to write, or vice versa.
  ///
  /// Re-checks BR-1 immediately before writing (not just at UI-render
  /// time) as defense in depth against a stale UI state — still a
  /// client-side check only, see [hasPriorShoringWarning].
  ///
  /// Returns the new Notice's ID, so the caller can navigate to
  /// `/notices/:id`.
  Future<String> submitReviewAndDecision({
    required Report report,
    required ReviewPriority priority,
    required DecisionAction action,
    required DateTime executionDate,
  }) async {
    if (action == DecisionAction.shoringConfirm) {
      final hasWarning = await hasPriorShoringWarning(report.parcelId);
      if (!hasWarning) {
        throw StateError('BR-1: لا يوجد إنذار تدعيم سابق على هذا العقار — لا يمكن إصدار تأكيدي بالتدعيم.');
      }
    }

    final reviewRef = firestore.collection(FirestorePaths.reviews).doc();
    final decisionRef = firestore.collection(FirestorePaths.decisions).doc();
    final noticeRef = firestore.collection(FirestorePaths.notices).doc();

    String? linkedWarningNoticeId;
    if (action == DecisionAction.shoringConfirm) {
      linkedWarningNoticeId = await _findLatestShoringWarningNoticeId(report.parcelId);
    }

    final uid = auth.currentUser?.uid ?? '';

    final review = Review(
      id: reviewRef.id,
      reportId: report.id,
      caseId: report.caseId,
      parcelId: report.parcelId,
      reviewerUid: uid,
      priority: priority,
      status: ReviewRecordStatus.submitted,
    );
    final decision = Decision(
      id: decisionRef.id,
      reviewId: reviewRef.id,
      caseId: report.caseId,
      parcelId: report.parcelId,
      action: action,
      executionDate: executionDate,
      createdByUid: uid,
    );
    // FR-ACT-2: the notice records WHICH version of its template it was
    // issued under, so it can always be re-rendered with that exact
    // wording even after an administrator publishes a newer version.
    final templateVersion = await NoticeTemplates.currentVersion(firestore, action);
    final notice = Notice(
      id: noticeRef.id,
      decisionId: decisionRef.id,
      caseId: report.caseId,
      parcelId: report.parcelId,
      type: action.firestoreValue,
      templateVersion: templateVersion.toString(),
      source: NoticeSource.system,
      linkedWarningNoticeId: linkedWarningNoticeId,
    );

    final batch = firestore.batch();
    batch.set(reviewRef, review.toFirestoreCreate());
    batch.set(decisionRef, decision.toFirestoreCreate());
    batch.set(noticeRef, notice.toFirestoreCreate());

    // Denormalized onto the Case so Dashboard can list "cases awaiting
    // review" — triaged but not yet decided — with a plain equality
    // query; see the doc comment on Case.reviewed.
    final caseRef = firestore.collection(FirestorePaths.cases).doc(report.caseId);
    batch.update(caseRef, {'reviewed': true, 'updatedAt': FieldValue.serverTimestamp()});

    // Parcel-level status transition (Appendix B).
    final parcelRef = firestore.collection(FirestorePaths.parcels).doc(report.parcelId);
    final nextStatus = action == DecisionAction.evacuation ? ParcelStatus.evacuation : ParcelStatus.awaitingCompliance;
    batch.update(parcelRef, {'status': nextStatus.firestoreValue, 'updatedAt': FieldValue.serverTimestamp()});

    auditLog.logInBatch(
      batch,
      parcelId: report.parcelId,
      entityType: 'DECISION',
      entityId: decisionRef.id,
      action: 'DECISION_ISSUED',
      summary: 'صدر قرار: ${action.noticeTitle} — بمهلة تنفيذ حتى ${_fmtDate(executionDate)}',
      actorUid: uid,
      afterValue: nextStatus.firestoreValue,
    );

    await batch.commit();

    return noticeRef.id;
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
