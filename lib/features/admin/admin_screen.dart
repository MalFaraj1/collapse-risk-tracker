import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// إعدادات النظام (§7.12, FR-USR-1..3)
/// TODO(Phase 3): إدارة المستخدمين والأدوار (عبر Cloud Function setUserRole)، قوالب الإشعارات، والمهل الافتراضية لكل نوع إجراء (BR-4).
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'إعدادات النظام',
      specRef: '§7.12, FR-USR-1..3',
      description: 'إدارة المستخدمين والأدوار (عبر Cloud Function setUserRole)، قوالب الإشعارات، والمهل الافتراضية لكل نوع إجراء (BR-4).',
      icon: Icons.admin_panel_settings_outlined,
    );
  }
}
