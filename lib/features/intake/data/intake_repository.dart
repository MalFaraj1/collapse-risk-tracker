import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../auth/auth_providers.dart';
import '../models/case.dart';
import '../models/complaint.dart';
import '../models/parcel.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final storageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final intakeRepositoryProvider = Provider<IntakeRepository>((ref) {
  return IntakeRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(storageProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// Everything the Intake screen needs to talk to Firestore/Storage.
///
/// Kept as a plain repository class rather than several scattered
/// StreamProviders, since intake is a short, linear sequence of one-off
/// writes — not a continuously-listened feed. Compare with
/// `dashboard_screen.dart`'s StreamProvider pattern, used where a live
/// feed actually matters.
class IntakeRepository {
  IntakeRepository({required this.firestore, required this.storage, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseAuth auth;

  /// FR-INT-2: look up a parcel by its composite natural key.
  Future<Parcel?> findParcel({required String parcelNo, required String cadastralZone}) async {
    final id = Parcel.buildId(parcelNo, cadastralZone);
    final doc = await firestore.collection(FirestorePaths.parcels).doc(id).get();
    return doc.exists ? Parcel.fromFirestore(doc) : null;
  }

  /// FR-INT-2: create a new parcel when the lookup above finds nothing.
  ///
  /// `buildingCount` defaults to 1 and is not something Intake asks the
  /// user for — a complaint is always about one specific building.
  /// `latitude`/`longitude` are optional — set only if the user dropped a
  /// pin on the map before submitting.
  Future<Parcel> createParcel({
    required String parcelNo,
    required String cadastralZone,
    required String address,
    int buildingCount = 1,
    double? latitude,
    double? longitude,
  }) async {
    final id = Parcel.buildId(parcelNo, cadastralZone);
    final ref = firestore.collection(FirestorePaths.parcels).doc(id);
    final parcel = Parcel(
      id: id,
      parcelNo: parcelNo.trim(),
      cadastralZone: cadastralZone.trim().toUpperCase(),
      address: address.trim(),
      buildingCount: buildingCount,
      status: ParcelStatus.newCase,
      latitude: latitude,
      longitude: longitude,
    );
    await ref.set(parcel.toFirestoreCreate());
    return parcel;
  }

  /// BR-3: every prior case ever opened on this parcel, most recent first —
  /// used to drive the case-status overview (open/closed) shown to the
  /// Call Center agent.
  ///
  /// NOTE: this query (equality on parcelId + orderBy openedAt) needs a
  /// Firestore composite index. The first time this runs, Firestore will
  /// throw an error containing a direct link that creates the required
  /// index in one click — that's expected on first run, not a bug.
  Future<List<Case>> getCaseHistory(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.cases)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('openedAt', descending: true)
        .get();
    return snap.docs.map(Case.fromFirestore).toList();
  }

  /// Every complaint ever logged on this parcel (across every case), most
  /// recent first — lets a Call Center agent see what was previously
  /// reported: narrative, photos, channel, contact info. Also what Intake
  /// uses to decide whether there's a pending, not-yet-triaged complaint
  /// that a new search should resume editing rather than duplicate — see
  /// `intake_screen.dart`'s `_searchParcel`.
  ///
  /// NOTE: like getCaseHistory, this needs a Firestore composite index
  /// (equality on parcelId + orderBy date). The first time this runs,
  /// Firestore will throw an error with a direct link that creates the
  /// required index in one click — expected on first run, not a bug.
  Future<List<Complaint>> getComplaintHistory(String parcelId) async {
    final snap = await firestore
        .collection(FirestorePaths.complaints)
        .where('parcelId', isEqualTo: parcelId)
        .orderBy('date', descending: true)
        .get();
    return snap.docs.map(Complaint.fromFirestore).toList();
  }

  /// BR-2, enforced atomically: reuses the parcel's open case if one
  /// exists, otherwise creates a new one and points the parcel at it.
  ///
  /// Runs as a Firestore transaction over the PARCEL document only
  /// (transactions can `get()` specific documents, not run queries) — the
  /// parcel's `openCaseId` field is what makes "is there already an open
  /// case?" answerable without a query, and is what prevents two
  /// complaints filed on the same parcel moments apart from each believing
  /// they're the first and creating two separate "open" cases.
  Future<String> getOrCreateOpenCaseId(String parcelId) {
    final parcelRef = firestore.collection(FirestorePaths.parcels).doc(parcelId);
    final newCaseRef = firestore.collection(FirestorePaths.cases).doc();

    return firestore.runTransaction<String>((transaction) async {
      final parcelSnap = await transaction.get(parcelRef);
      final existingOpenCaseId = parcelSnap.data()?['openCaseId'] as String?;
      if (existingOpenCaseId != null) return existingOpenCaseId;

      final newCase = Case(
        id: newCaseRef.id,
        parcelId: parcelId,
        status: CaseStatus.open,
        openedAt: DateTime.now(),
      );
      transaction.set(newCaseRef, newCase.toFirestoreCreate());
      transaction.update(parcelRef, {
        'openCaseId': newCaseRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return newCaseRef.id;
    });
  }

  /// Uploads every selected photo to Storage under `complaints/{complaintId}/`
  /// and returns their download URLs — matching exactly the path the
  /// Storage security rules authorize for Call Center/Engineering/Admin.
  ///
  /// Each filename includes a fresh Firestore auto-ID, not just a loop
  /// index — [updateComplaint] can call this a second time for the SAME
  /// complaint (to add more photos during an edit), and a plain
  /// `photo_0.jpg`/`photo_1.jpg` scheme would silently overwrite the
  /// originally uploaded files at those exact paths the second time
  /// around. A fresh unique segment per call makes that collision
  /// impossible regardless of how many times photos are added later.
  ///
  /// No client-side compression is applied. If large uploads become a
  /// problem in practice, add explicit compression before calling this —
  /// the Storage rules cap each file at 10MB regardless.
  Future<List<String>> _uploadPhotos(String complaintId, List<PlatformFile> photos) async {
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final file = photos[i];
      final bytes = file.bytes;
      if (bytes == null) continue; // shouldn't happen with withData: true when picking
      final ext = file.extension?.toLowerCase() ?? 'jpg';
      final unique = firestore.collection(FirestorePaths.complaints).doc().id;
      final ref = storage.ref('${FirestorePaths.complaints}/$complaintId/photo_${unique}_$i.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: _mimeTypeFor(ext)));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  String _mimeTypeFor(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// FR-INT-1: logs a NEW complaint, uploading any attached photos first
  /// so their URLs can be stored on the complaint document in the same
  /// write. Always creates a fresh document with a new auto-generated ID
  /// — call this only when logging a complaint for the first time.
  ///
  /// To edit an EXISTING, not-yet-triaged complaint, call
  /// [updateComplaint] instead. Never call this method again for an edit:
  /// it has no way to know an edit is "about" an existing document, so
  /// doing so creates a second, separate complaint — which is exactly
  /// what previously caused an edited complaint to show up twice in
  /// Dashboard's "awaiting triage" queue.
  Future<Complaint> submitComplaint({
    required String caseId,
    required String parcelId,
    required DateTime date,
    required ComplaintChannel channel,
    required String narrative,
    String? complainantContact,
    required List<PlatformFile> photos,
  }) async {
    final ref = firestore.collection(FirestorePaths.complaints).doc();
    final photoUrls = photos.isEmpty ? <String>[] : await _uploadPhotos(ref.id, photos);

    final complaint = Complaint(
      id: ref.id,
      caseId: caseId,
      parcelId: parcelId,
      date: date,
      channel: channel,
      narrative: narrative,
      complainantContact: complainantContact,
      photoUrls: photoUrls,
      createdByUid: auth.currentUser?.uid ?? '',
    );
    await ref.set(complaint.toFirestoreCreate());
    return complaint;
  }

  /// Updates an EXISTING complaint's editable fields in place — date,
  /// channel, narrative, contact. This is what Intake's "save" action
  /// calls when the search found a pending complaint to resume editing,
  /// instead of [submitComplaint].
  ///
  /// Uses Firestore's partial `.update()`, not `.set()` — combined with
  /// [Complaint.toFirestoreUpdate] leaving `photoUrls` out of its own map
  /// entirely, a complaint's EXISTING photos are left completely
  /// untouched by an edit, exactly as you described. [newPhotos], if any
  /// are passed, are uploaded and ADDED to that existing array via
  /// `FieldValue.arrayUnion` — appended, never replacing what's there.
  Future<void> updateComplaint({
    required String complaintId,
    required DateTime date,
    required ComplaintChannel channel,
    required String narrative,
    String? complainantContact,
    List<PlatformFile> newPhotos = const [],
  }) async {
    final newUrls = newPhotos.isEmpty ? <String>[] : await _uploadPhotos(complaintId, newPhotos);

    final updated = Complaint(
      id: complaintId,
      caseId: '', // not written by toFirestoreUpdate(); required only by the constructor
      parcelId: '', // not written by toFirestoreUpdate(); required only by the constructor
      date: date,
      channel: channel,
      narrative: narrative,
      complainantContact: complainantContact,
      photoUrls: const [],
      createdByUid: '', // not written by toFirestoreUpdate(); required only by the constructor
    );
    final updateMap = updated.toFirestoreUpdate();
    if (newUrls.isNotEmpty) {
      updateMap['photoUrls'] = FieldValue.arrayUnion(newUrls);
    }
    await firestore.collection(FirestorePaths.complaints).doc(complaintId).update(updateMap);
  }
}