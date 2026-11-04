import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/web_face_bridge.dart';
import '../state/app_session_state.dart';

/// Preset location model for 1-tap Point A / Point B selection.
class _PresetPlace {
  final String title;
  final LatLng coords;
  const _PresetPlace(this.title, this.coords);
}

/// Single Turn-by-Turn maneuver step inside the built-in navigator.
class _RouteStep {
  final String actionText;
  final String streetName;
  final double distanceMeters;
  final LatLng location;
  final IconData icon;

  const _RouteStep({
    required this.actionText,
    required this.streetName,
    required this.distanceMeters,
    required this.location,
    required this.icon,
  });
}

/// Built-In Full-Screen Turn-by-Turn Navigator (Point A -> Point B OSRM Street Routing, Voice Prompts, Step List, Live GPS & PiP Camera).
class LiveNavigationMapView extends StatefulWidget {
  final Widget pipCameraPreview;
  final bool isEyesOpen;
  final VoidCallback onTriggerSystemPip;

  const LiveNavigationMapView({
    super.key,
    required this.pipCameraPreview,
    required this.isEyesOpen,
    required this.onTriggerSystemPip,
  });

  @override
  State<LiveNavigationMapView> createState() => _LiveNavigationMapViewState();
}

class _LiveNavigationMapViewState extends State<LiveNavigationMapView> {
  static const MethodChannel _bgChannel =
      MethodChannel('antisleep_ai/background');

  static const List<_PresetPlace> _presets = <_PresetPlace>[
    _PresetPlace('Абая / Достык', LatLng(43.2415, 76.9562)),
    _PresetPlace('Достык / Аль-Фараби', LatLng(43.2220, 76.9585)),
    _PresetPlace('ТРЦ Mega Alma-Ata', LatLng(43.2016, 76.8924)),
    _PresetPlace('ВСК Медеу', LatLng(43.1574, 77.0590)),
    _PresetPlace('Аэропорт Алматы', LatLng(43.3521, 77.0405)),
    _PresetPlace('Вокзал Алматы-2', LatLng(43.2736, 76.9390)),
    _PresetPlace('Қонаев (Капшагай)', LatLng(43.8644, 77.0528)),
    _PresetPlace('Астана Байтерек', LatLng(51.1283, 71.4305)),
  ];

  final MapController _mapController = MapController();
  final TextEditingController _fromController =
      TextEditingController(text: 'Абая / Достык');
  final TextEditingController _toController =
      TextEditingController(text: 'Достык / Аль-Фараби');
  final Distance _distanceCalc = const Distance();

  // Point A (Start), Point B (Destination), and live vehicle position
  LatLng _pointA = const LatLng(43.2415, 76.9562);
  LatLng _pointB = const LatLng(43.2220, 76.9585);
  LatLng _currentLocation = const LatLng(43.2415, 76.9562);

  String _pointALabel = 'Абая / Достык';
  String _pointBLabel = 'Достык / Аль-Фараби';
  String _nextActionText = 'Поверните направо';
  String _nextStreetInstruction = 'пр. Достык';
  IconData _nextManeuverIcon = Icons.turn_right_rounded;
  double _nextStepDistanceMeters = 250.0;

  // Which point a map tap updates: 'B' (default destination) or 'A' (start point)
  String _mapTapTarget = 'B';

  final List<LatLng> _traveledTrail = <LatLng>[];
  List<LatLng> _routeWaypoints = <LatLng>[];
  List<_RouteStep> _routeSteps = <_RouteStep>[];
  int _activeStepIndex = 0;
  int _simRouteIndex = 0;
  int _lastSpokenStepIndex = -1;

  double _routeTotalMeters = 2400.0;
  int _routeEtaMinutes = 6;
  double _currentSpeedKmh = 48.0;
  double _headingDeg = 180.0;
  double _zoom = 14.2;

  // 0 = Bright Navigator Scheme (2GIS/Yandex style), 1 = Dark Cockpit Night, 2 = OSM Detailed
  int _mapStyleIndex = 0;
  bool _hasRealGpsFix = false;
  bool _isCalculatingRoute = false;
  bool _isNavigating = true;
  bool _isFollowingCar = false;
  bool _isVoiceEnabled = true;
  bool _showRouteBuilderPanel = false;
  bool _showStepsDrawer = false;
  bool _isPipMinimized = false;

  // Draggable PiP camera overlay position inside the viewport (right, top)
  Offset _pipOffset = const Offset(10, 82);

  Timer? _gpsPollTimer;

  @override
  void initState() {
    super.initState();
    _traveledTrail.add(_currentLocation);
    _fetchRealRoadRoute(_pointA, _pointB, announceVoice: false);
    _startGpsTracking();
  }

  void _speak(String text) {
    if (!_isVoiceEnabled) return;
    if (kIsWeb) {
      WebFaceBridge.speakNavigationInstruction(text);
    }
  }

  void _moveActiveMap(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  /// Translates OSRM maneuver type + modifier into Russian turn instruction and icon.
  MapEntry<String, IconData> _parseManeuver(String type, String modifier) {
    if (type == 'arrive') {
      return const MapEntry<String, IconData>(
        'Вы прибыли в точку Б',
        Icons.flag_rounded,
      );
    }
    if (type == 'depart') {
      return const MapEntry<String, IconData>(
        'Начните движение',
        Icons.navigation_rounded,
      );
    }
    if (type == 'roundabout' || type == 'rotary') {
      return const MapEntry<String, IconData>(
        'Круговое движение',
        Icons.roundabout_right_rounded,
      );
    }
    if (modifier.contains('uturn')) {
      return const MapEntry<String, IconData>(
        'Развернитесь',
        Icons.u_turn_left_rounded,
      );
    }
    if (modifier == 'sharp left' || modifier == 'left') {
      return const MapEntry<String, IconData>(
        'Поверните налево',
        Icons.turn_left_rounded,
      );
    }
    if (modifier == 'slight left') {
      return const MapEntry<String, IconData>(
        'Держитесь левее',
        Icons.turn_slight_left_rounded,
      );
    }
    if (modifier == 'sharp right' || modifier == 'right') {
      return const MapEntry<String, IconData>(
        'Поверните направо',
        Icons.turn_right_rounded,
      );
    }
    if (modifier == 'slight right') {
      return const MapEntry<String, IconData>(
        'Держитесь правее',
        Icons.turn_slight_right_rounded,
      );
    }
    return const MapEntry<String, IconData>(
      'Двигайтесь прямо',
      Icons.straight_rounded,
    );
  }

  /// Queries OSRM real road routing engine for exact street geometry, distance, ETA, and turn-by-turn steps.
  Future<void> _fetchRealRoadRoute(
    LatLng start,
    LatLng end, {
    bool announceVoice = true,
  }) async {
    if (!mounted) return;
    setState(() => _isCalculatingRoute = true);

    try {
      final Uri url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final http.Response response =
          await http.get(url).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic>? routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final Map<String, dynamic> route =
              routes.first as Map<String, dynamic>;
          final double distMeters =
              (route['distance'] as num?)?.toDouble() ?? 1000.0;
          final double durationSec =
              (route['duration'] as num?)?.toDouble() ?? 300.0;

          final Map<String, dynamic>? geom =
              route['geometry'] as Map<String, dynamic>?;
          final List<dynamic>? coords = geom?['coordinates'] as List<dynamic>?;

          final List<LatLng> roadPoints = <LatLng>[];
          if (coords != null) {
            for (final dynamic pair in coords) {
              final List<dynamic> pt = pair as List<dynamic>;
              roadPoints.add(
                LatLng(
                  (pt[1] as num).toDouble(),
                  (pt[0] as num).toDouble(),
                ),
              );
            }
          }

          final List<_RouteStep> parsedSteps = <_RouteStep>[];
          final List<dynamic>? legs = route['legs'] as List<dynamic>?;
          if (legs != null && legs.isNotEmpty) {
            final Map<String, dynamic> leg = legs.first as Map<String, dynamic>;
            final List<dynamic>? steps = leg['steps'] as List<dynamic>?;
            if (steps != null) {
              for (int i = 0; i < steps.length; i++) {
                final Map<String, dynamic> step =
                    steps[i] as Map<String, dynamic>;
                final String rawName = (step['name'] as String? ?? '').trim();
                final double stepDist =
                    (step['distance'] as num?)?.toDouble() ?? 0.0;
                final Map<String, dynamic>? maneuver =
                    step['maneuver'] as Map<String, dynamic>?;
                final String mType = maneuver?['type'] as String? ?? 'turn';
                final String modifier =
                    maneuver?['modifier'] as String? ?? 'straight';
                final List<dynamic>? loc =
                    maneuver?['location'] as List<dynamic>?;
                final LatLng stepLatLng = (loc != null && loc.length >= 2)
                    ? LatLng(
                        (loc[1] as num).toDouble(),
                        (loc[0] as num).toDouble(),
                      )
                    : (roadPoints.isNotEmpty ? roadPoints.first : start);

                final MapEntry<String, IconData> parsed =
                    _parseManeuver(mType, modifier);
                final String streetLabel = rawName.isNotEmpty
                    ? rawName
                    : (mType == 'arrive' ? _pointBLabel : 'по маршруту');

                if (stepDist >= 15.0 || mType == 'arrive' || i == 0) {
                  parsedSteps.add(
                    _RouteStep(
                      actionText: parsed.key,
                      streetName: streetLabel,
                      distanceMeters: stepDist,
                      location: stepLatLng,
                      icon: parsed.value,
                    ),
                  );
                }
              }
            }
          }

          if (parsedSteps.isEmpty) {
            parsedSteps.add(
              _RouteStep(
                actionText: 'Двигайтесь прямо',
                streetName: _pointBLabel,
                distanceMeters: distMeters,
                location: start,
                icon: Icons.straight_rounded,
              ),
            );
          }

          final _RouteStep firstTurn =
              parsedSteps.length > 1 ? parsedSteps[1] : parsedSteps.first;

          if (mounted) {
            setState(() {
              _routeWaypoints =
                  roadPoints.isNotEmpty ? roadPoints : <LatLng>[start, end];
              _routeSteps = parsedSteps;
              _activeStepIndex = parsedSteps.length > 1 ? 1 : 0;
              _lastSpokenStepIndex = -1;
              _simRouteIndex = 0;
              _currentLocation = start;
              _traveledTrail
                ..clear()
                ..add(start);
              _routeTotalMeters = distMeters;
              _routeEtaMinutes = math.max(1, (durationSec / 60.0).round());
              _nextActionText = firstTurn.actionText;
              _nextStreetInstruction = firstTurn.streetName;
              _nextStepDistanceMeters = firstTurn.distanceMeters > 0
                  ? firstTurn.distanceMeters
                  : math.min(250.0, distMeters);
              _nextManeuverIcon = firstTurn.icon;
              _isCalculatingRoute = false;
            });

            if (announceVoice) {
              _speak(
                'Маршрут построен. Расстояние ${_formatMeters(distMeters)}, время в пути $_routeEtaMinutes минут. ${firstTurn.actionText} на ${firstTurn.streetName}.',
              );
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM route fallback: $e');
    }

    if (!mounted) return;
    final double fallbackDist =
        _distanceCalc.as(LengthUnit.Meter, start, end);
    setState(() {
      _routeWaypoints = <LatLng>[
        start,
        LatLng(
          start.latitude + (end.latitude - start.latitude) * 0.4,
          start.longitude,
        ),
        LatLng(
          start.latitude + (end.latitude - start.latitude) * 0.75,
          end.longitude,
        ),
        end,
      ];
      _routeSteps = <_RouteStep>[
        _RouteStep(
          actionText: 'Начните движение',
          streetName: _pointALabel,
          distanceMeters: fallbackDist * 0.4,
          location: start,
          icon: Icons.navigation_rounded,
        ),
        _RouteStep(
          actionText: 'Поверните направо',
          streetName: _pointBLabel,
          distanceMeters: fallbackDist * 0.6,
          location: end,
          icon: Icons.turn_right_rounded,
        ),
      ];
      _activeStepIndex = 1;
      _simRouteIndex = 0;
      _currentLocation = start;
      _routeTotalMeters = fallbackDist;
      _routeEtaMinutes = math.max(1, (fallbackDist / 750.0).round());
      _isCalculatingRoute = false;
    });
  }

  /// Geocodes an address string via OpenStreetMap Nominatim and returns its coordinates & short label.
  Future<_PresetPlace?> _geocodeAddress(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    for (final _PresetPlace p in _presets) {
      if (p.title.toLowerCase().contains(trimmed.toLowerCase())) {
        return p;
      }
    }

    try {
      final String fullQuery =
          trimmed.toLowerCase().contains('алматы') ||
                  trimmed.toLowerCase().contains('астана')
              ? trimmed
              : '$trimmed, Алматы';
      final Uri uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&limit=1&q=${Uri.encodeComponent(fullQuery)}',
      );
      final http.Response res = await http.get(
        uri,
        headers: const <String, String>{'Accept-Language': 'ru,kk,en'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final Map<String, dynamic> item =
              list.first as Map<String, dynamic>;
          final double lat = double.parse(item['lat'].toString());
          final double lon = double.parse(item['lon'].toString());
          final String displayName =
              (item['display_name'] as String? ?? trimmed).split(',').first;
          return _PresetPlace(displayName, LatLng(lat, lon));
        }
      }
    } catch (e) {
      debugPrint('Geocode error: $e');
    }
    return null;
  }

  /// Resolves both Point A and Point B from the text fields and starts in-app navigation.
  Future<void> _applyCustomRouteFromFields() async {
    HapticFeedback.selectionClick();
    setState(() => _isCalculatingRoute = true);

    final _PresetPlace? resolvedA = await _geocodeAddress(_fromController.text);
    final _PresetPlace? resolvedB = await _geocodeAddress(_toController.text);

    if (!mounted) return;
    setState(() {
      if (resolvedA != null) {
        _pointA = resolvedA.coords;
        _pointALabel = resolvedA.title;
        _fromController.text = resolvedA.title;
      }
      if (resolvedB != null) {
        _pointB = resolvedB.coords;
        _pointBLabel = resolvedB.title;
        _toController.text = resolvedB.title;
      }
      _showRouteBuilderPanel = false;
      _isNavigating = true;
    });

    final LatLng center = LatLng(
      (_pointA.latitude + _pointB.latitude) / 2.0,
      (_pointA.longitude + _pointB.longitude) / 2.0,
    );
    _moveActiveMap(center, 13.2);
    await _fetchRealRoadRoute(_pointA, _pointB, announceVoice: true);
  }

  void _swapPointsAandB() {
    HapticFeedback.selectionClick();
    setState(() {
      final LatLng tmpCoord = _pointA;
      _pointA = _pointB;
      _pointB = tmpCoord;

      final String tmpLabel = _pointALabel;
      _pointALabel = _pointBLabel;
      _pointBLabel = tmpLabel;

      _fromController.text = _pointALabel;
      _toController.text = _pointBLabel;
    });
    _fetchRealRoadRoute(_pointA, _pointB, announceVoice: true);
  }

  void _updateTurnByTurnProgress(LatLng carPos) {
    if (_routeSteps.isEmpty) return;

    // Find closest upcoming step
    for (int i = _activeStepIndex; i < _routeSteps.length; i++) {
      final _RouteStep step = _routeSteps[i];
      final double distToTurn =
          _distanceCalc.as(LengthUnit.Meter, carPos, step.location);
      if (distToTurn < 45.0 && i < _routeSteps.length - 1) {
        _activeStepIndex = i + 1;
        final _RouteStep nextStep = _routeSteps[_activeStepIndex];
        _nextActionText = nextStep.actionText;
        _nextStreetInstruction = nextStep.streetName;
        _nextManeuverIcon = nextStep.icon;
        if (_lastSpokenStepIndex != _activeStepIndex) {
          _lastSpokenStepIndex = _activeStepIndex;
          _speak('${nextStep.actionText} на ${nextStep.streetName}');
        }
        break;
      } else {
        _nextStepDistanceMeters = distToTurn;
        _nextActionText = step.actionText;
        _nextStreetInstruction = step.streetName;
        _nextManeuverIcon = step.icon;
        break;
      }
    }
  }

  Future<void> _startGpsTracking() async {
    if (kIsWeb) {
      WebFaceBridge.startWebGps();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _bgChannel.invokeMethod<bool>('startGps');
      } catch (_) {}
    }

    _gpsPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;

      // 1. Poll real browser GPS on Web (only override Point A if user is actually moving or requests GPS)
      if (kIsWeb) {
        final WebGpsData? webGps = WebFaceBridge.pollLatestWebGps();
        if (webGps != null && webGps.speedKmh > 2.5) {
          final LatLng newPos = LatLng(webGps.lat, webGps.lng);
          _hasRealGpsFix = true;
          _currentLocation = newPos;
          _currentSpeedKmh = webGps.speedKmh;
          _headingDeg = webGps.heading;
          _traveledTrail.add(newPos);
          _updateTurnByTurnProgress(newPos);
          if (_isFollowingCar) {
            _moveActiveMap(newPos, _zoom);
          }
          if (mounted) setState(() {});
          return;
        }
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // 2. Poll native Android LocationManager
        try {
          final Map<dynamic, dynamic>? gpsMap =
              await _bgChannel.invokeMethod<Map<dynamic, dynamic>>('getGps');
          if (gpsMap != null && gpsMap['lat'] != null && gpsMap['lng'] != null) {
            final double spd = (gpsMap['speedKmh'] as num?)?.toDouble() ?? 0.0;
            if (spd > 2.5) {
              final LatLng newPos = LatLng(
                (gpsMap['lat'] as num).toDouble(),
                (gpsMap['lng'] as num).toDouble(),
              );
              _hasRealGpsFix = true;
              _currentLocation = newPos;
              _currentSpeedKmh = spd;
              _headingDeg =
                  (gpsMap['heading'] as num?)?.toDouble() ?? _headingDeg;
              _traveledTrail.add(newPos);
              _updateTurnByTurnProgress(newPos);
              if (_isFollowingCar) {
                _moveActiveMap(newPos, _zoom);
              }
              if (mounted) setState(() {});
              return;
            }
          }
        } catch (_) {}
      }

      // 3. Built-in In-App Navigator Driving Mode along the OSRM street route
      if (_isNavigating && !_hasRealGpsFix && _routeWaypoints.length > 2) {
        if (_simRouteIndex < _routeWaypoints.length - 1) {
          final LatLng prev = _routeWaypoints[_simRouteIndex];
          _simRouteIndex++;
          final LatLng next = _routeWaypoints[_simRouteIndex];
          final double dLat = next.latitude - prev.latitude;
          final double dLng = next.longitude - prev.longitude;
          if (dLat.abs() > 0.000001 || dLng.abs() > 0.000001) {
            _headingDeg = (math.atan2(dLng, dLat) * 180 / math.pi + 360) % 360;
          }
          _currentLocation = next;
          _currentSpeedKmh = 46.0 + (DateTime.now().second % 11);
          _traveledTrail.add(next);
          _routeTotalMeters = math.max(
            0.0,
            _distanceCalc.as(LengthUnit.Meter, _currentLocation, _pointB),
          );
          _routeEtaMinutes = math.max(1, (_routeTotalMeters / 750.0).ceil());
          _updateTurnByTurnProgress(next);
          if (_isFollowingCar) {
            _moveActiveMap(next, _zoom);
          }
          setState(() {});
        } else if (_simRouteIndex == _routeWaypoints.length - 1) {
          _simRouteIndex++;
          _nextActionText = 'Вы прибыли в пункт назначения';
          _nextStreetInstruction = _pointBLabel;
          _nextManeuverIcon = Icons.flag_rounded;
          _nextStepDistanceMeters = 0;
          _currentSpeedKmh = 0;
          _speak('Вы прибыли в пункт назначения: $_pointBLabel');
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _gpsPollTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String _formatMeters(double m) {
    if (m >= 1000) {
      return '${(m / 1000).toStringAsFixed(1)} км';
    }
    return '${m.round()} м';
  }

  String get _activeTileUrl {
    if (_mapStyleIndex == 1) {
      // Dark Cockpit Navigation Map
      return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    } else if (_mapStyleIndex == 2) {
      // OpenStreetMap Detailed Street Map with House Numbers
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    // Bright 2GIS / Yandex-style High-Contrast Navigator Map
    return 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  }

  String get _activeMapStyleLabel {
    if (_mapStyleIndex == 0) return 'Навигатор День';
    if (_mapStyleIndex == 1) return 'Навигатор Ночь';
    return 'Детальная (Дома)';
  }

  void _onMapTapped(LatLng tappedLatLng) {
    HapticFeedback.selectionClick();
    final String coordsLabel =
        '${tappedLatLng.latitude.toStringAsFixed(4)}, ${tappedLatLng.longitude.toStringAsFixed(4)}';
    setState(() {
      if (_mapTapTarget == 'A') {
        _pointA = tappedLatLng;
        _pointALabel = 'Точка А ($coordsLabel)';
        _fromController.text = _pointALabel;
        _mapTapTarget = 'B';
      } else {
        _pointB = tappedLatLng;
        _pointBLabel = 'Точка Б ($coordsLabel)';
        _toController.text = _pointBLabel;
      }
      _isNavigating = true;
    });
    _fetchRealRoadRoute(_pointA, _pointB, announceVoice: true);
  }

  @override
  Widget build(BuildContext context) {
    // Remaining route points from current vehicle position to Point B
    final List<LatLng> remainingRoute = _routeWaypoints.isNotEmpty &&
            _simRouteIndex < _routeWaypoints.length
        ? _routeWaypoints.sublist(_simRouteIndex)
        : _routeWaypoints;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Built-In 60FPS Interactive Map Canvas (Drag, Pinch/Scroll Zoom, Tap to set Point A or Point B)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: _zoom,
                onPositionChanged: (MapCamera cam, bool hasGesture) {
                  _zoom = cam.zoom;
                  if (hasGesture && _isFollowingCar) {
                    setState(() => _isFollowingCar = false);
                  }
                },
                onTap: (TapPosition tapPos, LatLng tappedLatLng) =>
                    _onMapTapped(tappedLatLng),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: _activeTileUrl,
                  userAgentPackageName: 'com.antisleep.ai',
                ),
                // Traveled trail (gray) + Remaining Active A -> B Road Route Polyline (2GIS/Yandex bright green)
                PolylineLayer(
                  polylines: <Polyline>[
                    if (_traveledTrail.length > 1)
                      Polyline(
                        points: _traveledTrail,
                        strokeWidth: 5.0,
                        color: Colors.grey.withValues(alpha: 0.65),
                      ),
                    if (remainingRoute.length > 1)
                      Polyline(
                        points: remainingRoute,
                        strokeWidth: 7.5,
                        color: const Color(0xFF00C853),
                        borderStrokeWidth: 2.5,
                        borderColor: const Color(0xFF003816),
                      ),
                  ],
                ),
                // Turn Maneuver Dots + Point A Marker + Point B Marker + Live Driver Vehicle Arrow
                MarkerLayer(
                  markers: <Marker>[
                    // Turn maneuver dots along the route
                    ..._routeSteps.skip(1).map((_RouteStep step) {
                      return Marker(
                        point: step.location,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF003816),
                              width: 2.5,
                            ),
                          ),
                        ),
                      );
                    }),
                    // Point A (Start) Marker
                    Marker(
                      point: _pointA,
                      width: 38,
                      height: 38,
                      child: Container(
                        decoration: BoxDecoration(
                          color: CockpitColors.safeGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'А',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    // Point B (Destination) Marker
                    Marker(
                      point: _pointB,
                      width: 42,
                      height: 42,
                      child: Container(
                        decoration: BoxDecoration(
                          color: CockpitColors.dangerRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Б',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    // Live Driver Vehicle Arrow
                    Marker(
                      point: _currentLocation,
                      width: 48,
                      height: 48,
                      child: Transform.rotate(
                        angle: _headingDeg * math.pi / 180.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1E88E5).withValues(alpha: 0.25),
                            border: Border.all(
                              color: Colors.white,
                              width: 2.5,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(color: Colors.black45, blurRadius: 8),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.navigation_rounded,
                              color: Color(0xFF00E676),
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 2. Top Built-In Turn-by-Turn Navigator Banner + Expandable "А -> Б" Route Builder & Steps Drawer
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Main Turn-by-Turn Maneuver Header (like 2GIS / Yandex Navigator)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: CockpitColors.card.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.5),
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        // Turn Direction Icon Box
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _showStepsDrawer = !_showStepsDrawer;
                              _showRouteBuilderPanel = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: CockpitColors.safeGreen
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _nextManeuverIcon,
                              color: CockpitColors.safeGreen,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Distance + Action + Street Name + A -> B subtitle
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _showStepsDrawer = !_showStepsDrawer;
                                _showRouteBuilderPanel = false;
                              });
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Text(
                                      _formatMeters(_nextStepDistanceMeters),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '• $_nextActionText',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: CockpitColors.safeGreen,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isCalculatingRoute
                                      ? 'Построение маршрута А → Б...'
                                      : '$_nextStreetInstruction  (А: $_pointALabel → Б: $_pointBLabel)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: CockpitColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Voice Guidance Toggle Button (🔊 / 🔇)
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isVoiceEnabled = !_isVoiceEnabled);
                            if (_isVoiceEnabled) {
                              _speak('Голосовые подсказки включены');
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: _isVoiceEnabled
                                  ? CockpitColors.safeGreen
                                      .withValues(alpha: 0.16)
                                  : CockpitColors.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isVoiceEnabled
                                    ? CockpitColors.safeGreen
                                    : CockpitColors.cardBorder,
                              ),
                            ),
                            child: Icon(
                              _isVoiceEnabled
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              color: _isVoiceEnabled
                                  ? CockpitColors.safeGreen
                                  : CockpitColors.textMuted,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Toggle "А -> Б" Route Builder Panel Button
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _showRouteBuilderPanel = !_showRouteBuilderPanel;
                              _showStepsDrawer = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _showRouteBuilderPanel
                                  ? CockpitColors.safeGreen
                                  : const Color(0xFFFFCC00),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  _showRouteBuilderPanel
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.alt_route_rounded,
                                  color: Colors.black,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showRouteBuilderPanel ? 'Скрыть' : 'А → Б',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Expandable In-App Turn-by-Turn Steps List ("Маневры по маршруту")
                  if (_showStepsDrawer && _routeSteps.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 210),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CockpitColors.card.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: CockpitColors.cardBorder),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black87, blurRadius: 16),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                'Манёвры по маршруту (${_routeSteps.length})',
                                style: const TextStyle(
                                  color: CockpitColors.textWhite,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              InkWell(
                                onTap: () =>
                                    setState(() => _showStepsDrawer = false),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: CockpitColors.textMuted,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _routeSteps.length,
                              itemBuilder: (BuildContext ctx, int idx) {
                                final _RouteStep s = _routeSteps[idx];
                                final bool isCurrent = idx == _activeStepIndex;
                                return InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _moveActiveMap(s.location, 15.5);
                                    _speak('${s.actionText} на ${s.streetName}');
                                    setState(() => _showStepsDrawer = false);
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          s.icon,
                                          size: 18,
                                          color: isCurrent
                                              ? CockpitColors.safeGreen
                                              : const Color(0xFFFFCC00),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${s.actionText} • ${s.streetName}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? CockpitColors.safeGreen
                                                  : CockpitColors.textWhite,
                                              fontWeight: isCurrent
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatMeters(s.distanceMeters),
                                          style: const TextStyle(
                                            color: CockpitColors.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Expandable In-App "Откуда (А) -> Куда (Б)" Route Builder Panel
                  if (_showRouteBuilderPanel)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CockpitColors.card.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: CockpitColors.cardBorder),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black87, blurRadius: 16),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Row A: Откуда (Точка А)
                          Row(
                            children: <Widget>[
                              Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: CockpitColors.safeGreen,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'А',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _fromController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                    onTap: () {
                                      setState(() => _mapTapTarget = 'A');
                                    },
                                    onSubmitted: (_) =>
                                        _applyCustomRouteFromFields(),
                                    decoration: InputDecoration(
                                      hintText: 'Откуда (Точка А)',
                                      hintStyle: const TextStyle(
                                        color: CockpitColors.textMuted,
                                        fontSize: 11,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      filled: true,
                                      fillColor: CockpitColors.bg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: _mapTapTarget == 'A'
                                              ? CockpitColors.safeGreen
                                              : CockpitColors.cardBorder,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Поменять А и Б местами',
                                onPressed: _swapPointsAandB,
                                icon: const Icon(
                                  Icons.swap_vert_rounded,
                                  color: Color(0xFFFFCC00),
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Row B: Куда (Точка Б)
                          Row(
                            children: <Widget>[
                              Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: CockpitColors.dangerRed,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Б',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _toController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                    onTap: () {
                                      setState(() => _mapTapTarget = 'B');
                                    },
                                    onSubmitted: (_) =>
                                        _applyCustomRouteFromFields(),
                                    decoration: InputDecoration(
                                      hintText: 'Куда (Точка Б — улица или место)',
                                      hintStyle: const TextStyle(
                                        color: CockpitColors.textMuted,
                                        fontSize: 11,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      filled: true,
                                      fillColor: CockpitColors.bg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: _mapTapTarget == 'B'
                                              ? CockpitColors.dangerRed
                                              : CockpitColors.cardBorder,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CockpitColors.safeGreen,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(52, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _applyCustomRouteFromFields,
                                child: const Text(
                                  'Поехали!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Map tap target selector
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  _mapTapTarget == 'A'
                                      ? 'Клик по карте ставит: Точку А (Старт)'
                                      : 'Клик по карте ставит: Точку Б (Финиш)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _mapTapTarget == 'A'
                                        ? CockpitColors.safeGreen
                                        : const Color(0xFFFFCC00),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _mapTapTarget =
                                        _mapTapTarget == 'A' ? 'B' : 'A';
                                  });
                                },
                                child: Text(
                                  _mapTapTarget == 'A'
                                      ? 'Выбрать Б'
                                      : 'Выбрать А на карте',
                                  style: const TextStyle(
                                    color: CockpitColors.textWhite,
                                    fontSize: 10,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 1-Tap Quick Route Presets
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _presets.map((_PresetPlace place) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: CockpitColors.bg,
                                    side: const BorderSide(
                                      color: CockpitColors.cardBorder,
                                    ),
                                    label: Text(
                                      place.title,
                                      style: const TextStyle(
                                        color: CockpitColors.textWhite,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (_mapTapTarget == 'A') {
                                          _pointA = place.coords;
                                          _pointALabel = place.title;
                                          _fromController.text = place.title;
                                          _mapTapTarget = 'B';
                                        } else {
                                          _pointB = place.coords;
                                          _pointBLabel = place.title;
                                          _toController.text = place.title;
                                        }
                                        _showRouteBuilderPanel = false;
                                        _isNavigating = true;
                                      });
                                      _moveActiveMap(place.coords, 13.5);
                                      _fetchRealRoadRoute(
                                        _pointA,
                                        _pointB,
                                        announceVoice: true,
                                      );
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 3. Left Map Controls (Zoom +, Zoom -, Follow Car GPS, Map Style Switcher)
            Positioned(
              left: 10,
              bottom: 68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildMapIconButton(
                    icon: Icons.add_rounded,
                    onTap: () {
                      _zoom = (_zoom + 1.0).clamp(3.0, 18.5);
                      _moveActiveMap(_mapController.camera.center, _zoom);
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMapIconButton(
                    icon: Icons.remove_rounded,
                    onTap: () {
                      _zoom = (_zoom - 1.0).clamp(3.0, 18.5);
                      _moveActiveMap(_mapController.camera.center, _zoom);
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMapIconButton(
                    icon: _isFollowingCar
                        ? Icons.navigation_rounded
                        : Icons.my_location_rounded,
                    color: _isFollowingCar
                        ? const Color(0xFFFFCC00)
                        : CockpitColors.safeGreen,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isFollowingCar = true);
                      _moveActiveMap(_currentLocation, 15.2);
                    },
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _mapStyleIndex = (_mapStyleIndex + 1) % 3;
                      });
                    },
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: CockpitColors.card.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFCC00)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.layers_rounded,
                            color: Color(0xFFFFCC00),
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _activeMapStyleLabel,
                            style: const TextStyle(
                              color: Color(0xFFFFCC00),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 4. Bottom Built-In Navigator Dashboard (Speed Limit + Speed + ETA + In-App "В путь / Пауза" Button)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: CockpitColors.card.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Row(
                  children: <Widget>[
                    // Speed Limit Sign (60)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: CockpitColors.dangerRed,
                          width: 3.2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '60',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '${_currentSpeedKmh.round()} ${appState.t('speedUnit')} • $_routeEtaMinutes ${appState.t('etaMin')} (${_formatMeters(_routeTotalMeters)})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CockpitColors.textWhite,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$_pointALabel → $_pointBLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CockpitColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // In-App Start / Pause Active Guidance Button ("В путь" / "Пауза")
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          if (_simRouteIndex >= _routeWaypoints.length - 1) {
                            _simRouteIndex = 0;
                            _currentLocation = _pointA;
                            _traveledTrail
                              ..clear()
                              ..add(_pointA);
                            _isNavigating = true;
                          } else {
                            _isNavigating = !_isNavigating;
                          }
                          if (_isNavigating) {
                            _isFollowingCar = true;
                          }
                        });
                        if (_isNavigating) {
                          _speak(
                            'Ведение по маршруту активно. $_nextActionText на $_nextStreetInstruction',
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _isNavigating
                              ? CockpitColors.safeGreen
                              : const Color(0xFFFFCC00),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              _isNavigating
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isNavigating ? 'Ведение' : 'В путь',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. Compact Draggable & Collapsible Floating PiP Live Camera Preview Window
            Positioned(
              right: _pipOffset.dx,
              top: _pipOffset.dy,
              width: _isPipMinimized ? 52 : 100,
              height: _isPipMinimized ? 52 : 132,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isPipMinimized = !_isPipMinimized);
                },
                onPanUpdate: (DragUpdateDetails details) {
                  setState(() {
                    final double maxRight = math.max(
                      8.0,
                      constraints.maxWidth - (_isPipMinimized ? 62.0 : 110.0),
                    );
                    final double maxTop = math.max(
                      74.0,
                      constraints.maxHeight - (_isPipMinimized ? 70.0 : 150.0),
                    );
                    final double newRight =
                        (_pipOffset.dx - details.delta.dx).clamp(8.0, maxRight);
                    final double newTop =
                        (_pipOffset.dy + details.delta.dy).clamp(74.0, maxTop);
                    _pipOffset = Offset(newRight, newTop);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: CockpitColors.bg,
                    borderRadius:
                        BorderRadius.circular(_isPipMinimized ? 26 : 16),
                    border: Border.all(
                      color: widget.isEyesOpen
                          ? CockpitColors.safeGreen
                          : CockpitColors.dangerRed,
                      width: 2.2,
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Colors.black87, blurRadius: 12),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(_isPipMinimized ? 24 : 14),
                    child: _isPipMinimized
                        ? Center(
                            child: Icon(
                              Icons.videocam_rounded,
                              color: widget.isEyesOpen
                                  ? CockpitColors.safeGreen
                                  : CockpitColors.dangerRed,
                              size: 24,
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              widget.pipCameraPreview,
                              Positioned(
                                bottom: 4,
                                left: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.isEyesOpen
                                        ? appState.t('eyeOpen')
                                        : appState.t('eyeClosed'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: widget.isEyesOpen
                                          ? CockpitColors.safeGreen
                                          : CockpitColors.dangerRed,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMapIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = CockpitColors.textWhite,
  }) {
    return Material(
      color: CockpitColors.card.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: CockpitColors.cardBorder),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }
}
