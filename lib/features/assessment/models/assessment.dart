import 'package:cloud_firestore/cloud_firestore.dart';

/// Why this case entered external assessment in the first place (BR-8).
enum AssessmentTrigger {
  evacuation,
  nonCompliedWarning;

  String get label => this == AssessmentTrigger.evacuation ? 'إخلاء المبنى (BR-8)' : 'عدم الامتثال لإنذار سابق (BR-8)';
  String get firestoreValue => this == AssessmentTrigger.evacuation ? 'EVACUATION' : 'NON_COMPLIED_WARNING';

  static AssessmentTrigger fromFirestore(String? value) =>
      value == 'EVACUATION' ? AssessmentTrigger.evacuation : AssessmentTrigger.nonCompliedWarning;
}

/// The external firm's opinion (§6.4, §7.6, FR-ASM-2/3).
enum ExternalOpinion {
  restore,
  demolish;

  String get label => this == ExternalOpinion.restore ? 'ترميم (RESTORE)' : 'هدم (DEMOLISH)';
  String get subtitle => this == ExternalOpinion.restore
      ? 'المبنى قابل للترميم وفق دراسة هندسية'
      : 'المبنى غير قابل للترميم — يحال إلى مسار الهدم';
  String get firestoreValue => this == ExternalOpinion.restore ? 'RESTORE' : 'DEMOLISH';

  static ExternalOpinion? fromFirestore(String? value) {
    if (value == null) return null;
    return value == 'RESTORE' ? ExternalOpinion.restore : ExternalOpinion.demolish;
  }
}

/// External evaluation by the external engineering firm (Khatib & Alami)
/// (§6.4, §7.6, BR-8, FR-ASM-1..3). One per originating decision — its
/// Firestore document ID is deliberately the SAME as the Decision's ID,
/// the same 1:1 technique used for [EvacuationExecution].
///
/// Created automatically (empty, pending) the moment BR-8's trigger
/// condition is met — see the trigger calls added to EvacuationRepository
/// and SiteVisitRepository. Engineering fills in the order/opinion fields
/// afterward on this screen; nothing here pretends to actually contact the
/// external firm, which is explicitly out of this POC's scope (§2.2).
class Assessment {
  const Assessment({
    required this.id,
    required this.decisionId,
    required this.caseId,
    required this.parcelId,
    required this.triggerReason,
    this.orderSentDate,
    this.opinionReceivedDate,
    this.opinion,
    this.createdAt,
  });

  final String id;
  final String decisionId;
  final String caseId;
  final String parcelId;
  final AssessmentTrigger triggerReason;
  final DateTime? orderSentDate;
  final DateTime? opinionReceivedDate;
  final ExternalOpinion? opinion;
  final DateTime? createdAt;

  factory Assessment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Assessment(
      id: doc.id,
      decisionId: data['decisionId'] as String? ?? '',
      caseId: data['caseId'] as String? ?? '',
      parcelId: data['parcelId'] as String? ?? '',
      triggerReason: AssessmentTrigger.fromFirestore(data['triggerReason'] as String?),
      orderSentDate: (data['orderSentDate'] as Timestamp?)?.toDate(),
      opinionReceivedDate: (data['opinionReceivedDate'] as Timestamp?)?.toDate(),
      opinion: ExternalOpinion.fromFirestore(data['opinion'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreInitial() => {
        'decisionId': decisionId,
        'caseId': caseId,
        'parcelId': parcelId,
        'triggerReason': triggerReason.firestoreValue,
        'orderSentDate': null,
        'opinionReceivedDate': null,
        'opinion': null,
        'createdAt': FieldValue.serverTimestamp(),
      };
}