import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// زيارة ميدانية (§7.8, FR-DASH-3/4)
/// TODO(Phase 3): تسجيل نتيجة زيارة التحقق من الامتثال (تم / لم يتم / جزئي) المُطلَقة من لوحة الإجراءات المستحقة.
class SiteVisitScreen extends StatelessWidget {
  const SiteVisitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'زيارة ميدانية',
      specRef: '§7.8, FR-DASH-3/4',
      description: 'تسجيل نتيجة زيارة التحقق من الامتثال (تم / لم يتم / جزئي) المُطلَقة من لوحة الإجراءات المستحقة.',
      icon: Icons.domain_verification_outlined,
    );
  }
}
