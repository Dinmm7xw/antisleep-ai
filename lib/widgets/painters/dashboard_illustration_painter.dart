import 'package:flutter/material.dart';
import '../../core/theme/cockpit_colors.dart';

/// Cockpit Car Dashboard + Mounted Phone Illustration (Figma Screen 1)
class DashboardIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = const Color(0xFF30363D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint greenPaint = Paint()
      ..color = CockpitColors.safeGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    // Dashboard Windshield Curve
    final Path dashPath = Path()
      ..moveTo(12, size.height * 0.78)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.18,
        size.width * 0.8,
        size.height * 0.18,
        size.width - 12,
        size.height * 0.78,
      )
      ..close();
    canvas.drawPath(dashPath, linePaint);

    // Steering Wheel Left
    final Offset wheelCenter = Offset(size.width * 0.30, size.height * 0.70);
    canvas.drawCircle(wheelCenter, 24, linePaint);
    canvas.drawCircle(wheelCenter, 7, linePaint);

    // Mounted Smartphone in Center
    final RRect phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.52, size.height * 0.45),
        width: 26,
        height: 46,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(phoneRect, greenPaint);
    canvas.drawCircle(
      Offset(size.width * 0.52, size.height * 0.41),
      4,
      Paint()..color = CockpitColors.safeGreen,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

