import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../review/models/decision.dart';

/// Configurable default follow-up periods (BR-4, FR-ACT-4, FR-USR-3).
///
/// §5.2 states there are no fixed legal follow-up periods: execution
/// dates are auto-filled from per-action-type defaults that the
/// administrator manages, and can still be overridden per action by the
/// user. Stored as one document, `settings/followUpPeriods`.
///
/// Every screen that used to hardcode a period now reads it from here:
/// Review & Decision (per decision type), Assessment's automatic
/// demolition scheduling, Evacuation's compliance clock (BR-7), and the
/// "due soon" window of the overdue/upcoming report.
class FollowUpSettings {
  const FollowUpSettings({
    this.shoringWarningDays = 30,
    this.shoringConfirmDays = 30,
    this.restorationWarningDays = 30,
    this.evacuationHours = 48,
    this.demolitionDays = 30,
    this.dueSoonWindowDays = 7,
  });

  static const docId = 'followUpPeriods';

  /// Matches the values that were previously hardcoded, so nothing
  /// changes for anyone until an administrator saves different ones.
  static const defaults = FollowUpSettings();

  final int shoringWarningDays;
  final int shoringConfirmDays;
  final int restorationWarningDays;
  final int evacuationHours;
  final int demolitionDays;
  final int dueSoonWindowDays;

  Duration periodFor(DecisionAction action) => switch (action) {
        DecisionAction.evacuation => Duration(hours: evacuationHours),
        DecisionAction.shoringWarning => Duration(days: shoringWarningDays),
        DecisionAction.shoringConfirm => Duration(days: shoringConfirmDays),
        DecisionAction.restorationWarning => Duration(days: restorationWarningDays),
      };

  /// Human-readable period for the auto-fill hint on Review & Decision.
  String describe(DecisionAction action) =>
      action == DecisionAction.evacuation ? '$evacuationHours ساعة' : '${periodFor(action).inDays} يومًا';

  FollowUpSettings copyWith({
    int? shoringWarningDays,
    int? shoringConfirmDays,
    int? restorationWarningDays,
    int? evacuationHours,
    int? demolitionDays,
    int? dueSoonWindowDays,
  }) =>
      FollowUpSettings(
        shoringWarningDays: shoringWarningDays ?? this.shoringWarningDays,
        shoringConfirmDays: shoringConfirmDays ?? this.shoringConfirmDays,
        restorationWarningDays: restorationWarningDays ?? this.restorationWarningDays,
        evacuationHours: evacuationHours ?? this.evacuationHours,
        demolitionDays: demolitionDays ?? this.demolitionDays,
        dueSoonWindowDays: dueSoonWindowDays ?? this.dueSoonWindowDays,
      );

  static int _int(Object? v, int fallback, {int max = 3650}) {
    final n = (v as num?)?.toInt();
    if (n == null || n < 1 || n > max) return fallback;
    return n;
  }

  factory FollowUpSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    return FollowUpSettings(
      shoringWarningDays: _int(m['shoringWarningDays'], defaults.shoringWarningDays),
      shoringConfirmDays: _int(m['shoringConfirmDays'], defaults.shoringConfirmDays),
      restorationWarningDays: _int(m['restorationWarningDays'], defaults.restorationWarningDays),
      evacuationHours: _int(m['evacuationHours'], defaults.evacuationHours, max: 720),
      demolitionDays: _int(m['demolitionDays'], defaults.demolitionDays),
      dueSoonWindowDays: _int(m['dueSoonWindowDays'], defaults.dueSoonWindowDays, max: 365),
    );
  }

  Map<String, dynamic> toMap() => {
        'shoringWarningDays': shoringWarningDays,
        'shoringConfirmDays': shoringConfirmDays,
        'restorationWarningDays': restorationWarningDays,
        'evacuationHours': evacuationHours,
        'demolitionDays': demolitionDays,
        'dueSoonWindowDays': dueSoonWindowDays,
      };

  /// One-shot read for repositories that need the current defaults at the
  /// moment they write (demolition scheduling, evacuation posting).
  /// Never throws: if the document is missing or unreadable, the
  /// historical defaults apply — a settings problem must never block
  /// enforcement work.
  static Future<FollowUpSettings> load(FirebaseFirestore firestore) async {
    try {
      final doc = await firestore.collection(FirestorePaths.settings).doc(docId).get();
      return FollowUpSettings.fromMap(doc.data());
    } catch (_) {
      return defaults;
    }
  }
}