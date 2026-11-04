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

/// Single Turn-by-Turn maneuver step inside the built-in 2GIS-style navigator.
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

/// Authentic 2GIS-Style Built-In Navigator (Real 2GIS Tiles with 3D Buildings & Parks, Dual Yellow/Green Route Line, 2GIS White HUD & Live PiP AI Guard).
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
    _PresetPlace('Астана: Туркестан / Акмешит', LatLng(51.1142, 71.4218)),
    _PresetPlace('Астана: пр. Улы Дала', LatLng(51.1065, 71.4145)),
    _PresetPlace('Астана: Байтерек', LatLng(51.1283, 71.4305)),
    _PresetPlace('Астана: Mega Silk Way', LatLng(51.0892, 71.4146)),
    _PresetPlace('Алматы: Абая / Достык', LatLng(43.2415, 76.9562)),
    _PresetPlace('Алматы: Достык / Аль-Фараби', LatLng(43.2220, 76.9585)),
    _PresetPlace('Алматы: ТРЦ Mega', LatLng(43.2016, 76.8924)),
    _PresetPlace('Алматы: ВСК Медеу', LatLng(43.1574, 77.0590)),
    _PresetPlace('Алматы: Аэропорт', LatLng(43.3521, 77.0405)),
  ];

  final MapController _mapController = MapController();
  final TextEditingController _fromController =
      TextEditingController(text: 'Акмешит / Ботанический сад');
  final TextEditingController _toController =
      TextEditingController(text: 'ул. Туркестан / пр. Улы Дала');
  final Distance _distanceCalc = const Distance();

  // Default coordinates matching the 2GIS Astana screenshot (Turkestan / Akmeshit / Botanical Park)
  LatLng _pointA = const LatLng(51.1102, 71.4192);
  LatLng _pointB = const LatLng(51.1245, 71.4268);
  LatLng _currentLocation = const LatLng(51.1102, 71.4192);

  String _pointALabel = 'Акмешит';
  String _pointBLabel = 'Туркестан';
  String _nextActionText = 'Прямо';
  String _nextStreetInstruction = 'Туркестан';
  IconData _nextManeuverIcon = Icons.arrow_upward_rounded;
  double _nextStepDistanceMeters = 250.0;

  // Which point a map tap updates: 'B' (default destination) or 'A' (start point)
  String _mapTapTarget = 'B';

  final List<LatLng> _traveledTrail = <LatLng>[];
  List<LatLng> _routeWaypoints = <LatLng>[];
  List<_RouteStep> _routeSteps = <_RouteStep>[];
  int _activeStepIndex = 0;
  int _simRouteIndex = 0;
  int _lastSpokenStepIndex = -1;

  double _routeTotalMeters = 17000.0;
  int _routeEtaMinutes = 51;
  double _currentSpeedKmh = 0.0;
  int _speedLimitKmh = 20;
  int _trafficScore = 5;
  double _headingDeg = 18.0;
  double _zoom = 16.2;

  // 0 = Real 2GIS Map Tiles (with 3D Buildings, House Numbers & Green Parks), 1 = 2GIS Dark Cockpit, 2 = OSM Detailed
  int _mapStyleIndex = 0;
  bool _hasRealGpsFix = false;
  bool _isCalculatingRoute = false;
  bool _isNavigating = false;
  bool _isFollowingCar = true;
  bool _isVoiceEnabled = true;
  bool _showParkingOverlay = false;
  bool _showRouteBuilderPanel = false;
  bool _showMenuSheet = false;
  bool _isPipExpanded = false;

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

  /// Resolves both Point A and Point B from the text fields and starts in-app 2GIS navigation.
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

    _moveActiveMap(_pointA, 16.0);
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

    for (int i = _activeStepIndex; i < _routeSteps.length; i++) {
      final _RouteStep step = _routeSteps[i];
      final double distToTurn =
          _distanceCalc.as(LengthUnit.Meter, carPos, step.location);
      if (distToTurn < 40.0 && i < _routeSteps.length - 1) {
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
    if (kIsWeb) {
      WebFaceBridge.startWebGps();
      final WebGpsData? webGps = WebFaceBridge.pollLatestWebGps();
      if (webGps != null) {
        final LatLng gpsPos = LatLng(webGps.lat, webGps.lng);
        setState(() {
          _hasRealGpsFix = true;
          _currentLocation = gpsPos;
          _pointA = gpsPos;
          _pointALabel = 'Моя геопозиция (GPS)';
          _fromController.text = _pointALabel;
          _isFollowingCar = true;
        });
        _moveActiveMap(gpsPos, 16.2);
        await _fetchRealRoadRoute(_pointA, _pointB, announceVoice: true);
        return;
      }
    }
    setState(() => _isFollowingCar = true);
    _moveActiveMap(_currentLocation, 16.2);
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

      // 1. Poll real browser GPS on Web when moving
      if (kIsWeb) {
        final WebGpsData? webGps = WebFaceBridge.pollLatestWebGps();
        if (webGps != null && webGps.speedKmh > 2.5) {
          final LatLng newPos = LatLng(webGps.lat, webGps.lng);
          _hasRealGpsFix = true;
          _currentLocation = newPos;
          _currentSpeedKmh = webGps.speedKmh;
          _speedLimitKmh = _currentSpeedKmh > 40 ? 60 : 20;
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
              _speedLimitKmh = _currentSpeedKmh > 40 ? 60 : 20;
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

      // 2. Built-in 2GIS Navigator Driving Mode along the OSRM street route
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
          _currentSpeedKmh = 44.0 + (DateTime.now().second % 14);
          _speedLimitKmh = 60;
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
          _isNavigating = false;
          _currentSpeedKmh = 0;
          _speedLimitKmh = 20;
          _nextActionText = 'Прибытие';
          _nextStreetInstruction = _pointBLabel;
          _nextManeuverIcon = Icons.flag_rounded;
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
      // Dark Cockpit Navigation Map
      return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    }
    // OpenStreetMap Detailed
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
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
    });
    _fetchRealRoadRoute(_pointA, _pointB, announceVoice: true);
  }

  @override
  Widget build(BuildContext context) {
    final List<LatLng> remainingRoute = _routeWaypoints.isNotEmpty &&
            _simRouteIndex < _routeWaypoints.length
        ? _routeWaypoints.sublist(_simRouteIndex)
        : _routeWaypoints;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Official 2GIS Map Tiles Canvas + Dual Yellow/Green Route Line + 3D Blue Cursor
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
                // 2GIS-Style Dual Route Polyline (Gray courtyard lead-in + Yellow & Green traffic route)
                PolylineLayer(
                  polylines: <Polyline>[
                    if (_traveledTrail.length > 1)
                      Polyline(
                        points: _traveledTrail,
                        strokeWidth: 7.0,
                        color: const Color(0xFF727880),
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white,
                      ),
                    if (remainingRoute.length > 1) ...<Polyline>[
                      // Outer green 2GIS main route lane
                      Polyline(
                        points: remainingRoute,
                        strokeWidth: 11.0,
                        color: const Color(0xFF19AA1E),
                        borderStrokeWidth: 2.0,
                        borderColor: const Color(0xFF0E6B12),
                      ),
                      // Inner yellow 2GIS traffic highlight lane
                      Polyline(
                        points: remainingRoute,
                        strokeWidth: 5.5,
                        color: const Color(0xFFFFD600),
                      ),
                    ],
                  ],
                ),
                // Parking markers (if enabled) + Point B Flag + 2GIS 3D Blue Navigation Cursor & Avatar Badge
                MarkerLayer(
                  markers: <Marker>[
                    if (_showParkingOverlay) ...<Marker>[
                      _buildParkingMarker(
                        LatLng(
                          _currentLocation.latitude + 0.0014,
                          _currentLocation.longitude + 0.0012,
                        ),
                      ),
                      _buildParkingMarker(
                        LatLng(
                          _currentLocation.latitude - 0.0011,
                          _currentLocation.longitude + 0.0018,
                        ),
                      ),
                    ],
                    // Point B Destination Pin
                    Marker(
                      point: _pointB,
                      width: 42,
                      height: 42,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF19AA1E),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.8),
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
                    // 2GIS Signature 3D Blue Navigation Arrow + Driver Avatar Circle Badge
                    Marker(
                      point: _currentLocation,
                      width: 82,
                      height: 68,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          // 3D Blue Navigation Arrow
                          Positioned(
                            right: 6,
                            bottom: 8,
                            child: Transform.rotate(
                              angle: _headingDeg * math.pi / 180.0,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E5EFF),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: const <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          // 2GIS Circular Driver Avatar with Status Badge ("3")
                          Positioned(
                            left: 4,
                            top: 4,
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Color(0xFF2B4162),
                                    Color(0xFF12100E),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3.0,
                                ),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black26,
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
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Text(
                                        'AI',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
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
                          '2ГИС • AI',
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
                      const BoxConstraints(minWidth: 128, maxWidth: 175),
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
                          if (_isNavigating) ...<Widget>[
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

            // 4. Top-Right 2GIS Overlapping Speed ("0") & Speed Limit ("20" / "60") Circles
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

            // 5. Right-Side 2GIS Floating White Pills (Traffic Score "5" + Parking "P", Zoom "+" / "-", Location Pin, Compass)
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
                            _zoom = (_zoom + 1.0).clamp(3.0, 18.5);
                            _moveActiveMap(
                                _mapController.camera.center, _zoom);
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
                            _zoom = (_zoom - 1.0).clamp(3.0, 18.5);
                            _moveActiveMap(
                                _mapController.camera.center, _zoom);
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

                  // Location Pin Button
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
                      child: const Icon(
                        Icons.pin_drop_outlined,
                        color: Color(0xFF1C1E21),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2GIS Compass Circle Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _moveActiveMap(_currentLocation, 16.2);
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
                      child: const Icon(
                        Icons.explore_rounded,
                        color: Color(0xFFE53935),
                        size: 24,
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
                      height: _isPipExpanded ? 142 : 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF12161F).withValues(alpha: 0.94),
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

                    // Center 3-Column 2GIS Telemetry (мин | прибытие | км) — tapping starts/pauses driving
                    Expanded(
                      child: GestureDetector(
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
                            if (_isNavigating) _isFollowingCar = true;
                          });
                          if (_isNavigating) {
                            _speak(
                              'Маршрут активен. $_nextActionText на $_nextStreetInstruction',
                            );
                          }
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
                                Text(
                                  _isNavigating ? 'в пути ▶' : 'прибытие',
                                  style: TextStyle(
                                    color: _isNavigating
                                        ? const Color(0xFF19AA1E)
                                        : const Color(0xFF8E9297),
                                    fontWeight: FontWeight.w700,
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

            // 8. 2GIS Search & Route Builder Sheet ("Откуда А -> Куда Б")
            if (_showRouteBuilderPanel)
              Positioned(
                top: 86,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text(
                            'Маршрут 2ГИС (Точка А → Точка Б)',
                            style: TextStyle(
                              color: Color(0xFF1C1E21),
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(
                                () => _showRouteBuilderPanel = false),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF8E9297),
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Point A Field
                      Row(
                        children: <Widget>[
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E5EFF),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'А',
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
                              height: 38,
                              child: TextField(
                                controller: _fromController,
                                style: const TextStyle(
                                  color: Color(0xFF1C1E21),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                onTap: () =>
                                    setState(() => _mapTapTarget = 'A'),
                                onSubmitted: (_) =>
                                    _applyCustomRouteFromFields(),
                                decoration: InputDecoration(
                                  hintText: 'Откуда (Точка А)',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF3F4F6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: _swapPointsAandB,
                            icon: const Icon(
                              Icons.swap_vert_rounded,
                              color: Color(0xFF1E5EFF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Point B Field
                      Row(
                        children: <Widget>[
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Color(0xFF19AA1E),
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
                              height: 38,
                              child: TextField(
                                controller: _toController,
                                style: const TextStyle(
                                  color: Color(0xFF1C1E21),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                onTap: () =>
                                    setState(() => _mapTapTarget = 'B'),
                                onSubmitted: (_) =>
                                    _applyCustomRouteFromFields(),
                                decoration: InputDecoration(
                                  hintText: 'Куда (Точка Б — улица, ТРЦ, дом)',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF3F4F6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF19AA1E),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(64, 38),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _applyCustomRouteFromFields,
                            child: const Text(
                              'В путь',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Quick Preset Chips (Astana & Almaty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _presets.map((_PresetPlace place) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: const Color(0xFFF3F4F6),
                                side: BorderSide.none,
                                label: Text(
                                  place.title,
                                  style: const TextStyle(
                                    color: Color(0xFF1C1E21),
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
                                  _moveActiveMap(place.coords, 15.8);
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
              ),

            // 9. Bottom-Right Menu Sheet (☰ — Start/Pause Driving, Voice Toggle, Map Style, Steps)
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isNavigating
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFF19AA1E),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
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
                                if (_isNavigating) {
                                  _speak(
                                    'Движение по маршруту начато. $_nextActionText на $_nextStreetInstruction',
                                  );
                                }
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
                                    : 'Начать движение по маршруту',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                              setState(
                                  () => _isVoiceEnabled = !_isVoiceEnabled);
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
                    ],
                  ),
                ),
              ),
          ],
        );
      },
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
