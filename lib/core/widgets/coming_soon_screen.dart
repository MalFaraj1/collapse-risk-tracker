import 'package:flutter/material.dart';
import 'app_card.dart';
import '../../app/theme/app_colors.dart';

/// Placeholder body for a screen whose UI hasn't been built yet.
///
/// Used by every feature stub in `lib/features/` so navigating the app is
/// coherent end-to-end during development — nobody hits a blank white
/// screen — while making unmistakably clear the screen is a stub, which
/// spec section governs it, and what needs to be built.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.specRef,
    required this.description,
    this.icon = Icons.construction_outlined,
  });

  final String title;
  final String specRef;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          AppCard(
            backgroundColor: AppColors.iceTint,
            borderColor: AppColors.ice,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 28, color: AppColors.navy),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('قيد الإنشاء — $specRef',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.navy)),
                      const SizedBox(height: 6),
                      Text(description,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.6)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
