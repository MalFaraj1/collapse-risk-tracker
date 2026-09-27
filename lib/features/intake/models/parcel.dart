import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/parcel_status.dart';

/// Minimal Parcel model, owned by the Intake feature for now.
///
/// NOTE: a separate, richer Parcel model exists under
/// `features/parcels/models/` from earlier, currently-paused work on the
/// parcel registry (neighborhoods, building condition tracking, location).
/// Both would read/write the same underlying Firestore `parcels`
/// collection. A document created here will simply have null/missing
/// values for fields the other model expects — harmless for now since
/// those fields are nullable there, but the two definitions should be
/// reconciled into one shared model (likely under `core/models/`) once
/// parcels-feature work resumes, rather than left as two competing
/// definitions long-term.
class Parcel {
  const Parcel({
    required this.id,
    required this.parcelNo,
    required this.cadastralZone,
    required this.address,
    required this.buildingCount,
    required this.status,
    this.openCaseId,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.updatedAt,
  });

  final String id; // Firestore document ID — see buildId()
  final String parcelNo;
  final String cadastralZone;
  final String address;
  final int buildingCount;
  final ParcelStatus status;

  /// Denormalized pointer to this parcel's currently OPEN case, or null.
  /// This is what makes Business Rule BR-2 enforceable inside a plain
  /// Firestore transaction: a transaction can only `get()` specific
  /// document references, not run a query — so instead of querying
  /// `cases` for an open one on every complaint, we keep a pointer to it
  /// right on the parcel and update both atomically together. See
  /// [IntakeRepository.getOrCreateOpenCaseId] in `../data/intake_repository.dart`.
  final String? openCaseId;

  /// Nullable — not every parcel has a pinned location yet. Set once, at
  /// creation, by dropping a pin on the map during Intake; Intake doesn't
  /// support editing an existing parcel's location, same as it doesn't
  /// support editing its address (see the screen's doc comments).
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministic document ID built from the composite natural key
  /// (parcel_no, cadastral_zone) — this is what guarantees uniqueness
  /// without a query-then-write race condition: Firestore document IDs
  /// are inherently unique, so two parcels can never collide on this pair.
  static String buildId(String parcelNo, String cadastralZone) {
    String sanitize(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'[/\s]+'), '-');
    return 'PARCEL-${sanitize(parcelNo)}-${sanitize(cadastralZone)}';
  }

  factory Parcel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Parcel(
      id: doc.id,
      parcelNo: data['parcelNo'] as String? ?? '',
      cadastralZone: data['cadastralZone'] as String? ?? '',
      address: data['address'] as String? ?? '',
      buildingCount: (data['buildingCount'] as num?)?.toInt() ?? 1,
      status: ParcelStatus.fromFirestore(data['status'] as String? ?? 'newCase'),
      openCaseId: data['openCaseId'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'parcelNo': parcelNo,
        'cadastralZone': cadastralZone,
        'address': address,
        'buildingCount': buildingCount,
        'status': status.firestoreValue,
        'openCaseId': openCaseId,
        'latitude': latitude,
        'longitude': longitude,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}