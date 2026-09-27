import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// A horizontal numbered-step progress indicator for multi-step forms
/// (e.g. Intake's 3-step wizard). Generic — not tied to any one feature,
/// reuse it for any future wizard-style screen.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.steps, required this.currentIndex});

  final List<String> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      children.add(_circle(i));
      children.add(const SizedBox(width: 9));
      children.add(
        Text(
          steps[i],
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: i <= currentIndex ? AppColors.text : AppColors.textMuted,
          ),
        ),
      );
      if (i != steps.length - 1) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                height: 2,
                color: i < currentIndex ? AppColors.success : AppColors.border,
              ),
            ),
          ),
        );
      }
    }
    return Row(children: children);
  }

  Widget _circle(int i) {
    final done = i < currentIndex;
    final current = i == currentIndex;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.success : (current ? AppColors.navy : AppColors.border),
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : Text(
              '${i + 1}',
              style: AppTypography.mono(
                fontSize: 13,
                weight: FontWeight.w800,
                color: current ? AppColors.gold : AppColors.textMuted,
              ),
            ),
    );
  }
}