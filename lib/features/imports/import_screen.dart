import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon_screen.dart';

/// استيراد إنذارات سابقة (§7.9, BR-1, FR-IMP-1..3)
/// TODO(Phase 3): رفع جدول بيانات يحتوي إنذارات قديمة، مطابقتها مع العقارات القائمة أو إنشاء عقارات جديدة، وتعليم الصفوف غير المطابَقة للمراجعة اليدوية.
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ComingSoonScreen(
      title: 'استيراد إنذارات سابقة',
      specRef: '§7.9, BR-1, FR-IMP-1..3',
      description: 'رفع جدول بيانات يحتوي إنذارات قديمة، مطابقتها مع العقارات القائمة أو إنشاء عقارات جديدة، وتعليم الصفوف غير المطابَقة للمراجعة اليدوية.',
      icon: Icons.upload_file_outlined,
    );
  }
}
