import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// شكوى جديدة (§7.1, FR-INT-1..4)
/// TODO(Phase 3): تسجيل بلاغ مواطن وربطه بالعقار المعني، بما يشمل تنبيه BR-3 عند وجود حالات سابقة على العقار.
class IntakeScreen extends StatelessWidget {
  const IntakeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'شكوى جديدة',
      specRef: '§7.1, FR-INT-1..4',
      description: 'تسجيل بلاغ مواطن وربطه بالعقار المعني، بما يشمل تنبيه BR-3 عند وجود حالات سابقة على العقار.',
      icon: Icons.add_ic_call_outlined,
    );
  }
}
