import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// التقارير (§9)
/// TODO(Phase 3): سبعة تقارير إدارية (R1–R7) قابلة للتصدير بصيغة PDF أو Excel، بالعربية RTL.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'التقارير',
      specRef: '§9',
      description: 'سبعة تقارير إدارية (R1–R7) قابلة للتصدير بصيغة PDF أو Excel، بالعربية RTL.',
      icon: Icons.bar_chart_outlined,
    );
  }
}
