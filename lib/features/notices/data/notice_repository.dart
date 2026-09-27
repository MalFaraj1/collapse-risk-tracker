import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider, storageProvider;
import '../../intake/models/parcel.dart';
import '../../review/models/decision.dart';
import '../../review/models/notice.dart';

final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  return NoticeRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(storageProvider),
  );
});

/// Everything the Notice Preview screen needs to talk to Firestore and
/// Storage.
class NoticeRepository {
  NoticeRepository({required this.firestore, required this.storage});

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  Future<Notice?> getNotice(String noticeId) async {
    final doc = await firestore.collection(FirestorePaths.notices).doc(noticeId).get();
    return doc.exists ? Notice.fromFirestore(doc) : null;
  }

  Future<Decision?> getDecision(String decisionId) async {
    final doc = await firestore.collection(FirestorePaths.decisions).doc(decisionId).get();
    return doc.exists ? Decision.fromFirestore(doc) : null;
  }

  Future<Parcel?> getParcel(String parcelId) async {
    final doc = await firestore.collection(FirestorePaths.parcels).doc(parcelId).get();
    return doc.exists ? Parcel.fromFirestore(doc) : null;
  }

  /// Uploads a freshly-generated PDF for this notice and permanently
  /// records its URL — the actual completion of FR-ACT-2's "generated and
  /// stored" requirement, done here on first request rather than by a
  /// Cloud Function (see the doc comment on NoticePreviewScreen for why).
  /// Idempotent in effect: once `pdfUrl` is set, every later viewer reads
  /// the same cached file instead of regenerating it.
  Future<String> savePdf(String noticeId, Uint8List pdfBytes) async {
    final ref = storage.ref('notices/$noticeId/notice.pdf');
    await ref.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
    await firestore.collection(FirestorePaths.notices).doc(noticeId).update({'pdfUrl': url});
    return url;
  }
}