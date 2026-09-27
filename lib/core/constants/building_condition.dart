import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// The physical/structural condition of a building, as assessed by
/// Engineering after reviewing it on-site.
///
/// This is deliberately a **separate concept from [ParcelStatus]**:
/// `ParcelStatus` tracks where a case is in the municipal *workflow* (NEW,
/// UNDER_REVIEW, CLOSED_SAFE, ...); `BuildingCondition` tracks the
/// *physical* state of the structure itself, independent of whether any
/// case is currently open on it. A building can be CRITICAL condition with
/// no open case yet (nobody has filed a complaint), or SAFE condition with
/// a case open for an unrelated reason.
///
/// **Access control: only Engineering and Admin may set or change this
/// value.** This is enforced in two places, and must stay true in both:
///   1. The UI — the "تحديث الحالة" button on Parcel Detail is only shown
///      to those two roles (see `parcel_detail_screen.dart`).
///   2. The Firestore security rules — the `parcels` collection's `update`
///      rule specifically blocks Call Center from touching the
///      `condition`/`conditionSetByUid`/`conditionSetByName`/`conditionSetAt`
///      fields, even though Call Center can update other parcel fields.
///      See the updated `firestore.rules` in docs/ or the delivery message
///      this file shipped with. The UI check alone is not enforcement.
enum BuildingCondition {
  safe,
  minorDamage,
  atRisk,
  critical;

  String get label => switch (this) {
        BuildingCondition.safe => 'سليم',
        BuildingCondition.minorDamage => 'أضرار طفيفة',
        BuildingCondition.atRisk => 'آيل للسقوط',
        BuildingCondition.critical => 'خطر انهيار وشيك',
      };

  String get description => switch (this) {
        BuildingCondition.safe => 'لا توجد مؤشرات خطر إنشائي عند المعاينة.',
        BuildingCondition.minorDamage => 'أضرار سطحية لا تستدعي إجراءً عاجلاً، تُتابَع دوريًا.',
        BuildingCondition.atRisk => 'مؤشرات إنشائية تستدعي متابعة وإجراءً تنظيميًا.',
        BuildingCondition.critical => 'خطر انهيار وشيك — يستدعي تقييمًا عاجلاً لاحتمال الإخلاء.',
      };

  Color get color => switch (this) {
        BuildingCondition.safe => AppColors.success,
        BuildingCondition.minorDamage => AppColors.info,
        BuildingCondition.atRisk => AppColors.warning,
        BuildingCondition.critical => AppColors.danger,
      };

  Color get backgroundColor => switch (this) {
        BuildingCondition.safe => AppColors.successBg,
        BuildingCondition.minorDamage => AppColors.infoBg,
        BuildingCondition.atRisk => AppColors.warningBg,
        BuildingCondition.critical => AppColors.dangerBg,
      };

  Color get borderColor => switch (this) {
        BuildingCondition.safe => AppColors.successBorder,
        BuildingCondition.minorDamage => AppColors.infoBorder,
        BuildingCondition.atRisk => AppColors.warningBorder,
        BuildingCondition.critical => AppColors.dangerBorder,
      };

  /// True for the two conditions that should visually stand out in list/
  /// grid views (e.g. a warning badge on a neighborhood card).
  bool get needsAttention => this == BuildingCondition.atRisk || this == BuildingCondition.critical;

  String get firestoreValue => name;

  static BuildingCondition? fromFirestore(String? value) {
    if (value == null) return null;
    for (final c in BuildingCondition.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}
