import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Biometric telemetry extracted from a single ML Kit [Face] frame.
class FaceBiometrics {
  final double leftEyeOpenProb;
  final double rightEyeOpenProb;
  final double ear; // Geometric + probabilistic Eye Aspect Ratio
  final double mar; // Geometric Mouth Aspect Ratio
  final double headPitchX; // Nodding forward/backward (degrees)
  final double headYawY; // Turning left/right (degrees)
  final double headRollZ; // Tilting head (degrees)
  final bool isHeadDrooping;
  final bool isLookingAway;

  const FaceBiometrics({
    required this.leftEyeOpenProb,
    required this.rightEyeOpenProb,
    required this.ear,
    required this.mar,
    required this.headPitchX,
    required this.headYawY,
    required this.headRollZ,
    required this.isHeadDrooping,
    required this.isLookingAway,
  });
}

/// Production utility for converting [CameraImage] (Android YUV_420_888 / NV21
/// and iOS BGRA8888) into ML Kit [InputImage], and computing real geometric
/// EAR, MAR, and Head Pose angles from [Face] contours and landmarks.
class MlKitImageConverter {
  /// Converts [CameraImage] to [InputImage] with full Android YUV_420_888 -> NV21
  /// plane interleaving support so face detection works across all Android devices.
  static InputImage? fromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
  }) {
    final InputImageRotation? rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      if (image.planes.isEmpty) return null;
      final InputImageFormat format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.bgra8888;
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // If already single-plane NV21
      if (image.planes.length == 1) {
        return InputImage.fromBytes(
          bytes: image.planes.first.bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );
      }

      // Convert 3-plane YUV_420_888 to NV21 byte array
      final Uint8List nv21Bytes = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return null;
  }

  /// Hardware-safe YUV_420_888 (3 planes) to NV21 converter for Android CameraX / Camera2
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final Uint8List yBuffer = yPlane.bytes;
    final Uint8List uBuffer = uPlane.bytes;
    final Uint8List vBuffer = vPlane.bytes;

    final int numPixels = width * height + (width * height ~/ 2);
    final Uint8List nv21 = Uint8List(numPixels);

    // Copy Y plane row by row respecting rowStride
    int idY = 0;
    final int yRowStride = yPlane.bytesPerRow;
    final int yPixelStride = yPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final int yOffset = y * yRowStride;
      for (int x = 0; x < width; x++) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];
      }
    }

    // Interleave V and U planes (NV21 = YYYYYYYY VUVU)
    int idUV = width * height;
    final int uvWidth = width ~/ 2;
    final int uvHeight = height ~/ 2;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < uvHeight; y++) {
      final int uvOffset = y * uvRowStride;
      for (int x = 0; x < uvWidth; x++) {
        final int bufferIndex = uvOffset + (x * uvPixelStride);
        if (bufferIndex < vBuffer.length && idUV < nv21.length) {
          nv21[idUV++] = vBuffer[bufferIndex];
        }
        if (bufferIndex < uBuffer.length && idUV < nv21.length) {
          nv21[idUV++] = uBuffer[bufferIndex];
        }
      }
    }

    return nv21;
  }

  /// Extracts full [FaceBiometrics] (EAR, MAR, Eye Probabilities, Head Euler Angles)
  static FaceBiometrics extractBiometrics(Face face) {
    final double leftProb = (face.leftEyeOpenProbability ?? 0.90).clamp(0.0, 1.0);
    final double rightProb =
        (face.rightEyeOpenProbability ?? 0.90).clamp(0.0, 1.0);

    // Compute geometric EAR from 16-point eye contours if available
    final double? leftContourEar =
        _computeContourEAR(face.contours[FaceContourType.leftEye]);
    final double? rightContourEar =
        _computeContourEAR(face.contours[FaceContourType.rightEye]);

    double ear;
    final double probBasedEar = ((leftProb + rightProb) / 2.0) * 0.34;
    if (leftContourEar != null && rightContourEar != null) {
      final double geoEar = (leftContourEar + rightContourEar) / 2.0;
      // Fuse ML Kit classification probability with geometric contour EAR
      ear = (geoEar * 0.45) + (probBasedEar * 0.55);
    } else {
      ear = probBasedEar;
    }

    final double mar = computeMouthOpenRatio(face);

    final double pitchX = face.headEulerAngleX ?? 0.0;
    final double yawY = face.headEulerAngleY ?? 0.0;
    final double rollZ = face.headEulerAngleZ ?? 0.0;

    // Head nodding forward (< -15 deg) or looking away (> 32 deg yaw)
    final bool isDrooping = pitchX < -15.0;
    final bool isLookingAway = yawY.abs() > 32.0;

    return FaceBiometrics(
      leftEyeOpenProb: leftProb,
      rightEyeOpenProb: rightProb,
      ear: ear.clamp(0.05, 0.42),
      mar: mar,
      headPitchX: pitchX,
      headYawY: yawY,
      headRollZ: rollZ,
      isHeadDrooping: isDrooping,
      isLookingAway: isLookingAway,
    );
  }

  /// Computes geometric Eye Aspect Ratio (EAR) from ML Kit 16-point eye contour:
  /// Point 0 is left corner, Point 8 is right corner,
  /// Points (3,13), (4,12), (5,11) are vertical upper/lower lid pairs.
  static double? _computeContourEAR(FaceContour? eyeContour) {
    if (eyeContour == null || eyeContour.points.length < 16) return null;
    final List<math.Point<int>> pts = eyeContour.points;

    final double horiz = _dist(pts[0], pts[8]);
    if (horiz <= 1.0) return null;

    final double v1 = _dist(pts[3], pts[13]);
    final double v2 = _dist(pts[4], pts[12]);
    final double v3 = _dist(pts[5], pts[11]);

    return ((v1 + v2 + v3) / (3.0 * horiz)).clamp(0.05, 0.45);
  }

  /// Computes Mouth Aspect Ratio (MAR) from lip contours and mouth landmarks
  static double computeMouthOpenRatio(Face face) {
    final FaceContour? upperLipBottom =
        face.contours[FaceContourType.upperLipBottom];
    final FaceContour? lowerLipTop = face.contours[FaceContourType.lowerLipTop];

    if (upperLipBottom != null &&
        lowerLipTop != null &&
        upperLipBottom.points.length >= 5 &&
        lowerLipTop.points.length >= 5) {
      final List<math.Point<int>> up = upperLipBottom.points;
      final List<math.Point<int>> low = lowerLipTop.points;

      final double mouthWidth = _dist(up.first, up.last);
      if (mouthWidth > 2.0) {
        final int midU = up.length ~/ 2;
        final int midL = low.length ~/ 2;
        final double vCenter = _dist(up[midU], low[midL]);
        final double vLeft = _dist(up[midU - 1], low[midL - 1]);
        final double vRight = _dist(up[midU + 1], low[midL + 1]);
        final double avgVertical = (vCenter + vLeft + vRight) / 3.0;
        return (avgVertical / mouthWidth).clamp(0.02, 1.25);
      }
    }

    // Fallback to landmarks if contours were not detected on this frame
    final FaceLandmark? bottomMouth =
        face.landmarks[FaceLandmarkType.bottomMouth];
    final FaceLandmark? leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
    final FaceLandmark? rightMouth =
        face.landmarks[FaceLandmarkType.rightMouth];

    if (bottomMouth == null || leftMouth == null || rightMouth == null) {
      return 0.12;
    }

    final double mouthWidth = _dist(leftMouth.position, rightMouth.position);
    if (mouthWidth <= 1.0) return 0.12;

    final double mouthCornerMidY =
        (leftMouth.position.y + rightMouth.position.y) / 2.0;
    final double verticalDrop = (bottomMouth.position.y - mouthCornerMidY).abs();

    return (verticalDrop / mouthWidth).clamp(0.02, 1.25);
  }

  static double _dist(math.Point<int> a, math.Point<int> b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }
}
