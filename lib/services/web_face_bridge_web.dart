import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui';
import 'dart:ui_web' as ui_web;

import 'web_face_bridge_stub.dart';

export 'web_face_bridge_stub.dart' show WebFaceFrameData, WebGpsData;

@JS('_antiSleepLatestFaceJson')
external JSString? get _jsLatestFaceJson;

@JS('_antiSleepLatestGpsJson')
external JSString? get _jsLatestGpsJson;

@JS('_antiSleepClickedCoordsJson')
external JSString? get _jsClickedCoordsJson;

@JS('_antiSleepClickedCoordsJson')
external set _jsClickedCoordsJson(JSString? value);

@JS('_antiSleepStartWebGps')
external void _jsStartWebGps();

@JS('_antiSleepToggleWebPip')
external void _jsToggleWebPip();

@JS('_antiSleepOpenUrl')
external void _jsOpenUrl(JSString url);

@JS('_antiSleepCreateYandexMapDiv')
external JSObject _jsCreateYandexMapDiv(
  JSNumber viewId,
  JSNumber startLat,
  JSNumber startLng,
  JSNumber endLat,
  JSNumber endLng,
);

@JS('_antiSleepUpdateYandexRoute')
external void _jsUpdateYandexRoute(
  JSString pointsJson,
  JSNumber startLat,
  JSNumber startLng,
  JSNumber endLat,
  JSNumber endLng,
);

@JS('_antiSleepMoveYandexCenter')
external void _jsMoveYandexCenter(
  JSNumber lat,
  JSNumber lng,
  JSNumber zoom,
);

@JS('_antiSleepUpdate2GisCamera3D')
external void _jsUpdate2GisCamera3D(
  JSNumber lat,
  JSNumber lng,
  JSNumber zoom,
  JSNumber headingDeg,
  JSNumber pitchDeg,
);

@JS('_antiSleepStartWebSiren')
external void _jsStartWebSiren();

@JS('_antiSleepStopWebSiren')
external void _jsStopWebSiren();

@JS('_antiSleepSpeakNav')
external void _jsSpeakNav(JSString text);

/// Web implementation reading MediaPipe 468-Landmark telemetry, HTML5 GPS, Yandex Maps 2.1 JS API, and Web PiP.

@JS('_antiSleepStartNeuroGammaSiren')
external void _jsStartNeuroGammaSiren();

@JS('_antiSleepStopNeuroGammaSiren')
external void _jsStopNeuroGammaSiren();

@JS('_antiSleepSpeakText')
external void _jsSpeakText(JSString text, JSString lang);

@JS('_antiSleepStopSpeech')
external void _jsStopSpeech();

@JS('_antiSleepEnsureWebcam')
external void _jsEnsureWebcam();

@JS('_antiSleepPlayKazakhVoice')
external void _jsPlayKazakhVoice(JSString key);

@JS('_antiSleepStopKazakhVoice')
external void _jsStopKazakhVoice();

class WebFaceBridge {
  static final Set<String> _registeredViews = <String>{};

  static WebFaceFrameData? pollLatestWebFaceFrame() {
    try {
      final JSString? rawJs = _jsLatestFaceJson;
      if (rawJs == null) return null;
      final String jsonStr = rawJs.toDart;
      if (jsonStr.isEmpty) return null;

      final Map<String, dynamic> map =
          jsonDecode(jsonStr) as Map<String, dynamic>;
      final int ts = (map['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts > 1500) {
        return null;
      }

      final bool found = map['faceFound'] as bool? ?? false;
      if (!found) {
        return const WebFaceFrameData(
          faceFound: false,
          ear: 0.31,
          mar: 0.14,
          pitch: 0.0,
          yaw: 0.0,
          boundingBox: Rect.zero,
          leftEye: <Offset>[],
          rightEye: <Offset>[],
          lips: <Offset>[],
          oval: <Offset>[],
        );
      }

      final List<dynamic> bboxList =
          map['bbox'] as List<dynamic>? ?? <dynamic>[0.2, 0.2, 0.8, 0.8];
      final Rect bbox = Rect.fromLTRB(
        (bboxList[0] as num).toDouble(),
        (bboxList[1] as num).toDouble(),
        (bboxList[2] as num).toDouble(),
        (bboxList[3] as num).toDouble(),
      );

      List<Offset> parsePts(String key) {
        final List<dynamic>? list = map[key] as List<dynamic>?;
        if (list == null) return <Offset>[];
        return list.map((dynamic item) {
          final List<dynamic> pair = item as List<dynamic>;
          return Offset(
            (pair[0] as num).toDouble(),
            (pair[1] as num).toDouble(),
          );
        }).toList();
      }

      return WebFaceFrameData(
        faceFound: true,
        ear: (map['ear'] as num?)?.toDouble() ?? 0.31,
        mar: (map['mar'] as num?)?.toDouble() ?? 0.14,
        pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
        yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
        boundingBox: bbox,
        leftEye: parsePts('leftEye'),
        rightEye: parsePts('rightEye'),
        lips: parsePts('lips'),
        oval: parsePts('oval'),
      );
    } catch (_) {
      return null;
    }
  }

  static WebGpsData? pollLatestWebGps() {
    try {
      final JSString? rawJs = _jsLatestGpsJson;
      if (rawJs == null) return null;
      final String jsonStr = rawJs.toDart;
      if (jsonStr.isEmpty) return null;

      final Map<String, dynamic> map =
          jsonDecode(jsonStr) as Map<String, dynamic>;
      return WebGpsData(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        speedKmh: (map['speedKmh'] as num?)?.toDouble() ?? 0.0,
        heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
        accuracy: (map['accuracy'] as num?)?.toDouble() ?? 10.0,
      );
    } catch (_) {
      return null;
    }
  }

  static void registerYandexMapView(
    String viewType,
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    if (_registeredViews.contains(viewType)) return;
    _registeredViews.add(viewType);

    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      return _jsCreateYandexMapDiv(
        viewId.toJS,
        startLat.toJS,
        startLng.toJS,
        endLat.toJS,
        endLng.toJS,
      );
    });
  }

  static void updateYandexRoute(
    List<List<double>> points,
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    try {
      final String encoded = jsonEncode(points);
      _jsUpdateYandexRoute(
        encoded.toJS,
        startLat.toJS,
        startLng.toJS,
        endLat.toJS,
        endLng.toJS,
      );
    } catch (_) {}
  }

  static void moveYandexCenter(double lat, double lng, double zoom) {
    try {
      _jsMoveYandexCenter(lat.toJS, lng.toJS, zoom.toJS);
    } catch (_) {}
  }

  static void update2GisCamera3D(
    double lat,
    double lng,
    double zoom,
    double headingDeg,
    double pitchDeg,
  ) {
    try {
      _jsUpdate2GisCamera3D(
        lat.toJS,
        lng.toJS,
        zoom.toJS,
        headingDeg.toJS,
        pitchDeg.toJS,
      );
    } catch (_) {}
  }

  static Offset? pollClickedYandexCoords() {
    try {
      final JSString? raw = _jsClickedCoordsJson;
      if (raw == null) return null;
      final String s = raw.toDart;
      if (s.isEmpty) return null;
      _jsClickedCoordsJson = ''.toJS;
      final Map<String, dynamic> map = jsonDecode(s) as Map<String, dynamic>;
      return Offset(
        (map['lat'] as num).toDouble(),
        (map['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static void startWebGps() {
    try {
      _jsStartWebGps();
    } catch (_) {}
  }

  static void toggleWebPictureInPicture() {
    try {
      _jsToggleWebPip();
    } catch (_) {}
  }

  static void openExternalUrl(String url) {
    try {
      _jsOpenUrl(url.toJS);
    } catch (_) {}
  }

  static void playAlarmSound() => startWebSiren();
  static void startWebSiren() {
    try {
      _jsStartWebSiren();
    } catch (_) {}
  }

  static void stopWebSiren() {
    try {
      _jsStopWebSiren();
    } catch (_) {}
  }

  static void speakNavigationInstruction(String text) {
    try {
      _jsSpeakNav(text.toJS);
    } catch (_) {}
  }

  static void startNeuroGammaSiren() {
    try {
      _jsStartNeuroGammaSiren();
    } catch (_) {}
  }

  static void stopNeuroGammaSiren() {
    try {
      _jsStopNeuroGammaSiren();
    } catch (_) {}
  }

  static void speakText(String text, String lang) {
    try {
      _jsSpeakText(text.toJS, lang.toJS);
    } catch (_) {}
  }

  static void stopSpeech() {
    try {
      _jsStopSpeech();
    } catch (_) {}
  }

  static void ensureWebcam() {
    try {
      _jsEnsureWebcam();
    } catch (_) {}
  }

  static void playKazakhVoice(String key) {
    try {
      _jsPlayKazakhVoice(key.toJS);
    } catch (_) {}
  }

  static void stopKazakhVoice() {
    try {
      _jsStopKazakhVoice();
    } catch (_) {}
  }
}