import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/cockpit_colors.dart';

/// Futuristic Automotive Cockpit HUD & Speedometer Radar Illustration
class DashboardIllustrationPainter extends CustomPainter {
  final double pulseValue;

  DashboardIllustrationPainter({this.pulseValue = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Glowing Perspective Road Grid Lines
    final Paint gridPaint = Paint()
      ..color = CockpitColors.safeGreen.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final Offset vanishingPoint = Offset(w * 0.5, h * 0.28);

    // Horizon line
    canvas.drawLine(
      Offset(w * 0.1, h * 0.28),
      Offset(w * 0.9, h * 0.28),
      gridPaint,
    );

    // Perspective perspective lines
    for (double i = -1.0; i <= 1.0; i += 0.5) {
      canvas.drawLine(
        vanishingPoint,
        Offset(w * 0.5 + i * (w * 0.42), h * 0.85),
        gridPaint,
      );
    }

    // Outer Digital Cockpit Arc (Speedometer style)
    final Rect arcRect = Rect.fromCircle(
      center: Offset(w * 0.5, h * 0.75),
      radius: h * 0.65,
    );

    final Paint arcTrackPaint = Paint()
      ..color = const Color(0xFF222933)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawArc(arcRect, math.pi * 0.9, math.pi * 1.2, false, arcTrackPaint);

    final Paint activeArcPaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[
          CockpitColors.safeGreen,
          Color(0xFF00B0FF),
        ],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;
    canvas.drawArc(
      arcRect,
      math.pi * 0.9,
      math.pi * 0.9 * pulseValue.clamp(0.6, 1.0),
      false,
      activeArcPaint,
    );

    // Modern Cockpit Steering Ring (Left Side)
    final Offset wheelCenter = Offset(w * 0.22, h * 0.68);
    final Paint wheelPaint = Paint()
      ..color = const Color(0xFF38434F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(wheelCenter, 26, wheelPaint);

    final Paint wheelAccentPaint = Paint()
      ..color = CockpitColors.safeGreen.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(wheelCenter, 10, wheelAccentPaint);
    canvas.drawLine(
      Offset(wheelCenter.dx - 26, wheelCenter.dy),
      Offset(wheelCenter.dx + 26, wheelCenter.dy),
      wheelPaint,
    );

    // Center Mounted AI Vision Scanner Device (Phone with Face Detection Radar)
    final RRect phoneRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.46),
        width: 38,
        height: 64,
      ),
      const Radius.circular(8),
    );

    final Paint phoneBodyPaint = Paint()
      ..color = const Color(0xFF131920)
      ..style = PaintingStyle.fill;
    final Paint phoneBorderPaint = Paint()
      ..color = CockpitColors.safeGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRRect(phoneRRect, phoneBodyPaint);
    canvas.drawRRect(phoneRRect, phoneBorderPaint);

    // AI Radar Pulse inside scanner phone
    final Paint radarPaint = Paint()
      ..color = CockpitColors.safeGreen.withValues(alpha: 0.35 * pulseValue)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.5, h * 0.44), 9 * pulseValue, radarPaint);

    final Paint facePointPaint = Paint()
      ..color = CockpitColors.safeGreen
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.5, h * 0.44), 3.5, facePointPaint);

    // Right Side Telemetry Gauge Indicator
    final Offset rightGaugeCenter = Offset(w * 0.78, h * 0.68);
    final Paint gaugePaint = Paint()
      ..color = const Color(0xFF38434F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(rightGaugeCenter, 20, gaugePaint);

    final Paint gaugeLivePaint = Paint()
      ..color = CockpitColors.safeGreen
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;
    canvas.drawArc(
      Rect.fromCircle(center: rightGaugeCenter, radius: 20),
      -math.pi * 0.5,
      math.pi * 1.3,
      false,
      gaugeLivePaint,
    );
  }

  @override
  bool shouldRepaint(covariant DashboardIllustrationPainter oldDelegate) =>
      oldDelegate.pulseValue != pulseValue;
}
