import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// المراجعة والقرار (§7.3, BR-1, BR-6, FR-REV-1..4)
/// TODO(Phase 3): مراجعة التقرير الهندسي واتخاذ قرار واحد من الإجراءات الأربعة. يجب أن يمنع هذا الشاشة SHORING_CONFIRM عند غياب إنذار سابق (BR-1) — تحقق من ذلك في الطبقة الخلفية (Cloud Function)، وليس هنا فقط.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'المراجعة والقرار',
      specRef: '§7.3, BR-1, BR-6, FR-REV-1..4',
      description: 'مراجعة التقرير الهندسي واتخاذ قرار واحد من الإجراءات الأربعة. يجب أن يمنع هذا الشاشة SHORING_CONFIRM عند غياب إنذار سابق (BR-1) — تحقق من ذلك في الطبقة الخلفية (Cloud Function)، وليس هنا فقط.',
      icon: Icons.gavel_outlined,
    );
  }
}
