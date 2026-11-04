import 'dart:ui';

/// Normalized face contour data returned by the Web MediaPipe bridge when running on Flutter Web.
class WebFaceFrameData {
  final bool faceFound;
  final double ear;
  final double mar;
  final double pitch;
  final double yaw;
  final Rect boundingBox; // Normalized 0..1
  final List<Offset> leftEye;
  final List<Offset> rightEye;
  final List<Offset> lips;
  final List<Offset> oval;

  const WebFaceFrameData({
    required this.faceFound,
    required this.ear,
    required this.mar,
    required this.pitch,
    required this.yaw,
    required this.boundingBox,
    required this.leftEye,
    required this.rightEye,
    required this.lips,
    required this.oval,
  });
}

/// Native stub implementation (Android / iOS / Desktop).
class WebFaceBridge {
  static WebFaceFrameData? pollLatestWebFaceFrame() => null;
  static void startWebSiren() {}
  static void stopWebSiren() {}
}

