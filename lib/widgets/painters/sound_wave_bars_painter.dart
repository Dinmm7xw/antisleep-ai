import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated Sound-Wave Equalizer Bars for DangerAlertScreen (Figma Screen 3)
class SoundWaveBarsPainter extends CustomPainter {
  final double phase;
  SoundWaveBarsPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint barPaint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5;

    const int barCount = 13;
    final double spacing = size.width / (barCount + 1);

    for (int i = 0; i < barCount; i++) {
      final double x = spacing * (i + 1);
      final double wave =
          math.sin((i * 0.7) + (phase * math.pi * 2)).abs() * 0.75 + 0.25;
      final double barHeight = size.height * wave;
      final double top = (size.height - barHeight) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + barHeight), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SoundWaveBarsPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

