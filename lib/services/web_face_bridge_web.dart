import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui';

import 'web_face_bridge_stub.dart';

export 'web_face_bridge_stub.dart' show WebFaceFrameData;

@JS('_antiSleepLatestFaceJson')
external JSString? get _jsLatestFaceJson;

@JS('_antiSleepStartWebSiren')
external void _jsStartWebSiren();

@JS('_antiSleepStopWebSiren')
external void _jsStopWebSiren();

/// Web implementation reading MediaPipe 468-Landmark telemetry from window in Chrome/Edge.
class WebFaceBridge {
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
}

