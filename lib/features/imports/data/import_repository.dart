import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/parcel_status.dart';
import '../../auth/auth_providers.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider, storageProvider;
import '../../intake/models/parcel.dart';
import '../../review/models/decision.dart';
import '../models/import_models.dart';

final importRepositoryProvider = Provider<ImportRepository>((ref) {
  return ImportRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    storage: ref.watch(storageProvider),
  );
});

/// Every import batch, newest first.
final importBatchesProvider = StreamProvider<List<ImportBatch>>((ref) {
  return ref.watch(importRepositoryProvider).watchBatches();
});

/// The stored rows of one batch, in file order.
final importRowsProvider = StreamProvider.family<List<ImportRow>, String>((ref, batchId) {
  return ref.watch(importRepositoryProvider).watchRows(batchId);
});

/// Legacy-warning import (§7.9, FR-IMP-1..3).
///
/// Each valid row becomes a [Notice]-shaped document with
/// `source: IMPORTED` and the warning's TYPE and ORIGINAL DATE, attached
/// to its parcel (created if absent). Because ReviewRepository's BR-1
/// check simply asks "does a SHORING_WARNING notice exist on this
/// parcel?", an imported shoring warning satisfies BR-1 with no change to
/// that rule (FR-IMP-3) — and its `createdAt` is the legacy date, so it
/// sorts correctly among newer system-issued notices.
class ImportRepository {
  ImportRepository({required this.firestore, required this.auth, required this.storage});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  Stream<List<ImportBatch>> watchBatches({int limit = 30}) {
    return firestore
        .collection(FirestorePaths.importBatches)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ImportBatch.fromFirestore).toList());
  }

  /// Filtered by a single equality and sorted here, not in the query — a
  /// `where` + `orderBy` on different fields would need a composite index.
  Stream<List<ImportRow>> watchRows(String batchId) {
    return firestore
        .collection(FirestorePaths.importRows)
        .where('batchId', isEqualTo: batchId)
        .snapshots()
        .map((snap) {
      final rows = snap.docs.map(ImportRow.fromFirestore).toList();
      rows.sort((a, b) => a.rowNumber.compareTo(b.rowNumber));
      return rows;
    });
  }

  Map<String, dynamic> _noticeMap({
    required String parcelId,
    required DecisionAction type,
    required DateTime date,
    required String? reference,
    required String batchId,
    required String rowId,
  }) =>
      {
        'decisionId': '',
        'caseId': '',
        'parcelId': parcelId,
        'type': type.firestoreValue,
        'templateVersion': 'legacy',
        'source': 'IMPORTED',
        'linkedWarningNoticeId': null,
        'pdfUrl': null,
        'postedDate': null,
        'createdAt': Timestamp.fromDate(date),
        'importedAt': FieldValue.serverTimestamp(),
        'importBatchId': batchId,
        'importRowId': rowId,
        'reference': reference,
      };

  Parcel _newParcel(String id, String parcelNo, String zone) => Parcel(
        id: id,
        parcelNo: parcelNo.trim(),
        cadastralZone: zone.trim().toUpperCase(),
        address: '', // not part of a legacy warning record — completed later
        buildingCount: 1,
        status: ParcelStatus.newCase,
      );

  /// Uploads the raw spreadsheet to Storage for audit/reference
  /// (`imports/{batchId}/{fileName}`, admin-only, matching the deployed
  /// Storage rules) — kept separate from the import's actual data path,
  /// which is parsed entirely client-side from [rows]. Never blocks or
  /// fails the import itself: a Storage hiccup here just means the batch
  /// has no "original file" link, not that the import didn't happen.
  Future<String?> _uploadSourceFile(String batchId, String fileName, Uint8List bytes) async {
    try {
      final ext = fileName.toLowerCase().endsWith('.csv') ? 'csv' : 'xlsx';
      final contentType = ext == 'csv'
          ? 'text/csv'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      // Storage path is literally "imports/{batchId}/{fileName}" per the
      // deployed Storage rules — a deliberately different top-level
      // segment from the "importBatches" Firestore collection, so this is
      // NOT a typo for FirestorePaths.importBatches.
      final ref = storage.ref('imports/$batchId/$fileName');
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  /// Imports a whole parsed file as one batch (FR-IMP-1/2).
  ///
  /// Two passes: first PLAN every row (which parcels exist, which rows
  /// duplicate an earlier import), so the batch's summary counts are known
  /// before anything is written; then WRITE in chunks under Firestore's
  /// 500-operation batch limit. [sourceBytes] is optional — the import
  /// still runs fully from [rows] if it's omitted; it only enables saving
  /// the original file alongside the batch.
  Future<ImportBatch> importBatch({
    required String fileName,
    required List<ParsedImportRow> rows,
    Uint8List? sourceBytes,
  }) async {
    final uid = auth.currentUser?.uid ?? '';
    final existingBatches = await firestore.collection(FirestorePaths.importBatches).count().get();
    final batchNo = (existingBatches.count ?? 0) + 1;
    final batchRef = firestore.collection(FirestorePaths.importBatches).doc();
    final sourceFileUrl = sourceBytes == null ? null : await _uploadSourceFile(batchRef.id, fileName, sourceBytes);

    // ---- Pass 1: plan ----------------------------------------------------------
    final valid = rows.where((r) => r.isValid).toList();
    final parcelIds = {for (final r in valid) Parcel.buildId(r.parcelNo!, r.zone!)};

    final existingParcels = <String>{};
    final legacyKeysByParcel = <String, Set<String>>{};
    await Future.wait(parcelIds.map((id) async {
      final parcelDoc = await firestore.collection(FirestorePaths.parcels).doc(id).get();
      if (parcelDoc.exists) existingParcels.add(id);
      // Existing IMPORTED notices on this parcel, to avoid re-importing the
      // same warning when a file is uploaded twice.
      final notices = await firestore.collection(FirestorePaths.notices).where('parcelId', isEqualTo: id).get();
      legacyKeysByParcel[id] = {
        for (final n in notices.docs)
          if (n.data()['source'] == 'IMPORTED')
            _dedupeKey(n.data()['type'] as String? ?? '', (n.data()['createdAt'] as Timestamp?)?.toDate(), n.data()['reference'] as String?),
      };
    }));

    final planned = <_PlannedRow>[];
    final createdParcelIds = <String>{};
    var matched = 0, created = 0, unmatched = 0;

    for (final r in rows) {
      final rowRef = firestore.collection(FirestorePaths.importRows).doc();
      if (!r.isValid) {
        unmatched++;
        planned.add(_PlannedRow(r, rowRef, ImportRowStatus.unmatched));
        continue;
      }
      final parcelId = Parcel.buildId(r.parcelNo!, r.zone!);
      final needsParcel = !existingParcels.contains(parcelId) && !createdParcelIds.contains(parcelId);
      if (needsParcel) createdParcelIds.add(parcelId);

      final key = _dedupeKey(r.type!.firestoreValue, r.date, r.reference);
      final seen = legacyKeysByParcel.putIfAbsent(parcelId, () => <String>{});
      final duplicate = seen.contains(key);
      seen.add(key);

      matched++;
      if (needsParcel) created++;
      planned.add(_PlannedRow(
        r,
        rowRef,
        needsParcel ? ImportRowStatus.created : ImportRowStatus.matched,
        parcelId: parcelId,
        createParcel: needsParcel,
        noticeRef: duplicate ? null : firestore.collection(FirestorePaths.notices).doc(),
        note: duplicate ? 'إنذار مطابق مستورد سابقًا — لم يُكرَّر' : null,
      ));
    }

    // ---- Pass 2: write ---------------------------------------------------------
    final summary = {
      'batchNo': batchNo,
      'fileName': fileName,
      'uploadedByUid': uid,
      'totalRows': rows.length,
      'matchedCount': matched,
      'createdParcels': created,
      'unmatchedCount': unmatched,
      'resolvedCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'sourceFileUrl': sourceFileUrl,
    };

    var batch = firestore.batch();
    var ops = 0;
    batch.set(batchRef, summary);
    ops++;

    Future<void> flush({bool force = false}) async {
      if (ops >= 400 || (force && ops > 0)) {
        await batch.commit();
        batch = firestore.batch();
        ops = 0;
      }
    }

    for (final p in planned) {
      final r = p.row;
      if (p.createParcel) {
        batch.set(firestore.collection(FirestorePaths.parcels).doc(p.parcelId), _newParcel(p.parcelId!, r.parcelNo!, r.zone!).toFirestoreCreate());
        ops++;
      }
      if (p.noticeRef != null) {
        batch.set(
          p.noticeRef!,
          _noticeMap(parcelId: p.parcelId!, type: r.type!, date: r.date!, reference: r.reference, batchId: batchRef.id, rowId: p.rowRef.id),
        );
        ops++;
      }
      batch.set(p.rowRef, {
        'batchId': batchRef.id,
        'rowNumber': r.rowNumber,
        'parcelNoRaw': r.parcelNoRaw,
        'zoneRaw': r.zoneRaw,
        'typeRaw': r.typeRaw,
        'dateRaw': r.dateRaw,
        'reference': r.reference,
        'status': p.status.firestoreValue,
        'errorReason': r.error,
        'warningType': r.type?.firestoreValue,
        'warningDate': r.date == null ? null : Timestamp.fromDate(r.date!),
        'parcelId': p.parcelId,
        'noticeId': p.noticeRef?.id,
        'note': p.note,
        'createdAt': FieldValue.serverTimestamp(),
      });
      ops++;
      await flush();
    }
    await flush(force: true);

    return ImportBatch(
      id: batchRef.id,
      batchNo: batchNo,
      fileName: fileName,
      totalRows: rows.length,
      matchedCount: matched,
      createdParcels: created,
      unmatchedCount: unmatched,
      resolvedCount: 0,
      sourceFileUrl: sourceFileUrl,
    );
  }

  String _dedupeKey(String type, DateTime? date, String? reference) {
    final d = date == null ? '' : '${date.year}-${date.month}-${date.day}';
    return '$type|$d|${(reference ?? '').trim()}';
  }

  /// Manual review of an unmatched row (FR-IMP-2): the administrator
  /// supplies corrected values, and the row is imported exactly like an
  /// automatic one. The row record, the batch's counters, the parcel (if
  /// new) and the notice are all written in ONE atomic batch.
  Future<void> resolveRow(
    ImportRow row, {
    required String parcelNo,
    required String zone,
    required DecisionAction type,
    required DateTime date,
    String? reference,
  }) async {
    if (row.status != ImportRowStatus.unmatched) throw StateError('هذا الصف ليس بحاجة إلى مراجعة.');
    if (parcelNo.trim().isEmpty || zone.trim().isEmpty) throw StateError('رقم العقار والمنطقة العقارية مطلوبان.');

    final parcelId = Parcel.buildId(parcelNo, zone);
    final parcelRef = firestore.collection(FirestorePaths.parcels).doc(parcelId);
    final parcelExists = (await parcelRef.get()).exists;
    final noticeRef = firestore.collection(FirestorePaths.notices).doc();
    final ref = reference == null || reference.trim().isEmpty ? null : reference.trim();

    final batch = firestore.batch();
    if (!parcelExists) batch.set(parcelRef, _newParcel(parcelId, parcelNo, zone).toFirestoreCreate());
    batch.set(noticeRef, _noticeMap(parcelId: parcelId, type: type, date: date, reference: ref, batchId: row.batchId, rowId: row.id));
    batch.update(firestore.collection(FirestorePaths.importRows).doc(row.id), {
      'status': ImportRowStatus.resolved.firestoreValue,
      'parcelNoRaw': parcelNo.trim(),
      'zoneRaw': zone.trim(),
      'warningType': type.firestoreValue,
      'warningDate': Timestamp.fromDate(date),
      'reference': ref,
      'errorReason': null,
      'parcelId': parcelId,
      'noticeId': noticeRef.id,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByUid': auth.currentUser?.uid ?? '',
    });
    batch.update(firestore.collection(FirestorePaths.importBatches).doc(row.batchId), {
      'unmatchedCount': FieldValue.increment(-1),
      'resolvedCount': FieldValue.increment(1),
      if (!parcelExists) 'createdParcels': FieldValue.increment(1),
    });
    await batch.commit();
  }
}

class _PlannedRow {
  _PlannedRow(
    this.row,
    this.rowRef,
    this.status, {
    this.parcelId,
    this.createParcel = false,
    this.noticeRef,
    this.note,
  });

  final ParsedImportRow row;
  final DocumentReference<Map<String, dynamic>> rowRef;
  final ImportRowStatus status;
  final String? parcelId;
  final bool createParcel;
  final DocumentReference<Map<String, dynamic>>? noticeRef;
  final String? note;
}