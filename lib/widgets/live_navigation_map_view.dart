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

/// Preset location model for 1-tap Point A / Point B selection.
class _PresetPlace {
  final String title;
  final LatLng coords;
  const _PresetPlace(this.title, this.coords);
}

/// Single Turn-by-Turn maneuver step inside the built-in 2GIS 3D navigator.
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

/// Directional arrow marker placed along the active road route.
class _DirectionArrowPoint {
  final LatLng position;
  final double bearingDeg;
  const _DirectionArrowPoint(this.position, this.bearingDeg);
}

/// Authentic 3D Perspective 2GIS Navigator with Smooth 60FPS Road Movement, Auto-Rotating Camera, Directional Arrows & AI Guard PiP.
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

  /// Official 2GIS API Key (MapGL 3D WebGL, 2GIS Directions, 2GIS Car Routing & 2GIS Places Catalog)
  static const String _twoGisApiKey = '01a1951a-28ee-4a07-9e99-40ba82333bb0';

  static const List<_PresetPlace> _presets = <_PresetPlace>[
    _PresetPlace('Астана: Туркестан / Улы Дала', LatLng(51.1065, 71.4145)),
    _PresetPlace('Астана: Акмешит (Space Office)', LatLng(51.1142, 71.4218)),
    _PresetPlace('Астана: Байтерек', LatLng(51.1283, 71.4305)),
    _PresetPlace('Астана: Mega Silk Way', LatLng(51.0892, 71.4146)),
    _PresetPlace('Алматы: Абая / Достык', LatLng(43.2415, 76.9562)),
    _PresetPlace('Алматы: Достык / Аль-Фараби', LatLng(43.2220, 76.9585)),
    _PresetPlace('Алматы: ТРЦ Mega', LatLng(43.2016, 76.8924)),
    _PresetPlace('Алматы: ВСК Медеу', LatLng(43.1574, 77.0590)),
  ];

  // Exact street geometry along Turkestan Street / Botanical Park in Astana (matching the 2GIS screenshot)
  static const List<LatLng> _defaultAstanaStreetGeometry = <LatLng>[
    LatLng(51.10865, 71.42130), // Courtyard C1.2 start
    LatLng(51.10925, 71.42110), // P1 courtyard exit
    LatLng(51.10935, 71.42205), // Turn onto Turkestan street
    LatLng(51.10895, 71.42245), // Turkestan street lane
    LatLng(51.10980, 71.42295),
    LatLng(51.11085, 71.42355),
    LatLng(51.11190, 71.42415),
    LatLng(51.11305, 71.42480),
    LatLng(51.11420, 71.42545), // Intersection with Akmeshit
    LatLng(51.11535, 71.42610),
    LatLng(51.11650, 71.42675),
    LatLng(51.11780, 71.42750), // Towards Uly Dala / Syganak
    LatLng(51.11910, 71.42825),
    LatLng(51.12040, 71.42900),
  ];

  final MapController _mapController = MapController();
  final TextEditingController _fromController =
      TextEditingController(text: 'Моё местоположение • ул. Туркестан, 16');
  final TextEditingController _toController =
      TextEditingController(text: 'ул. Акмешит, 9 (Space Office)');
  final Distance _distanceCalc = const Distance();

  LatLng _pointA = const LatLng(51.10865, 71.42130);
  LatLng _pointB = const LatLng(51.12040, 71.42900);
  LatLng _currentLocation = const LatLng(51.10865, 71.42130);

  String _pointALabel = 'ул. Туркестан, 16';
  String _pointBLabel = 'ул. Акмешит, 9';
  String _nextActionText = 'Прямо';
  String _nextStreetInstruction = 'Туркестан';
  IconData _nextManeuverIcon = Icons.arrow_upward_rounded;
  double _nextStepDistanceMeters = 240.0;

  String _mapTapTarget = 'B';
  int _selectedTransportMode = 0; // 0 = Авто, 1 = Автобус, 2 = Такси, 3 = Пешком

  final List<LatLng> _traveledTrail = <LatLng>[];
  List<LatLng> _routeWaypoints = <LatLng>[];
  List<_DirectionArrowPoint> _routeDirectionArrows = <_DirectionArrowPoint>[];
  List<_RouteStep> _routeSteps = <_RouteStep>[];
  int _activeStepIndex = 0;
  int _lastSpokenStepIndex = -1;

  // Smooth continuous interpolation state (0.0 -> _routeWaypoints.length - 1)
  double _smoothRouteCursor = 0.0;

  double _routeTotalMeters = 17000.0;
  int _routeEtaMinutes = 51;
  double _currentSpeedKmh = 45.0;
  int _speedLimitKmh = 60;
  int _trafficScore = 5;
  double _headingDeg = 28.0;
  double _zoom = 17.0;

  // 0 = Real 2GIS Map Tiles, 1 = Dark Cockpit 3D, 2 = OSM Detailed
  int _mapStyleIndex = 0;
  bool _hasRealGpsFix = false;
  bool _isCalculatingRoute = false;

  // Active 3D Navigation & Camera Follow enabled by default so road movement is immediately visible!
  bool _isNavigating = true;
  bool _isFollowingCar = true;
  bool _is3DPerspective = true;
  bool _isVoiceEnabled = true;
  bool _showParkingOverlay = false;
  bool _showRouteBuilderPanel = false;
  bool _showMenuSheet = false;
  bool _isPipExpanded = false;

  Timer? _smoothMotionTimer;
  Timer? _gpsPollTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebFaceBridge.registerYandexMapView(
        'antisleep-2gis-map',
        _pointA.latitude,
        _pointA.longitude,
        _pointB.latitude,
        _pointB.longitude,
      );
    }
    // 1. Immediately initialize dense street route so road + movement work in 0ms
    _applyWaypointsAndBuildArrows(
      _defaultAstanaStreetGeometry,
      totalDistMeters: 17000.0,
      etaMin: 51,
    );
    // 2. Query official 2GIS Routing API + OSRM for exact turn steps
    _fetchRealRoadRoute(_pointA, _pointB, announceVoice: false);
    // 3. Start 25FPS smooth forward road movement & 3D camera rotation
    _startSmoothNavigatorEngine();
    _startGpsTracking();
  }

  void _syncRouteTo2GisWebGl() {
    if (!kIsWeb) return;
    final List<List<double>> pts = _routeWaypoints
        .map((LatLng p) => <double>[p.latitude, p.longitude])
        .toList();
    WebFaceBridge.updateYandexRoute(
      pts,
      _pointA.latitude,
      _pointA.longitude,
      _pointB.latitude,
      _pointB.longitude,
    );
  }

  /// Subdivides route segments into dense ~8-meter points and generates white directional arrows along the road.
  void _applyWaypointsAndBuildArrows(
    List<LatLng> rawPoints, {
    required double totalDistMeters,
    required int etaMin,
  }) {
    if (rawPoints.length < 2) return;

    final List<LatLng> dense = <LatLng>[];
    final List<_DirectionArrowPoint> arrows = <_DirectionArrowPoint>[];
    double accumArrowDist = 0.0;

    for (int i = 0; i < rawPoints.length - 1; i++) {
      final LatLng a = rawPoints[i];
      final LatLng b = rawPoints[i + 1];
      final double segMeters = _distanceCalc.as(LengthUnit.Meter, a, b);
      final double dLat = b.latitude - a.latitude;
      final double dLng = b.longitude - a.longitude;
      final double bearing =
          (math.atan2(dLng, dLat) * 180.0 / math.pi + 360.0) % 360.0;

      final int subdivisions = math.max(1, (segMeters / 6.0).round());
      for (int s = 0; s < subdivisions; s++) {
        final double t = s / subdivisions;
        final LatLng pt = LatLng(
          a.latitude + dLat * t,
          a.longitude + dLng * t,
        );
        dense.add(pt);
        accumArrowDist += segMeters / subdivisions;
        if (accumArrowDist >= 42.0) {
          accumArrowDist = 0.0;
          arrows.add(_DirectionArrowPoint(pt, bearing));
        }
      }
    }
    dense.add(rawPoints.last);

    _routeWaypoints = dense;
    _routeDirectionArrows = arrows;
    _smoothRouteCursor = 0.0;
    _currentLocation = dense.first;
    _traveledTrail
      ..clear()
      ..add(dense.first);
    _routeTotalMeters = totalDistMeters;
    _routeEtaMinutes = etaMin;

    if (dense.length > 1) {
      final double dLat = dense[1].latitude - dense[0].latitude;
      final double dLng = dense[1].longitude - dense[0].longitude;
      _headingDeg = (math.atan2(dLng, dLat) * 180.0 / math.pi + 360.0) % 360.0;
    }
  }

  void _speak(String text) {
    if (!_isVoiceEnabled) return;
    if (kIsWeb) {
      WebFaceBridge.speakNavigationInstruction(text);
    }
  }

  void _moveAndRotateCamera(LatLng center, double zoom, double headingDeg) {
    if (kIsWeb) {
      WebFaceBridge.update2GisCamera3D(
        center.latitude,
        center.longitude,
        zoom,
        headingDeg,
        _is3DPerspective ? 48.0 : 0.0,
      );
    }
    try {
      _mapController.moveAndRotate(
        center,
        zoom,
        _is3DPerspective ? -headingDeg : 0.0,
      );
    } catch (_) {
      try {
        _mapController.move(center, zoom);
      } catch (_) {}
    }
  }

  /// High-frame-rate (25 FPS) smooth vehicle & 3D road camera movement engine.
  void _startSmoothNavigatorEngine() {
    _smoothMotionTimer?.cancel();
    _smoothMotionTimer =
        Timer.periodic(const Duration(milliseconds: 40), (Timer timer) {
      if (!mounted || !_isNavigating || _hasRealGpsFix) return;
      if (_routeWaypoints.length < 2) return;

      // Advance smoothly along the dense 6-meter waypoints (~13.5 m/s = ~48 km/h)
      _smoothRouteCursor += 0.095;
      if (_smoothRouteCursor >= _routeWaypoints.length - 1) {
        // Loop continuously for live demo / defense so the navigator is always showing live motion
        _smoothRouteCursor = 0.0;
        _traveledTrail
          ..clear()
          ..add(_routeWaypoints.first);
      }

      final int idx = _smoothRouteCursor.floor();
      final int nextIdx = math.min(idx + 1, _routeWaypoints.length - 1);
      final double frac = _smoothRouteCursor - idx;

      final LatLng p1 = _routeWaypoints[idx];
      final LatLng p2 = _routeWaypoints[nextIdx];

      final LatLng interpolatedPos = LatLng(
        p1.latitude + (p2.latitude - p1.latitude) * frac,
        p1.longitude + (p2.longitude - p1.longitude) * frac,
      );

      final double dLat = p2.latitude - p1.latitude;
      final double dLng = p2.longitude - p1.longitude;
      if (dLat.abs() > 0.0000001 || dLng.abs() > 0.0000001) {
        final double targetHeading =
            (math.atan2(dLng, dLat) * 180.0 / math.pi + 360.0) % 360.0;
        // Smooth angular interpolation so turns look like a real 3D navigator
        double diff = targetHeading - _headingDeg;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;
        _headingDeg = (_headingDeg + diff * 0.22 + 360.0) % 360.0;
      }

      _currentLocation = interpolatedPos;
      _currentSpeedKmh = 46.0 + ((idx ~/ 8) % 9);
      _speedLimitKmh = 60;

      if (_traveledTrail.isEmpty ||
          _distanceCalc.as(
                  LengthUnit.Meter, _traveledTrail.last, interpolatedPos) >
              3.5) {
        _traveledTrail.add(interpolatedPos);
      }

      _updateTurnByTurnProgress(interpolatedPos);

      if (_isFollowingCar) {
        _moveAndRotateCamera(interpolatedPos, _zoom, _headingDeg);
      }

      setState(() {});
    });
  }

  /// Translates OSRM maneuver type + modifier into Russian turn instruction and icon.
  MapEntry<String, IconData> _parseManeuver(String type, String modifier) {
    if (type == 'arrive') {
      return const MapEntry<String, IconData>(
        'Прибытие',
        Icons.flag_rounded,
      );
    }
    if (type == 'depart') {
      return const MapEntry<String, IconData>(
        'Прямо',
        Icons.arrow_upward_rounded,
      );
    }
    if (type == 'roundabout' || type == 'rotary') {
      return const MapEntry<String, IconData>(
        'Кольцо',
        Icons.roundabout_right_rounded,
      );
    }
    if (modifier.contains('uturn')) {
      return const MapEntry<String, IconData>(
        'Разворот',
        Icons.u_turn_left_rounded,
      );
    }
    if (modifier == 'sharp left' || modifier == 'left') {
      return const MapEntry<String, IconData>(
        'Налево',
        Icons.turn_left_rounded,
      );
    }
    if (modifier == 'slight left') {
      return const MapEntry<String, IconData>(
        'Левее',
        Icons.turn_slight_left_rounded,
      );
    }
    if (modifier == 'sharp right' || modifier == 'right') {
      return const MapEntry<String, IconData>(
        'Направо',
        Icons.turn_right_rounded,
      );
    }
    if (modifier == 'slight right') {
      return const MapEntry<String, IconData>(
        'Правее',
        Icons.turn_slight_right_rounded,
      );
    }
    return const MapEntry<String, IconData>(
      'Прямо',
      Icons.arrow_upward_rounded,
    );
  }

  /// Queries official 2GIS Car Routing API (with OSRM fallback) for exact street geometry, distance, ETA, and turn-by-turn steps.
  Future<void> _fetchRealRoadRoute(
    LatLng start,
    LatLng end, {
    bool announceVoice = true,
  }) async {
    if (!mounted) return;
    setState(() => _isCalculatingRoute = true);

    // 1. Try Official 2GIS Car Routing API (key: 01a1951a-28ee-4a07-9e99-40ba82333bb0)
    try {
      final Uri dgisRoutingUri = Uri.parse(
        'https://routing.api.2gis.com/carrouting/6.0.0/global?key=$_twoGisApiKey',
      );
      final http.Response dgisRes = await http
          .post(
            dgisRoutingUri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'points': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'walking',
                  'x': start.longitude,
                  'y': start.latitude,
                },
                <String, dynamic>{
                  'type': 'walking',
                  'x': end.longitude,
                  'y': end.latitude,
                },
              ],
              'type': 'jam',
              'output': 'detailed',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (dgisRes.statusCode == 200) {
        final Map<String, dynamic> dgisData =
            jsonDecode(dgisRes.body) as Map<String, dynamic>;
        final List<dynamic>? resultList =
            dgisData['result'] as List<dynamic>?;
        if (resultList != null && resultList.isNotEmpty) {
          final Map<String, dynamic> firstRoute =
              resultList.first as Map<String, dynamic>;
          final double totalDist =
              (firstRoute['total_distance'] as num?)?.toDouble() ?? 1500.0;
          final double totalDur =
              (firstRoute['total_duration'] as num?)?.toDouble() ?? 300.0;

          final List<LatLng> dgisPoints = <LatLng>[];
          final List<_RouteStep> dgisSteps = <_RouteStep>[];

          final List<dynamic>? maneuvers =
              firstRoute['maneuvers'] as List<dynamic>?;
          if (maneuvers != null) {
            for (final dynamic m in maneuvers) {
              final Map<String, dynamic> man = m as Map<String, dynamic>;
              final String comment =
                  (man['comment'] as String? ?? 'Прямо').trim();
              final Map<String, dynamic>? outPath =
                  man['outcoming_path'] as Map<String, dynamic>?;
              final double segDist =
                  (outPath?['distance'] as num?)?.toDouble() ?? 100.0;
              final List<dynamic>? names =
                  outPath?['names'] as List<dynamic>?;
              final String streetName = (names != null && names.isNotEmpty)
                  ? names.first.toString()
                  : _pointBLabel;

              final List<dynamic>? geomList =
                  outPath?['geometry'] as List<dynamic>?;
              LatLng? firstStepPt;
              if (geomList != null) {
                for (final dynamic g in geomList) {
                  final Map<String, dynamic> gMap = g as Map<String, dynamic>;
                  final String selection =
                      gMap['selection'] as String? ?? '';
                  if (selection.startsWith('LINESTRING')) {
                    final String inner = selection
                        .replaceAll('LINESTRING(', '')
                        .replaceAll(')', '');
                    for (final String pairStr in inner.split(',')) {
                      final List<String> parts =
                          pairStr.trim().split(RegExp(r'\s+'));
                      if (parts.length >= 2) {
                        final double? lng = double.tryParse(parts[0]);
                        final double? lat = double.tryParse(parts[1]);
                        if (lat != null && lng != null) {
                          final LatLng pt = LatLng(lat, lng);
                          dgisPoints.add(pt);
                          firstStepPt ??= pt;
                        }
                      }
                    }
                  }
                }
              }

              if (firstStepPt != null) {
                dgisSteps.add(
                  _RouteStep(
                    actionText: comment,
                    streetName: streetName,
                    distanceMeters: segDist,
                    location: firstStepPt,
                    icon: comment.toLowerCase().contains('лев')
                        ? Icons.turn_left_rounded
                        : (comment.toLowerCase().contains('прав')
                            ? Icons.turn_right_rounded
                            : Icons.arrow_upward_rounded),
                  ),
                );
              }
            }
          }

          if (dgisPoints.length > 1 && mounted) {
            final _RouteStep firstTurn = dgisSteps.isNotEmpty
                ? dgisSteps.first
                : _RouteStep(
                    actionText: 'Прямо',
                    streetName: _pointBLabel,
                    distanceMeters: 250,
                    location: start,
                    icon: Icons.arrow_upward_rounded,
                  );
            setState(() {
              _applyWaypointsAndBuildArrows(
                dgisPoints,
                totalDistMeters: totalDist,
                etaMin: math.max(1, (totalDur / 60.0).round()),
              );
              _routeSteps = dgisSteps;
              _activeStepIndex = 0;
              _lastSpokenStepIndex = -1;
              _nextActionText = firstTurn.actionText;
              _nextStreetInstruction = firstTurn.streetName;
              _nextStepDistanceMeters = firstTurn.distanceMeters;
              _nextManeuverIcon = firstTurn.icon;
              _isCalculatingRoute = false;
            });
            _syncRouteTo2GisWebGl();
            if (announceVoice) {
              _speak(
                'Маршрут 2ГИС построен. ${_formatMeters(totalDist)}, время в пути $_routeEtaMinutes минут.',
              );
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('2GIS Routing API fallback to OSRM: $e');
    }

    // 2. Fallback to OSRM street routing engine
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
                    : (mType == 'arrive' ? _pointBLabel : 'Туркестан');

                if (stepDist >= 10.0 || mType == 'arrive' || i == 0) {
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
                actionText: 'Прямо',
                streetName: _pointBLabel,
                distanceMeters: distMeters,
                location: start,
                icon: Icons.arrow_upward_rounded,
              ),
            );
          }

          final _RouteStep firstTurn =
              parsedSteps.length > 1 ? parsedSteps[1] : parsedSteps.first;

          if (mounted) {
            setState(() {
              _applyWaypointsAndBuildArrows(
                roadPoints.length > 1 ? roadPoints : _defaultAstanaStreetGeometry,
                totalDistMeters: distMeters,
                etaMin: math.max(1, (durationSec / 60.0).round()),
              );
              _routeSteps = parsedSteps;
              _activeStepIndex = parsedSteps.length > 1 ? 1 : 0;
              _lastSpokenStepIndex = -1;
              _nextActionText = firstTurn.actionText;
              _nextStreetInstruction = firstTurn.streetName;
              _nextStepDistanceMeters = firstTurn.distanceMeters > 0
                  ? firstTurn.distanceMeters
                  : math.min(250.0, distMeters);
              _nextManeuverIcon = firstTurn.icon;
              _isCalculatingRoute = false;
            });
            _syncRouteTo2GisWebGl();

            if (announceVoice) {
              _speak(
                'Маршрут построен. ${_formatMeters(distMeters)}, время в пути $_routeEtaMinutes минут. ${firstTurn.actionText} на ${firstTurn.streetName}.',
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
    setState(() => _isCalculatingRoute = false);
  }

  /// Geocodes an address string via Official 2GIS Catalog API (with Nominatim fallback) and returns its coordinates & short label.
  Future<_PresetPlace?> _geocodeAddress(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    for (final _PresetPlace p in _presets) {
      if (p.title.toLowerCase().contains(trimmed.toLowerCase())) {
        return p;
      }
    }

    // 1. Official 2GIS Places & Geocoder API (key: 01a1951a-28ee-4a07-9e99-40ba82333bb0)
    try {
      final Uri dgisUri = Uri.parse(
        'https://catalog.api.2gis.com/3.0/items'
        '?q=${Uri.encodeComponent(trimmed)}'
        '&fields=items.point,items.full_name'
        '&key=$_twoGisApiKey',
      );
      final http.Response dgisRes =
          await http.get(dgisUri).timeout(const Duration(seconds: 5));
      if (dgisRes.statusCode == 200) {
        final Map<String, dynamic> dgisJson =
            jsonDecode(dgisRes.body) as Map<String, dynamic>;
        final Map<String, dynamic>? result =
            dgisJson['result'] as Map<String, dynamic>?;
        final List<dynamic>? items = result?['items'] as List<dynamic>?;
        if (items != null && items.isNotEmpty) {
          for (final dynamic rawItem in items) {
            final Map<String, dynamic> item =
                rawItem as Map<String, dynamic>;
            final Map<String, dynamic>? pt =
                item['point'] as Map<String, dynamic>?;
            if (pt != null && pt['lat'] != null && pt['lon'] != null) {
              final double lat = (pt['lat'] as num).toDouble();
              final double lon = (pt['lon'] as num).toDouble();
              final String name = (item['name'] as String? ??
                      item['full_name'] as String? ??
                      trimmed)
                  .trim();
              return _PresetPlace(name, LatLng(lat, lon));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('2GIS Catalog geocode fallback: $e');
    }

    // 2. OpenStreetMap Nominatim fallback
    try {
      final Uri uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&limit=1&q=${Uri.encodeComponent(trimmed)}',
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

  /// Resolves both Point A and Point B from the text fields and starts in-app 3D navigation.
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
      _isFollowingCar = true;
    });

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
    if (_routeSteps.isEmpty) {
      final double rem =
          _distanceCalc.as(LengthUnit.Meter, carPos, _pointB);
      _nextStepDistanceMeters = rem;
      return;
    }

    for (int i = _activeStepIndex; i < _routeSteps.length; i++) {
      final _RouteStep step = _routeSteps[i];
      final double distToTurn =
          _distanceCalc.as(LengthUnit.Meter, carPos, step.location);
      if (distToTurn < 30.0 && i < _routeSteps.length - 1) {
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

  Future<void> _locateMeNow() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isFollowingCar = true;
      _isNavigating = true;
      _zoom = 17.0;
    });
    _moveAndRotateCamera(_currentLocation, _zoom, _headingDeg);
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

      if (kIsWeb) {
        final Offset? clicked = WebFaceBridge.pollClickedYandexCoords();
        if (clicked != null) {
          _onMapTapped(LatLng(clicked.dx, clicked.dy));
        }
        final WebGpsData? webGps = WebFaceBridge.pollLatestWebGps();
        if (webGps != null && webGps.speedKmh > 3.0) {
          final LatLng newPos = LatLng(webGps.lat, webGps.lng);
          _hasRealGpsFix = true;
          _currentLocation = newPos;
          _currentSpeedKmh = webGps.speedKmh;
          _speedLimitKmh = _currentSpeedKmh > 40 ? 60 : 20;
          _headingDeg = webGps.heading;
          _traveledTrail.add(newPos);
          _updateTurnByTurnProgress(newPos);
          if (_isFollowingCar) {
            _moveAndRotateCamera(newPos, _zoom, _headingDeg);
          }
          if (mounted) setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _smoothMotionTimer?.cancel();
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

  String get _formattedDistanceKm {
    if (_routeTotalMeters >= 1000) {
      final double km = _routeTotalMeters / 1000.0;
      return km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
    }
    return (_routeTotalMeters / 1000.0).toStringAsFixed(1);
  }

  String get _formattedArrivalClock {
    final DateTime arrival =
        DateTime.now().add(Duration(minutes: _routeEtaMinutes));
    final String hh = arrival.hour.toString().padLeft(2, '0');
    final String mm = arrival.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String get _activeTileUrl {
    if (_mapStyleIndex == 0) {
      // Official 2GIS Raster Map Tiles (3D Buildings, House Numbers, Trees, Parks, Bus Stops, Gas Stations)
      return 'https://tile2.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1';
    } else if (_mapStyleIndex == 1) {
      return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Resolves tapped coordinates into a human-readable 2GIS street/building name (never ugly raw numbers).
  Future<String> _reverseGeocode2Gis(LatLng pt) async {
    try {
      final Uri uri = Uri.parse(
        'https://catalog.api.2gis.com/3.0/items/geocode'
        '?lat=${pt.latitude}&lon=${pt.longitude}'
        '&fields=items.name,items.full_name'
        '&key=$_twoGisApiKey',
      );
      final http.Response res =
          await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(res.body) as Map<String, dynamic>;
        final List<dynamic>? items =
            (data['result'] as Map<String, dynamic>?)?['items']
                as List<dynamic>?;
        if (items != null && items.isNotEmpty) {
          final Map<String, dynamic> first =
              items.first as Map<String, dynamic>;
          final String name =
              (first['name'] as String? ?? first['full_name'] as String? ?? '')
                  .trim();
          if (name.isNotEmpty) return name;
        }
      }
    } catch (_) {}

    // Fallback to nearest preset street name so raw coordinates are never shown
    _PresetPlace nearest = _presets.first;
    double bestDist = double.infinity;
    for (final _PresetPlace p in _presets) {
      final double d = _distanceCalc.as(LengthUnit.Meter, pt, p.coords);
      if (d < bestDist) {
        bestDist = d;
        nearest = p;
      }
    }
    return nearest.title;
  }

  Future<void> _onMapTapped(LatLng tappedLatLng) async {
    // Only pick points on map tap when the 2GIS Route Builder sheet is open
    // so accidental touches while viewing the map don't overwrite the route.
    if (!_showRouteBuilderPanel) return;

    HapticFeedback.selectionClick();
    final String target = _mapTapTarget;
    final String streetLabel = await _reverseGeocode2Gis(tappedLatLng);
    if (!mounted) return;

    setState(() {
      if (target == 'A') {
        _pointA = tappedLatLng;
        _pointALabel = streetLabel;
        _fromController.text = streetLabel;
        _mapTapTarget = 'B';
      } else {
        _pointB = tappedLatLng;
        _pointBLabel = streetLabel;
        _toController.text = streetLabel;
      }
      _isNavigating = true;
      _isFollowingCar = true;
    });
    _fetchRealRoadRoute(_pointA, _pointB, announceVoice: true);
  }

  @override
  Widget build(BuildContext context) {
    final int curIdx =
        _smoothRouteCursor.floor().clamp(0, math.max(0, _routeWaypoints.length - 1));
    final List<LatLng> remainingRoute = _routeWaypoints.isNotEmpty
        ? <LatLng>[_currentLocation, ..._routeWaypoints.sublist(curIdx)]
        : <LatLng>[];

    // Courtyard gray lead-in segment (first 30 meters of route)
    final List<LatLng> courtyardSegment = _routeWaypoints.length > 6
        ? _routeWaypoints.sublist(0, 6)
        : <LatLng>[];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Official 2GIS MapGL 3D WebGL Engine OR 3D Perspective Tilted 2GIS Navigator Viewport
            if (kIsWeb && _mapStyleIndex == 1)
              const HtmlElementView(viewType: 'antisleep-2gis-map')
            else
              ClipRect(
                child: Transform(
                alignment: Alignment.center,
                transform: _is3DPerspective
                    ? (Matrix4.identity()
                      ..setEntry(3, 2, 0.00095) // 3D depth perspective
                      ..rotateX(-0.48) // 3D Navigator forward road tilt
                      ..scale(1.28, 1.28, 1.0))
                    : Matrix4.identity(),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation,
                    initialZoom: _zoom,
                    initialRotation: _is3DPerspective ? -_headingDeg : 0.0,
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
                    // 2GIS Route Ribbon: Gray courtyard path + Green & Yellow dual road lanes
                    PolylineLayer(
                      polylines: <Polyline>[
                        if (courtyardSegment.length > 1)
                          Polyline(
                            points: courtyardSegment,
                            strokeWidth: 10.0,
                            color: const Color(0xFF6E757C),
                            borderStrokeWidth: 2.0,
                            borderColor: Colors.white,
                          ),
                        if (_traveledTrail.length > 1)
                          Polyline(
                            points: _traveledTrail,
                            strokeWidth: 9.0,
                            color: const Color(0xFF727880),
                            borderStrokeWidth: 1.5,
                            borderColor: Colors.white70,
                          ),
                        if (remainingRoute.length > 1) ...<Polyline>[
                          // Wide 2GIS Green road lane
                          Polyline(
                            points: remainingRoute,
                            strokeWidth: 14.0,
                            color: const Color(0xFF19AA1E),
                            borderStrokeWidth: 2.5,
                            borderColor: const Color(0xFF0C5E10),
                          ),
                          // Inner 2GIS Yellow traffic/active lane
                          Polyline(
                            points: remainingRoute,
                            strokeWidth: 7.0,
                            color: const Color(0xFFFFD600),
                          ),
                        ],
                      ],
                    ),
                    // White Directional Chevrons along the road + Point B Flag + 2GIS 3D Blue Cursor & Avatar
                    MarkerLayer(
                      markers: <Marker>[
                        // White directional movement arrows along the route
                        ..._routeDirectionArrows.map((_DirectionArrowPoint a) {
                          return Marker(
                            point: a.position,
                            width: 18,
                            height: 18,
                            child: Transform.rotate(
                              angle: a.bearingDeg * math.pi / 180.0,
                              child: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          );
                        }),
                        if (_showParkingOverlay) ...<Marker>[
                          _buildParkingMarker(
                            LatLng(
                              _currentLocation.latitude + 0.0012,
                              _currentLocation.longitude + 0.0010,
                            ),
                          ),
                          _buildParkingMarker(
                            LatLng(
                              _currentLocation.latitude - 0.0009,
                              _currentLocation.longitude + 0.0015,
                            ),
                          ),
                        ],
                        // Point B Destination Flag Marker
                        Marker(
                          point: _pointB,
                          width: 42,
                          height: 42,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF19AA1E),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.8),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(color: Colors.black38, blurRadius: 6),
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
                        // 2GIS Signature 3D Blue Navigation Wedge + Circular Avatar ("3")
                        Marker(
                          point: _currentLocation,
                          width: 90,
                          height: 76,
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              // 3D Blue Navigator Wedge Arrow
                              Positioned(
                                right: 8,
                                bottom: 6,
                                child: Transform.rotate(
                                  angle: _is3DPerspective
                                      ? 0.0
                                      : (_headingDeg * math.pi / 180.0),
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E5EFF),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2.8,
                                      ),
                                      boxShadow: const <BoxShadow>[
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.navigation_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ),
                              // 2GIS Circular Driver Avatar with Status Badge ("3")
                              Positioned(
                                left: 4,
                                top: 4,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: <Color>[
                                        Color(0xFF3A506B),
                                        Color(0xFF0B132B),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3.0,
                                    ),
                                    boxShadow: const <BoxShadow>[
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: <Widget>[
                                      Center(
                                        child: Icon(
                                          Icons.directions_car_filled_rounded,
                                          color: widget.isEyesOpen
                                              ? const Color(0xFF00E676)
                                              : CockpitColors.dangerRed,
                                          size: 22,
                                        ),
                                      ),
                                      Positioned(
                                        right: -4,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF494F56),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: const Text(
                                            '3',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Top Horizon Soft Sky Gradient for 3D Perspective Realism
            if (_is3DPerspective)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 44,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          const Color(0xFFEFF3F8).withValues(alpha: 0.78),
                          const Color(0xFFEFF3F8).withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Top-Center 2GIS Green Capsule Badge
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _showRouteBuilderPanel = !_showRouteBuilderPanel;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF19AA1E),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: Colors.black26, blurRadius: 6),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.navigation_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '2ГИС',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Top-Left 2GIS White Turn-by-Turn Card ("↑ Туркестан")
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _showRouteBuilderPanel = !_showRouteBuilderPanel;
                  });
                },
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 132, maxWidth: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _nextManeuverIcon,
                            color: const Color(0xFF1E5EFF),
                            size: 28,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatMeters(_nextStepDistanceMeters),
                            style: const TextStyle(
                              color: Color(0xFF1E5EFF),
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _nextStreetInstruction,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1C1E21),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Top-Right 2GIS Overlapping Speed & Speed Limit Circles
            Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                width: 96,
                height: 76,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    // Current Speed White Circle (left/lower)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${_currentSpeedKmh.round()}',
                          style: const TextStyle(
                            color: Color(0xFF1C1E21),
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                    // Speed Limit Red-Bordered Circle (right/upper)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE53935),
                            width: 4.0,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_speedLimitKmh',
                          style: const TextStyle(
                            color: Color(0xFF1C1E21),
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. Right-Side 2GIS Floating White Pills (Traffic Score "5" + Parking "P", Zoom "+" / "-", Location Pin, 3D Compass)
            Positioned(
              right: 12,
              top: 98,
              child: Column(
                children: <Widget>[
                  // Traffic Score ("5") + Parking ("P") Vertical White Pill
                  Container(
                    width: 44,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _trafficScore = (_trafficScore % 9) + 1;
                            });
                          },
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF5A623),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$_trafficScore',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _showParkingOverlay = !_showParkingOverlay;
                            });
                          },
                          child: Text(
                            'P',
                            style: TextStyle(
                              color: _showParkingOverlay
                                  ? const Color(0xFF1E5EFF)
                                  : const Color(0xFF1C1E21),
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Zoom "+" and "-" Vertical White Pill
                  Container(
                    width: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        InkWell(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                          onTap: () {
                            _zoom = (_zoom + 0.8).clamp(3.0, 18.5);
                            _moveAndRotateCamera(
                                _mapController.camera.center, _zoom, _headingDeg);
                          },
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.add_rounded,
                              color: Color(0xFF1C1E21),
                              size: 24,
                            ),
                          ),
                        ),
                        Container(
                          height: 1,
                          width: 28,
                          color: const Color(0xFFE5E7EB),
                        ),
                        InkWell(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(14),
                          ),
                          onTap: () {
                            _zoom = (_zoom - 0.8).clamp(3.0, 18.5);
                            _moveAndRotateCamera(
                                _mapController.camera.center, _zoom, _headingDeg);
                          },
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.remove_rounded,
                              color: Color(0xFF1C1E21),
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Location Pin Button (Recenter & Follow Car in 3D)
                  GestureDetector(
                    onTap: _locateMeNow,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.pin_drop_outlined,
                        color: _isFollowingCar
                            ? const Color(0xFF1E5EFF)
                            : const Color(0xFF1C1E21),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2GIS Compass / 3D Perspective Toggle Circle Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _is3DPerspective = !_is3DPerspective;
                        _isFollowingCar = true;
                      });
                      _moveAndRotateCamera(
                          _currentLocation, _zoom, _headingDeg);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Transform.rotate(
                        angle: -_headingDeg * math.pi / 180.0,
                        child: const Icon(
                          Icons.explore_rounded,
                          color: Color(0xFFE53935),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 6. Bottom-Left "Уточните, где вы" Pill + Compact AI Camera Preview Pill
            Positioned(
              left: 12,
              bottom: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Compact Expandable AI Camera PiP Preview
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isPipExpanded = !_isPipExpanded);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.only(bottom: 8),
                      width: _isPipExpanded ? 112 : 148,
                      height: _isPipExpanded ? 142 : 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF12161F).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: widget.isEyesOpen
                              ? const Color(0xFF19AA1E)
                              : CockpitColors.dangerRed,
                          width: 2.0,
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _isPipExpanded
                            ? Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  widget.pipCameraPreview,
                                  Positioned(
                                    bottom: 4,
                                    left: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        widget.isEyesOpen
                                            ? 'ИИ: Глаза открыты'
                                            : 'ИИ: ВНИМАНИЕ!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: widget.isEyesOpen
                                              ? const Color(0xFF00E676)
                                              : CockpitColors.dangerRed,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: widget.isEyesOpen
                                            ? const Color(0xFF00E676)
                                            : CockpitColors.dangerRed,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        widget.isEyesOpen
                                            ? 'AI Камера: Норма'
                                            : 'AI: Глаза закрыты!',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.open_in_full_rounded,
                                      color: Colors.white70,
                                      size: 13,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),

                  // Exact 2GIS "Уточните, где вы" White Pill
                  GestureDetector(
                    onTap: _locateMeNow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.near_me_rounded,
                            color: Color(0xFF1C1E21),
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Уточните, где вы',
                            style: TextStyle(
                              color: Color(0xFF1C1E21),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 7. Bottom 2GIS White Dashboard Bar (Search 🔍 | 51 мин • 17:06 прибытие • 17 км | Menu ☰)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // Left Search Icon Button (opens A -> B Route Builder)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _showRouteBuilderPanel = !_showRouteBuilderPanel;
                          _showMenuSheet = false;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.search_rounded,
                          color: Color(0xFF1C1E21),
                          size: 26,
                        ),
                      ),
                    ),

                    // Center 3-Column 2GIS Telemetry (мин | прибытие | км)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _isNavigating = !_isNavigating;
                            if (_isNavigating) _isFollowingCar = true;
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            // Column 1: Minutes
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  '$_routeEtaMinutes',
                                  style: const TextStyle(
                                    color: Color(0xFF1C1E21),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                                const Text(
                                  'мин',
                                  style: TextStyle(
                                    color: Color(0xFF8E9297),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            // Column 2: Arrival Time
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  _formattedArrivalClock,
                                  style: const TextStyle(
                                    color: Color(0xFF1C1E21),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                                const Text(
                                  'прибытие',
                                  style: TextStyle(
                                    color: Color(0xFF8E9297),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            // Column 3: Kilometers
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  _formattedDistanceKm,
                                  style: const TextStyle(
                                    color: Color(0xFF1C1E21),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                                const Text(
                                  'км',
                                  style: TextStyle(
                                    color: Color(0xFF8E9297),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right Menu Icon Button (☰)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _showMenuSheet = !_showMenuSheet;
                          _showRouteBuilderPanel = false;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.menu_rounded,
                          color: Color(0xFF1C1E21),
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 8. Authentic 2GIS Route Builder Card (Transport Tabs + Connected Откуда/Куда + Quick Places + Full-Width "В путь")
            if (_showRouteBuilderPanel)
              Positioned(
                top: 76,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x3D000000),
                        blurRadius: 28,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Top Drag Handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDE1E6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      // 2GIS Transport Mode Header Tabs + Close Button
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: <Widget>[
                                  _build2GisTransportTab(
                                    index: 0,
                                    icon: Icons.directions_car_filled_rounded,
                                    label: '$_routeEtaMinutes мин',
                                  ),
                                  const SizedBox(width: 6),
                                  _build2GisTransportTab(
                                    index: 1,
                                    icon: Icons.directions_bus_filled_rounded,
                                    label: '${_routeEtaMinutes + 12} мин',
                                  ),
                                  const SizedBox(width: 6),
                                  _build2GisTransportTab(
                                    index: 2,
                                    icon: Icons.local_taxi_rounded,
                                    label: 'Такси',
                                  ),
                                  const SizedBox(width: 6),
                                  _build2GisTransportTab(
                                    index: 3,
                                    icon: Icons.directions_walk_rounded,
                                    label: 'Пешком',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(
                                () => _showRouteBuilderPanel = false),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF2F3F5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF5A6066),
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Authentic 2GIS Connected "Откуда -> Куда" Block with Swap Button
                      Stack(
                        alignment: Alignment.centerRight,
                        children: <Widget>[
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(12, 6, 48, 6),
                            child: Column(
                              children: <Widget>[
                                // Point A ("Откуда")
                                Row(
                                  children: <Widget>[
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF1E5EFF),
                                          width: 5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: _fromController,
                                          style: const TextStyle(
                                            color: Color(0xFF1C1E21),
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          onTap: () => setState(
                                              () => _mapTapTarget = 'A'),
                                          onSubmitted: (_) =>
                                              _applyCustomRouteFromFields(),
                                          decoration: InputDecoration(
                                            hintText: 'Откуда (Моё местоположение)',
                                            hintStyle: const TextStyle(
                                              color: Color(0xFF8E9297),
                                              fontSize: 13,
                                            ),
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            border: InputBorder.none,
                                            suffixIcon: IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.cancel_rounded,
                                                color: Color(0xFFB0B5BA),
                                                size: 16,
                                              ),
                                              onPressed: () {
                                                _fromController.clear();
                                                setState(
                                                    () => _mapTapTarget = 'A');
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                // Divider line with left vertical connector dots
                                Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: 18,
                                      child: Column(
                                        children: <Widget>[
                                          Container(
                                            width: 2,
                                            height: 4,
                                            color: const Color(0xFFBEC3C9),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: 2,
                                            height: 4,
                                            color: const Color(0xFFBEC3C9),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: const Color(0xFFE2E5E9),
                                      ),
                                    ),
                                  ],
                                ),
                                // Point B ("Куда")
                                Row(
                                  children: <Widget>[
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF19AA1E),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.flag_rounded,
                                        color: Colors.white,
                                        size: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: _toController,
                                          style: const TextStyle(
                                            color: Color(0xFF1C1E21),
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          onTap: () => setState(
                                              () => _mapTapTarget = 'B'),
                                          onSubmitted: (_) =>
                                              _applyCustomRouteFromFields(),
                                          decoration: InputDecoration(
                                            hintText: 'Куда едем? (улица, ТРЦ, офис)',
                                            hintStyle: const TextStyle(
                                              color: Color(0xFF8E9297),
                                              fontSize: 13,
                                            ),
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            border: InputBorder.none,
                                            suffixIcon: IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.cancel_rounded,
                                                color: Color(0xFFB0B5BA),
                                                size: 16,
                                              ),
                                              onPressed: () {
                                                _toController.clear();
                                                setState(
                                                    () => _mapTapTarget = 'B');
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Floating 2GIS Swap Circle Button (⇅)
                          Positioned(
                            right: 8,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: _swapPointsAandB,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: const <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.swap_vert_rounded,
                                  color: Color(0xFF1C1E21),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 2GIS Quick Places Carousel (Icons + Full Street Names, never cut off)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _presets.map((_PresetPlace place) {
                            final bool isSelected =
                                _toController.text.contains(place.title) ||
                                    _pointBLabel == place.title;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
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
                                    _isFollowingCar = true;
                                  });
                                  _fetchRealRoadRoute(
                                    _pointA,
                                    _pointB,
                                    announceVoice: true,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFE8F7E9)
                                        : const Color(0xFFF2F3F5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF19AA1E)
                                          : Colors.transparent,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.place_rounded,
                                        size: 14,
                                        color: isSelected
                                            ? const Color(0xFF19AA1E)
                                            : const Color(0xFF1E5EFF),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        place.title,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFF0E7A12)
                                              : const Color(0xFF1C1E21),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Full-Width Official 2GIS Green "В путь" Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF19AA1E),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _applyCustomRouteFromFields,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              const Icon(
                                Icons.navigation_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'В путь • $_routeEtaMinutes мин ($_formattedDistanceKm км)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
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

            // 9. Bottom-Right Menu Sheet (☰ — Start/Pause Driving, 3D/2D Mode, Voice Toggle, Map Theme)
            if (_showMenuSheet)
              Positioned(
                bottom: 82,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isNavigating
                                ? const Color(0xFFE53935)
                                : const Color(0xFF19AA1E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _isNavigating = !_isNavigating;
                              _showMenuSheet = false;
                              if (_isNavigating) _isFollowingCar = true;
                            });
                          },
                          icon: Icon(
                            _isNavigating
                                ? Icons.pause_rounded
                                : Icons.navigation_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _isNavigating
                                ? 'Пауза ведения'
                                : 'Продолжить движение',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '3D / 2D перспектива дороги',
                        onPressed: () {
                          setState(() => _is3DPerspective = !_is3DPerspective);
                        },
                        icon: Icon(
                          Icons.view_in_ar_rounded,
                          color: _is3DPerspective
                              ? const Color(0xFF19AA1E)
                              : const Color(0xFF8E9297),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Сменить тему карты (2ГИС / Ночь / OSM)',
                        onPressed: () {
                          setState(() {
                            _mapStyleIndex = (_mapStyleIndex + 1) % 3;
                          });
                        },
                        icon: const Icon(
                          Icons.layers_rounded,
                          color: Color(0xFF1E5EFF),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Голосовые подсказки',
                        onPressed: () {
                          setState(() => _isVoiceEnabled = !_isVoiceEnabled);
                        },
                        icon: Icon(
                          _isVoiceEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          color: _isVoiceEnabled
                              ? const Color(0xFF19AA1E)
                              : const Color(0xFF8E9297),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _build2GisTransportTab({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = _selectedTransportMode == index;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTransportMode = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF19AA1E) : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF5A6066),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF1C1E21),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildParkingMarker(LatLng point) {
    return Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E5EFF),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: const Text(
          'P',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
