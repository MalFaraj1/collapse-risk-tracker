import 'package:cloud_firestore/cloud_firestore.dart';

/// (§5.1, FR-RST-4).
enum FundingCandidateStatus {
  proposed,
  selected,
  funded;

  String get label => switch (this) {
        FundingCandidateStatus.proposed => 'قيد الاقتراح',
        FundingCandidateStatus.selected => 'تم اختياره من جهة تمويل',
        FundingCandidateStatus.funded => 'تم التمويل بالكامل',
      };

  String get firestoreValue => name.toUpperCase();

  static FundingCandidateStatus fromFirestore(String? value) {
    return FundingCandidateStatus.values.firstWhere(
      (s) => s.firestoreValue == value,
      orElse: () => FundingCandidateStatus.proposed,
    );
  }
}

/// A building ready for restoration whose owner cannot bear the cost,
/// proposed to third-party funders (§5.1, §7.6a, FR-RST-4). Created
/// automatically — see AssessmentRepository.saveRestorationStudy — the
/// moment a restoration study is both engineering-approved and marked
/// CANNOT_BEAR; never created manually. Its document ID is the SAME as
/// the originating RestorationStudy's ID.
class FundingCandidate {
  const FundingCandidate({
    required this.id,
    required this.restorationStudyId,
    required this.caseId,
    required this.parcelId,
    this.funder,
    this.status = FundingCandidateStatus.proposed,
    this.proposedDate,
  });

  final String id;
  final String restorationStudyId;
  final String caseId;
  final String parcelId;
  final String? funder;
  final FundingCandidateStatus status;
  final DateTime? proposedDate;

  factory FundingCandidate.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return FundingCandidate(
      id: doc.id,
      restorationStudyId: data['restorationStudyId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      funder: data['funder'] as String?,
      status: FundingCandidateStatus.fromFirestore(data['status'] as String?),
      proposedDate: (data['proposedDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'restorationStudyId': restorationStudyId,
        'caseId': caseId,
        'parcelId': parcelId,
        'funder': funder,
        'status': status.firestoreValue,
        'proposedDate': FieldValue.serverTimestamp(),
      };
}