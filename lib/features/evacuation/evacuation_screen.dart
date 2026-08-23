import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// تنفيذ الإخلاء (§7.5, BR-7, FR-EVC-1..6)
/// TODO(Phase 3): متابعة خطوات تنفيذ أمر الإخلاء: نشر الأمر (يبدأ عدّاد 48 ساعة)، جمع بيانات الشاغلين، الإرسال للإغاثة، وزيارة التحقق. استخدم CountdownRing لعرض المهلة المتبقية.
class EvacuationScreen extends StatelessWidget {
  const EvacuationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'تنفيذ الإخلاء',
      specRef: '§7.5, BR-7, FR-EVC-1..6',
      description: 'متابعة خطوات تنفيذ أمر الإخلاء: نشر الأمر (يبدأ عدّاد 48 ساعة)، جمع بيانات الشاغلين، الإرسال للإغاثة، وزيارة التحقق. استخدم CountdownRing لعرض المهلة المتبقية.',
      icon: Icons.directions_run_outlined,
    );
  }
}
