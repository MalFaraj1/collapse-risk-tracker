import 'package:cloud_firestore/cloud_firestore.dart';

import '../../review/models/decision.dart';

/// One spreadsheet row after parsing and validation, BEFORE anything is
/// written. Carries both what the file literally said (`*Raw`, shown back
/// to the reviewer) and what it was understood as (`parcelNo`, `zone`,
/// `type`, `date`); [error] is set when any of the four minimum fields
/// (FR-IMP-1 / OQ-4) is missing or unintelligible.
class ParsedImportRow {
  const ParsedImportRow({
    required this.rowNumber,
    required this.parcelNoRaw,
    required this.zoneRaw,
    required this.typeRaw,
    required this.dateRaw,
    this.reference,
    this.parcelNo,
    this.zone,
    this.type,
    this.date,
    this.error,
  });

  final int rowNumber;
  final String parcelNoRaw;
  final String zoneRaw;
  final String typeRaw;
  final String dateRaw;
  final String? reference;

  final String? parcelNo;
  final String? zone;
  final DecisionAction? type;
  final DateTime? date;
  final String? error;

  bool get isValid => error == null;
}

/// Outcome of importing one row (FR-IMP-2).
enum ImportRowStatus {
  /// The parcel already existed — the notice was attached to it.
  matched,

  /// The parcel didn't exist, so it was created, then the notice attached.
  created,

  /// A minimum field was missing/invalid — nothing was written except this
  /// row's record; it waits for manual review.
  unmatched,

  /// Was unmatched; an administrator fixed it and it was then imported.
  resolved;

  String get firestoreValue => name.toUpperCase();

  String get label => switch (this) {
        ImportRowStatus.matched => 'مطابق',
        ImportRowStatus.created => 'مطابق (عقار جديد)',
        ImportRowStatus.unmatched => 'غير مطابق',
        ImportRowStatus.resolved => 'تمت المراجعة',
      };

  bool get isOk => this != ImportRowStatus.unmatched;

  static ImportRowStatus fromFirestore(String? v) => ImportRowStatus.values.firstWhere(
        (s) => s.firestoreValue == v,
        orElse: () => ImportRowStatus.unmatched,
      );
}

/// A whole uploaded file's import (`importBatches/{id}`).
class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.batchNo,
    required this.fileName,
    required this.totalRows,
    required this.matchedCount,
    required this.createdParcels,
    required this.unmatchedCount,
    required this.resolvedCount,
    this.createdAt,
    this.sourceFileUrl,
  });

  final String id;
  final int batchNo;
  final String fileName;
  final int totalRows;

  /// Rows matched automatically — includes those that needed a new parcel.
  final int matchedCount;
  final int createdParcels;

  /// Rows still waiting for manual review.
  final int unmatchedCount;

  /// Rows that were unmatched and have since been fixed by hand.
  final int resolvedCount;
  final DateTime? createdAt;

  /// The original uploaded spreadsheet, kept in Storage for audit/reference
  /// (`imports/{batchId}/{fileName}`) — null if the upload failed or this
  /// batch predates the feature; the import itself never depends on it.
  final String? sourceFileUrl;

  String get label => 'BATCH-${batchNo.toString().padLeft(3, '0')}';

  factory ImportBatch.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    int i(String k) => (d[k] as num?)?.toInt() ?? 0;
    return ImportBatch(
      id: doc.id,
      batchNo: i('batchNo'),
      fileName: d['fileName'] as String? ?? '',
      totalRows: i('totalRows'),
      matchedCount: i('matchedCount'),
      createdParcels: i('createdParcels'),
      unmatchedCount: i('unmatchedCount'),
      resolvedCount: i('resolvedCount'),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      sourceFileUrl: d['sourceFileUrl'] as String?,
    );
  }
}

/// One stored row of a batch (`importRows/{id}`).
class ImportRow {
  const ImportRow({
    required this.id,
    required this.batchId,
    required this.rowNumber,
    required this.parcelNoRaw,
    required this.zoneRaw,
    required this.typeRaw,
    required this.dateRaw,
    this.reference,
    required this.status,
    this.errorReason,
    this.warningType,
    this.warningDate,
    this.parcelId,
    this.noticeId,
    this.note,
  });

  final String id;
  final String batchId;
  final int rowNumber;
  final String parcelNoRaw;
  final String zoneRaw;
  final String typeRaw;
  final String dateRaw;
  final String? reference;
  final ImportRowStatus status;
  final String? errorReason;
  final DecisionAction? warningType;
  final DateTime? warningDate;
  final String? parcelId;
  final String? noticeId;
  final String? note;

  factory ImportRow.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final typeValue = d['warningType'] as String?;
    return ImportRow(
      id: doc.id,
      batchId: d['batchId'] as String? ?? '',
      rowNumber: (d['rowNumber'] as num?)?.toInt() ?? 0,
      parcelNoRaw: d['parcelNoRaw'] as String? ?? '',
      zoneRaw: d['zoneRaw'] as String? ?? '',
      typeRaw: d['typeRaw'] as String? ?? '',
      dateRaw: d['dateRaw'] as String? ?? '',
      reference: d['reference'] as String?,
      status: ImportRowStatus.fromFirestore(d['status'] as String?),
      errorReason: d['errorReason'] as String?,
      warningType: typeValue == null ? null : DecisionAction.fromFirestore(typeValue),
      warningDate: (d['warningDate'] as Timestamp?)?.toDate(),
      parcelId: d['parcelId'] as String?,
      noticeId: d['noticeId'] as String?,
      note: d['note'] as String?,
    );
  }
}