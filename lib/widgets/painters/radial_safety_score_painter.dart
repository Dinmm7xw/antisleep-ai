import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/cockpit_colors.dart';

/// Circular Radial Progress Gauge for SummaryScreen (Figma Screen 5)
class RadialSafetyScorePainter extends CustomPainter {
  final double progress;
  final Color color;

  RadialSafetyScorePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width / 2) - 5;

    final Paint trackPaint = Paint()
      ..color = CockpitColors.bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;

    final Paint arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant RadialSafetyScorePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

