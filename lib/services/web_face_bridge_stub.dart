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

/// Real GPS location fix returned by browser / device geolocation watcher.
class WebGpsData {
  final double lat;
  final double lng;
  final double speedKmh;
  final double heading;
  final double accuracy;

  const WebGpsData({
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.heading,
    required this.accuracy,
  });
}

/// Native stub implementation (Android / iOS / Desktop).
class WebFaceBridge {
  static WebFaceFrameData? pollLatestWebFaceFrame() => null;
  static WebGpsData? pollLatestWebGps() => null;
  static void startWebGps() {}
  static void toggleWebPictureInPicture() {}
  static void openExternalUrl(String url) {}
  static void registerYandexMapView(
    String viewType,
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {}
  static void updateYandexRoute(
    List<List<double>> points,
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {}
  static void moveYandexCenter(double lat, double lng, double zoom) {}
  static void update2GisCamera3D(
    double lat,
    double lng,
    double zoom,
    double headingDeg,
    double pitchDeg,
  ) {}
  static Offset? pollClickedYandexCoords() => null;
  static void playAlarmSound() => startWebSiren();
  static void startWebSiren() {}
  static void stopWebSiren() {}
  static void speakNavigationInstruction(String text) {}
  static void startNeuroGammaSiren() {}
  static void stopNeuroGammaSiren() {}
  static void speakText(String text, String lang) {}
  static void stopSpeech() {}
  static void ensureWebcam() {}
  static void playKazakhVoice(String key) {}
  static void stopKazakhVoice() {}
  static void startListening(String lang) {}
  static void stopListening() {}
  static bool isListening() => false;
  static String? pollLatestSpeechInput() => null;
  static String? pollInterimSpeechInput() => null;
}