import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/theme/cockpit_colors.dart';
import '../../services/web_face_bridge.dart';

/// Renders real-time ML Kit Face Contours (Android/iOS) OR MediaPipe 468-Landmark
/// Contours (Flutter Web Chrome/Edge) over the live camera preview.
class FaceMeshOverlayPainter extends CustomPainter {
  final List<Face> faces;
  final WebFaceFrameData? webFaceData;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final bool isEyesOpen;
  final bool isYawning;
  final double liveEar;

  FaceMeshOverlayPainter({
    required this.faces,
    this.webFaceData,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    required this.isEyesOpen,
    this.isYawning = false,
    this.liveEar = 0.31,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Color primaryColor =
        isEyesOpen ? CockpitColors.safeGreen : CockpitColors.dangerRed;

    final Paint bracketPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    final Paint contourLinePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final Paint eyeContourPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final Paint lipContourPaint = Paint()
      ..color = isYawning ? CockpitColors.warningAmber : CockpitColors.safeGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    // 1. Check if we have live Web MediaPipe Face Mesh data (Chrome / Edge)
    if (webFaceData != null && webFaceData!.faceFound) {
      _paintWebMediaPipeMesh(
        canvas: canvas,
        size: size,
        data: webFaceData!,
        bracketPaint: bracketPaint,
        contourLinePaint: contourLinePaint,
        eyeContourPaint: eyeContourPaint,
        lipContourPaint: lipContourPaint,
        dotPaint: dotPaint,
      );
      return;
    }

    // 2. Check if we have native ML Kit Faces (Android / iOS)
    if (faces.isNotEmpty) {
      for (final Face face in faces) {
        final Rect faceRect = _scaleRect(
          rect: face.boundingBox,
          imageSize: imageSize,
          widgetSize: size,
          rotation: rotation,
          lensDirection: lensDirection,
        );

        _drawCornerBrackets(canvas, faceRect, bracketPaint);

        for (final FaceContourType type in <FaceContourType>[
          FaceContourType.face,
          FaceContourType.leftEyebrowTop,
          FaceContourType.rightEyebrowTop,
          FaceContourType.noseBridge,
          FaceContourType.noseBottom,
        ]) {
          _drawContourPath(
            canvas: canvas,
            contour: face.contours[type],
            size: size,
            paint: contourLinePaint,
            closePath: type == FaceContourType.face,
            drawNodes: type == FaceContourType.face,
            nodePaint: dotPaint,
          );
        }

        for (final FaceContourType eyeType in <FaceContourType>[
          FaceContourType.leftEye,
          FaceContourType.rightEye,
        ]) {
          _drawContourPath(
            canvas: canvas,
            contour: face.contours[eyeType],
            size: size,
            paint: eyeContourPaint,
            closePath: true,
            drawNodes: true,
            nodePaint: dotPaint,
          );
        }

        for (final FaceContourType lipType in <FaceContourType>[
          FaceContourType.upperLipTop,
          FaceContourType.upperLipBottom,
          FaceContourType.lowerLipTop,
          FaceContourType.lowerLipBottom,
        ]) {
          _drawContourPath(
            canvas: canvas,
            contour: face.contours[lipType],
            size: size,
            paint: lipContourPaint,
            closePath: false,
            drawNodes: true,
            nodePaint: Paint()
              ..color = isYawning
                  ? CockpitColors.warningAmber
                  : CockpitColors.safeGreen,
          );
        }

        for (final FaceLandmark? lm in face.landmarks.values) {
          if (lm != null) {
            final Offset pt = _scalePoint(
              point: lm.position,
              imageSize: imageSize,
              widgetSize: size,
              rotation: rotation,
              lensDirection: lensDirection,
            );
            canvas.drawCircle(pt, 3.2, dotPaint);
          }
        }
      }
      return;
    }

    // 3. No face currently in frame: draw subtle scanning reticle
    final Rect scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 12),
      width: size.width * 0.58,
      height: size.height * 0.54,
    );
    _drawCornerBrackets(
      canvas,
      scanRect,
      Paint()
        ..color = CockpitColors.textMuted.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintWebMediaPipeMesh({
    required Canvas canvas,
    required Size size,
    required WebFaceFrameData data,
    required Paint bracketPaint,
    required Paint contourLinePaint,
    required Paint eyeContourPaint,
    required Paint lipContourPaint,
    required Paint dotPaint,
  }) {
    // Mirror horizontally because front webcam preview is mirrored
    Offset mapNorm(Offset norm) =>
        Offset((1.0 - norm.dx) * size.width, norm.dy * size.height);

    final Rect rawBox = data.boundingBox;
    final Rect screenBox = Rect.fromLTRB(
      (1.0 - rawBox.right) * size.width,
      rawBox.top * size.height,
      (1.0 - rawBox.left) * size.width,
      rawBox.bottom * size.height,
    ).inflate(10);

    _drawCornerBrackets(canvas, screenBox, bracketPaint);

    void drawNormalizedPoly(
      List<Offset> pts,
      Paint linePaint,
      Paint nodePaint, {
      bool close = true,
      double nodeRadius = 2.2,
    }) {
      if (pts.isEmpty) return;
      final Path path = Path();
      for (int i = 0; i < pts.length; i++) {
        final Offset p = mapNorm(pts[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawCircle(p, nodeRadius, nodePaint);
      }
      if (close) path.close();
      canvas.drawPath(path, linePaint);
    }

    drawNormalizedPoly(
      data.oval,
      contourLinePaint,
      dotPaint,
      close: true,
      nodeRadius: 1.6,
    );
    drawNormalizedPoly(
      data.leftEye,
      eyeContourPaint,
      dotPaint,
      close: true,
      nodeRadius: 2.6,
    );
    drawNormalizedPoly(
      data.rightEye,
      eyeContourPaint,
      dotPaint,
      close: true,
      nodeRadius: 2.6,
    );
    drawNormalizedPoly(
      data.lips,
      lipContourPaint,
      Paint()
        ..color =
            isYawning ? CockpitColors.warningAmber : CockpitColors.safeGreen,
      close: true,
      nodeRadius: 2.2,
    );
  }

  void _drawContourPath({
    required Canvas canvas,
    required FaceContour? contour,
    required Size size,
    required Paint paint,
    required bool closePath,
    required bool drawNodes,
    required Paint nodePaint,
  }) {
    if (contour == null || contour.points.isEmpty) return;

    final Path path = Path();
    for (int i = 0; i < contour.points.length; i++) {
      final Offset pt = _scalePoint(
        point: contour.points[i],
        imageSize: imageSize,
        widgetSize: size,
        rotation: rotation,
        lensDirection: lensDirection,
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
      if (drawNodes && i % 2 == 0) {
        canvas.drawCircle(pt, 1.8, nodePaint);
      }
    }
    if (closePath) {
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    const double len = 24.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, len), paint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, len), paint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(len, 0), paint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(0, -len), paint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight + const Offset(-len, 0), paint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight + const Offset(0, -len), paint);
  }

  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
    required InputImageRotation rotation,
    required CameraLensDirection lensDirection,
  }) {
    final bool isRotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final double scaleX =
        widgetSize.width / (isRotated ? imageSize.height : imageSize.width);
    final double scaleY =
        widgetSize.height / (isRotated ? imageSize.width : imageSize.height);

    double left = rect.left * scaleX;
    double right = rect.right * scaleX;
    if (lensDirection == CameraLensDirection.front) {
      final double mirroredLeft = widgetSize.width - right;
      right = widgetSize.width - left;
      left = mirroredLeft;
    }

    return Rect.fromLTRB(left, rect.top * scaleY, right, rect.bottom * scaleY);
  }

  Offset _scalePoint({
    required math.Point<int> point,
    required Size imageSize,
    required Size widgetSize,
    required InputImageRotation rotation,
    required CameraLensDirection lensDirection,
  }) {
    final bool isRotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final double scaleX =
        widgetSize.width / (isRotated ? imageSize.height : imageSize.width);
    final double scaleY =
        widgetSize.height / (isRotated ? imageSize.width : imageSize.height);

    double x = point.x * scaleX;
    if (lensDirection == CameraLensDirection.front) {
      x = widgetSize.width - x;
    }
    return Offset(x, point.y * scaleY);
  }

  @override
  bool shouldRepaint(covariant FaceMeshOverlayPainter oldDelegate) => true;
}

/// 2GIS Dark Map Background for PiP Navigation Overlay (Figma Screen 4)
class MapNavigationBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0E141B),
    );

    final Paint roadPaint = Paint()
      ..color = const Color(0xFF1B2430)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;

    canvas.drawLine(
      Offset(size.width * 0.42, 0),
      Offset(size.width * 0.42, size.height),
      roadPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.45),
      Offset(size.width, size.height * 0.45),
      roadPaint,
    );

    final Paint routePaint = Paint()
      ..color = CockpitColors.safeGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path route = Path()
      ..moveTo(size.width * 0.42, size.height * 0.92)
      ..lineTo(size.width * 0.42, size.height * 0.45)
      ..lineTo(size.width * 0.85, size.height * 0.45);
    canvas.drawPath(route, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
