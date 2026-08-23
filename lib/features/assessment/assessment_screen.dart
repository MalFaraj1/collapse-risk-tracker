import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// التقييم والترميم (§7.6, §7.6a, BR-8, BR-10)
/// TODO(Phase 3): متابعة رأي الجهة الخارجية (خطيب وعلمي)، دراسة الترميم، قدرة المالك المالية، ومرشّحي التمويل.
class AssessmentScreen extends StatelessWidget {
  const AssessmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'التقييم والترميم',
      specRef: '§7.6, §7.6a, BR-8, BR-10',
      description: 'متابعة رأي الجهة الخارجية (خطيب وعلمي)، دراسة الترميم، قدرة المالك المالية، ومرشّحي التمويل.',
      icon: Icons.architecture_outlined,
    );
  }
}
