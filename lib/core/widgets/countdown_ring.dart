import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// The circular countdown ring — one of the app's two signature motifs
/// (the other is [TimelineRail]). Used for every hard deadline: the 48-hour
/// evacuation compliance clock (BR-7), notice execution deadlines (BR-4),
/// etc. Reuse this everywhere a deadline needs visualizing rather than
/// inventing a new pattern per screen.
///
/// [progress] is 0.0–1.0 (fraction of the deadline elapsed, not remaining).
/// [urgent] switches the ring to the danger color for near-expiry states.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.progress,
    required this.centerLabel,
    required this.subLabel,
    this.size = 150,
    this.urgent = false,
  });

  final double progress;
  final String centerLabel;
  final String subLabel;
  final double size;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final ringColor = urgent ? AppColors.danger : AppColors.gold;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(progress: progress.clamp(0.0, 1.0), color: ringColor),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: AppTypography.mono(fontSize: size * 0.16, weight: FontWeight.w800, color: AppColors.text),
              ),
              const SizedBox(height: 2),
              Text(
                subLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: size * 0.07, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 10) / 2;
    final strokeWidth = size.width * 0.067;

    final bgPaint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
