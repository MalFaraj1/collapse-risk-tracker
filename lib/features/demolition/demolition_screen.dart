import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// أوامر الهدم (§7.7, BR-9, FR-DEM-1..3)
/// TODO(Phase 3): متابعة الإشعار المنشور، التنسيق مع الجهة الخارجية، وتكليف المتعهد عبر أمر مباشرة.
class DemolitionScreen extends StatelessWidget {
  const DemolitionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'أوامر الهدم',
      specRef: '§7.7, BR-9, FR-DEM-1..3',
      description: 'متابعة الإشعار المنشور، التنسيق مع الجهة الخارجية، وتكليف المتعهد عبر أمر مباشرة.',
      icon: Icons.domain_disabled_outlined,
    );
  }
}
