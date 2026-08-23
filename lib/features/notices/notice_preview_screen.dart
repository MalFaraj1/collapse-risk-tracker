import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// معاينة الإشعار (§8, FR-ACT-1/2)
/// TODO(Phase 3): عرض الإشعار الرسمي المُولَّد من قالب عربي RTL، مع خيار تنزيله كملف PDF.
class NoticePreviewScreen extends StatelessWidget {
  const NoticePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'معاينة الإشعار',
      specRef: '§8, FR-ACT-1/2',
      description: 'عرض الإشعار الرسمي المُولَّد من قالب عربي RTL، مع خيار تنزيله كملف PDF.',
      icon: Icons.description_outlined,
    );
  }
}
