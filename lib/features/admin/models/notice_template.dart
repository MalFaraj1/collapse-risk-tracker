import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../review/models/decision.dart';

/// The built-in (version 1) legal body text for each notice type — the
/// exact wording that used to be hardcoded in Notice Preview, now written
/// with `{placeholders}` so an administrator can edit it (FR-USR-3, §8).
class NoticeTemplateDefaults {
  NoticeTemplateDefaults._();

  static String bodyFor(DecisionAction action) => switch (action) {
        DecisionAction.evacuation =>
          'بناءً على المراجعة الهندسية للعقار المذكور أعلاه بتاريخ {decision_date}، وثبوت وجود خطر انهيار وشيك يهدد '
              'السلامة العامة، تأمر البلدية بإخلاء العقار المذكور فورًا، على أن يُنفَّذ الإخلاء ومتابعته وفق الإجراءات '
              'المعتمدة، طبقًا للصلاحيات المخوّلة للبلدية بموجب الأنظمة المرعية الإجراء.',
        DecisionAction.shoringWarning =>
          'بناءً على المراجعة الهندسية للعقار المذكور أعلاه بتاريخ {decision_date}، ونظرًا لما لوحظ من مؤشرات تستدعي '
              'أعمال تدعيم إنشائي، تُنذر البلدية مالك العقار المذكور أعلاه بوجوب اتخاذ إجراءات التدعيم اللازمة خلال '
              'المهلة المحددة أعلاه، وذلك حفاظًا على السلامة العامة، طبقًا للصلاحيات المخوّلة للبلدية بموجب الأنظمة '
              'المرعية الإجراء.',
        DecisionAction.shoringConfirm =>
          'إلحاقًا بالإنذار السابق الصادر بشأن هذا العقار (المرجع أعلاه)، ونظرًا لعدم تنفيذ أعمال التدعيم المطلوبة '
              'خلال المهلة الممنوحة، تؤكد البلدية إنذارها وتطالب المالك بتنفيذ الأعمال فورًا خلال المهلة الجديدة '
              'المحددة أعلاه، تحت طائلة اتخاذ الإجراءات القانونية اللاحقة.',
        DecisionAction.restorationWarning =>
          'بناءً على المراجعة الهندسية للعقار المذكور أعلاه بتاريخ {decision_date}، تُنذر البلدية مالك العقار المذكور '
              'أعلاه بوجوب القيام بأعمال الترميم اللازمة خلال المهلة المحددة أعلاه، حفاظًا على السلامة العامة وسلامة '
              'المبنى، طبقًا للصلاحيات المخوّلة للبلدية بموجب الأنظمة المرعية الإجراء.',
      };
}

/// One saved version of a template (`noticeTemplates/{type}/versions/{n}`).
/// Versions are immutable — saving an edit always creates the next
/// number, so a notice issued under version 3 can always be re-rendered
/// with exactly the wording it was issued with (FR-ACT-2: "keep prior
/// versions").
class NoticeTemplateVersion {
  const NoticeTemplateVersion({required this.version, required this.body, this.savedAt});
  final int version;
  final String body;
  final DateTime? savedAt;
}

/// The current state of one template as stored in `noticeTemplates/{type}`.
class NoticeTemplateState {
  const NoticeTemplateState({required this.version, required this.body, this.updatedAt});
  final int version;
  final String body;
  final DateTime? updatedAt;
}

class NoticeTemplates {
  NoticeTemplates._();

  /// The hardcoded default counts as version 1; the first administrator
  /// save is therefore version 2.
  static const builtInVersion = 1;

  /// Merge fields an administrator can place in a template body.
  static const placeholders = <String, String>{
    '{decision_date}': 'تاريخ القرار',
    '{execution_date}': 'تاريخ التنفيذ',
    '{parcel_no}': 'رقم العقار',
    '{cadastral_zone}': 'المنطقة العقارية',
    '{address}': 'العنوان',
  };

  static String render(
    String body, {
    required String decisionDate,
    required String executionDate,
    required String parcelNo,
    required String cadastralZone,
    required String address,
  }) {
    return body
        .replaceAll('{decision_date}', decisionDate)
        .replaceAll('{execution_date}', executionDate)
        .replaceAll('{parcel_no}', parcelNo)
        .replaceAll('{cadastral_zone}', cadastralZone)
        .replaceAll('{address}', address.isEmpty ? '—' : address);
  }

  /// The version number a notice issued right now should record.
  static Future<int> currentVersion(FirebaseFirestore firestore, DecisionAction action) async {
    try {
      final doc = await firestore.collection(FirestorePaths.noticeTemplates).doc(action.firestoreValue).get();
      return (doc.data()?['version'] as num?)?.toInt() ?? builtInVersion;
    } catch (_) {
      return builtInVersion;
    }
  }

  /// The raw (un-rendered) body for [action] at [version] — or the current
  /// one if [version] is null. Falls back to the built-in text whenever a
  /// custom one isn't available, so a notice can always be rendered.
  static Future<String> bodyFor(FirebaseFirestore firestore, DecisionAction action, {int? version}) async {
    try {
      final base = firestore.collection(FirestorePaths.noticeTemplates).doc(action.firestoreValue);
      if (version != null) {
        if (version <= builtInVersion) return NoticeTemplateDefaults.bodyFor(action);
        final v = await base.collection('versions').doc('$version').get();
        final body = v.data()?['body'] as String?;
        if (body != null && body.trim().isNotEmpty) return body;
      }
      final current = await base.get();
      final body = current.data()?['body'] as String?;
      if (body != null && body.trim().isNotEmpty) return body;
    } catch (_) {
      // fall through to the built-in text
    }
    return NoticeTemplateDefaults.bodyFor(action);
  }
}