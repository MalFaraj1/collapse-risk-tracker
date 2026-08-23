import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// فرز الأولوية (§7.1a, BR-5, FR-TRI-1..4)
/// TODO(Phase 3): مراجعة صور الشكوى وتحديد المسار: عاجل (معاينة موقعية) أو غير عاجل (إحالة للجنة).
class TriageScreen extends StatelessWidget {
  const TriageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'فرز الأولوية',
      specRef: '§7.1a, BR-5, FR-TRI-1..4',
      description: 'مراجعة صور الشكوى وتحديد المسار: عاجل (معاينة موقعية) أو غير عاجل (إحالة للجنة).',
      icon: Icons.rule_outlined,
    );
  }
}
