import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Parcel-level status, mirroring the state machine in the spec (§6.7,
/// Appendix B / docs/diagrams/parcel-state-machine.jpeg).
///
/// Each status carries its own fixed color and Arabic label so it renders
/// identically everywhere it appears (dashboard, parcel list, timeline) —
/// see [StatusBadge] in core/widgets, which consumes this directly.
enum ParcelStatus {
  newCase,
  triage,
  awaitingCommittee,
  urgentOnsite,
  underReview,
  evacuation,
  awaitingCompliance,
  inAssessment,
  restorationOrdered,
  fundingPending,
  demolitionPending,
  demolished,
  closedSafe;

  String get label => switch (this) {
        ParcelStatus.newCase => 'جديد',
        ParcelStatus.triage => 'قيد الفرز',
        ParcelStatus.awaitingCommittee => 'بانتظار اللجنة',
        ParcelStatus.urgentOnsite => 'معاينة عاجلة',
        ParcelStatus.underReview => 'قيد المراجعة',
        ParcelStatus.evacuation => 'إخلاء',
        ParcelStatus.awaitingCompliance => 'بانتظار الامتثال',
        ParcelStatus.inAssessment => 'قيد التقييم الخارجي',
        ParcelStatus.restorationOrdered => 'أمر ترميم صادر',
        ParcelStatus.fundingPending => 'بانتظار التمويل',
        ParcelStatus.demolitionPending => 'بانتظار الهدم',
        ParcelStatus.demolished => 'مهدوم',
        ParcelStatus.closedSafe => 'مغلق — آمن',
      };

  Color get color => switch (this) {
        ParcelStatus.newCase => AppColors.info,
        ParcelStatus.triage => AppColors.info,
        ParcelStatus.awaitingCommittee => AppColors.warning,
        ParcelStatus.urgentOnsite => AppColors.warning,
        ParcelStatus.underReview => AppColors.info,
        ParcelStatus.evacuation => AppColors.danger,
        ParcelStatus.awaitingCompliance => AppColors.warning,
        ParcelStatus.inAssessment => AppColors.purple,
        ParcelStatus.restorationOrdered => AppColors.info,
        ParcelStatus.fundingPending => AppColors.warning,
        ParcelStatus.demolitionPending => AppColors.danger,
        ParcelStatus.demolished => AppColors.neutral,
        ParcelStatus.closedSafe => AppColors.success,
      };

  Color get backgroundColor => switch (this) {
        ParcelStatus.newCase => AppColors.infoBg,
        ParcelStatus.triage => AppColors.infoBg,
        ParcelStatus.awaitingCommittee => AppColors.warningBg,
        ParcelStatus.urgentOnsite => AppColors.warningBg,
        ParcelStatus.underReview => AppColors.infoBg,
        ParcelStatus.evacuation => AppColors.dangerBg,
        ParcelStatus.awaitingCompliance => AppColors.warningBg,
        ParcelStatus.inAssessment => AppColors.purpleBg,
        ParcelStatus.restorationOrdered => AppColors.infoBg,
        ParcelStatus.fundingPending => AppColors.warningBg,
        ParcelStatus.demolitionPending => AppColors.dangerBg,
        ParcelStatus.demolished => AppColors.neutralBg,
        ParcelStatus.closedSafe => AppColors.successBg,
      };

  Color get borderColor => switch (this) {
        ParcelStatus.newCase => AppColors.infoBorder,
        ParcelStatus.triage => AppColors.infoBorder,
        ParcelStatus.awaitingCommittee => AppColors.warningBorder,
        ParcelStatus.urgentOnsite => AppColors.warningBorder,
        ParcelStatus.underReview => AppColors.infoBorder,
        ParcelStatus.evacuation => AppColors.dangerBorder,
        ParcelStatus.awaitingCompliance => AppColors.warningBorder,
        ParcelStatus.inAssessment => AppColors.purpleBorder,
        ParcelStatus.restorationOrdered => AppColors.infoBorder,
        ParcelStatus.fundingPending => AppColors.warningBorder,
        ParcelStatus.demolitionPending => AppColors.dangerBorder,
        ParcelStatus.demolished => AppColors.neutralBorder,
        ParcelStatus.closedSafe => AppColors.successBorder,
      };

  /// Firestore stores the status as this exact string — keep in sync with
  /// whatever your Cloud Functions / write paths use.
  String get firestoreValue => name;

  static ParcelStatus fromFirestore(String value) {
    return ParcelStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ParcelStatus.newCase,
    );
  }
}
