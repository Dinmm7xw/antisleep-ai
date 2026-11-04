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

/// Full-Screen Interactive Map & A -> B Road Routing HUD (OSRM Street Geometry + 2GIS / Yandex Deep Links + Live GPS + Draggable PiP Camera).
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
      TextEditingController(text: 'Абая / Достык (Моя геопозиция)');
  final TextEditingController _toController =
      TextEditingController(text: 'пр. Достык / пр. Аль-Фараби');
  final Distance _distanceCalc = const Distance();

  // Point A (Start), Point B (Destination), and live vehicle position
  LatLng _pointA = const LatLng(43.2415, 76.9562);
  LatLng _pointB = const LatLng(43.2220, 76.9585);
  LatLng _currentLocation = const LatLng(43.2415, 76.9562);

  String _pointALabel = 'Абая / Достык';
  String _pointBLabel = 'Достык / Аль-Фараби';
  String _nextStreetInstruction = 'пр. Достык';
  IconData _nextManeuverIcon = Icons.turn_right_rounded;
  double _nextStepDistanceMeters = 250.0;

  // Which point a map tap updates: 'B' (default destination) or 'A' (start point)
  String _mapTapTarget = 'B';

  final List<LatLng> _traveledTrail = <LatLng>[];
  List<LatLng> _routeWaypoints = <LatLng>[];
  int _simRouteIndex = 0;

  double _routeTotalMeters = 2400.0;
  int _routeEtaMinutes = 6;
  double _currentSpeedKmh = 48.0;
  double _headingDeg = 180.0;
  double _zoom = 13.8;

  // 0 = Bright 2GIS/Yandex Road Scheme (Voyager), 1 = Dark Cockpit Night, 2 = OSM Detailed
  int _mapStyleIndex = 0;
  bool _hasRealGpsFix = false;
  bool _isCalculatingRoute = false;
  bool _showRouteBuilderPanel = false;
  bool _isPipMinimized = false;

  // Draggable PiP camera overlay position inside the viewport (right, top)
  Offset _pipOffset = const Offset(10, 78);

  Timer? _gpsPollTimer;

  @override
  void initState() {
    super.initState();
    _traveledTrail.add(_currentLocation);
    _fetchRealRoadRoute(_pointA, _pointB);
    _startGpsTracking();
  }

  /// Queries OSRM real road routing engine for exact street geometry, distance, ETA, and turn-by-turn street names.
  Future<void> _fetchRealRoadRoute(LatLng start, LatLng end) async {
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

          String streetName = _pointBLabel;
          double stepDist = math.min(250.0, distMeters);
          IconData turnIcon = Icons.straight_rounded;

          final List<dynamic>? legs = route['legs'] as List<dynamic>?;
          if (legs != null && legs.isNotEmpty) {
            final Map<String, dynamic> leg = legs.first as Map<String, dynamic>;
            final List<dynamic>? steps = leg['steps'] as List<dynamic>?;
            if (steps != null && steps.isNotEmpty) {
              final Map<String, dynamic> step = steps.length > 1
                  ? steps[1] as Map<String, dynamic>
                  : steps.first as Map<String, dynamic>;
              final String rawName = (step['name'] as String? ?? '').trim();
              if (rawName.isNotEmpty) {
                streetName = rawName;
              }
              stepDist = (step['distance'] as num?)?.toDouble() ?? stepDist;
              final Map<String, dynamic>? maneuver =
                  step['maneuver'] as Map<String, dynamic>?;
              final String modifier =
                  maneuver?['modifier'] as String? ?? 'straight';
              if (modifier.contains('left')) {
                turnIcon = Icons.turn_left_rounded;
              } else if (modifier.contains('right')) {
                turnIcon = Icons.turn_right_rounded;
              } else if (modifier.contains('uturn')) {
                turnIcon = Icons.u_turn_left_rounded;
              } else {
                turnIcon = Icons.straight_rounded;
              }
            }
          }

          if (mounted) {
            setState(() {
              _routeWaypoints =
                  roadPoints.isNotEmpty ? roadPoints : <LatLng>[start, end];
              _simRouteIndex = 0;
              _currentLocation = start;
              _traveledTrail
                ..clear()
                ..add(start);
              _routeTotalMeters = distMeters;
              _routeEtaMinutes = math.max(1, (durationSec / 60.0).round());
              _nextStreetInstruction = streetName;
              _nextStepDistanceMeters = stepDist;
              _nextManeuverIcon = turnIcon;
              _isCalculatingRoute = false;
            });
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

    // Check local presets first for instant response
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

  /// Resolves both Point A and Point B from the text fields and builds the road route.
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
    });

    final LatLng center = LatLng(
      (_pointA.latitude + _pointB.latitude) / 2.0,
      (_pointA.longitude + _pointB.longitude) / 2.0,
    );
    _mapController.move(center, 12.8);
    await _fetchRealRoadRoute(_pointA, _pointB);
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
    _fetchRealRoadRoute(_pointA, _pointB);
  }

  /// Opens the exact Point A -> Point B route in 2GIS while keeping AntiSleep AI in PiP mode.
  Future<void> _openRouteIn2Gis() async {
    HapticFeedback.mediumImpact();
    final String twoGisUrl =
        'https://2gis.kz/almaty/directions/points/'
        '${_pointA.longitude}%2C${_pointA.latitude}%3B'
        '${_pointB.longitude}%2C${_pointB.latitude}';
    await _launchExternalNavigatorUrl(twoGisUrl);
  }

  /// Opens the exact Point A -> Point B route in Yandex.Maps while keeping AntiSleep AI in PiP mode.
  Future<void> _openRouteInYandexMaps() async {
    HapticFeedback.mediumImpact();
    final String yandexRouteUrl =
        'https://yandex.kz/maps/?rtext=${_pointA.latitude},${_pointA.longitude}'
        '~${_pointB.latitude},${_pointB.longitude}&rtt=auto';
    await _launchExternalNavigatorUrl(yandexRouteUrl);
  }

  Future<void> _launchExternalNavigatorUrl(String url) async {
    if (kIsWeb) {
      WebFaceBridge.toggleWebPictureInPicture();
      WebFaceBridge.openExternalUrl(url);
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _bgChannel.invokeMethod<bool>(
          'openUrl',
          <String, dynamic>{'url': url},
        );
      } catch (_) {}
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

      // 1. Poll real browser GPS on Web
      if (kIsWeb) {
        final WebGpsData? webGps = WebFaceBridge.pollLatestWebGps();
        if (webGps != null) {
          final LatLng newPos = LatLng(webGps.lat, webGps.lng);
          final bool firstFix = !_hasRealGpsFix;
          _hasRealGpsFix = true;
          _currentLocation = newPos;
          if (webGps.speedKmh > 1.0) {
            _currentSpeedKmh = webGps.speedKmh;
          }
          _headingDeg = webGps.heading;
          if (_traveledTrail.isEmpty ||
              _distanceCalc.as(LengthUnit.Meter, _traveledTrail.last, newPos) >
                  5) {
            _traveledTrail.add(newPos);
          }
          if (firstFix) {
            _pointA = newPos;
            _pointALabel = 'Моя геопозиция (GPS)';
            _fromController.text = _pointALabel;
            _mapController.move(newPos, _zoom);
            await _fetchRealRoadRoute(_pointA, _pointB);
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
            final LatLng newPos = LatLng(
              (gpsMap['lat'] as num).toDouble(),
              (gpsMap['lng'] as num).toDouble(),
            );
            final bool firstFix = !_hasRealGpsFix;
            _hasRealGpsFix = true;
            _currentLocation = newPos;
            final double spd = (gpsMap['speedKmh'] as num?)?.toDouble() ?? 0.0;
            if (spd > 1.0) _currentSpeedKmh = spd;
            _headingDeg = (gpsMap['heading'] as num?)?.toDouble() ?? _headingDeg;
            _traveledTrail.add(newPos);
            if (firstFix) {
              _pointA = newPos;
              _pointALabel = 'Моя геопозиция (GPS)';
              _fromController.text = _pointALabel;
              _mapController.move(newPos, _zoom);
              await _fetchRealRoadRoute(_pointA, _pointB);
            }
            if (mounted) setState(() {});
            return;
          }
        } catch (_) {}
      }

      // 3. Follow the real OSRM road route points smoothly when stationary/testing
      if (!_hasRealGpsFix && _routeWaypoints.length > 2) {
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
            50.0,
            _distanceCalc.as(LengthUnit.Meter, _currentLocation, _pointB),
          );
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
      // OpenStreetMap Detailed Street Map
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    // Bright 2GIS / Yandex-style High-Contrast Street Map
    return 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  }

  String get _activeMapStyleLabel {
    if (_mapStyleIndex == 0) return 'Дневная 2ГИС/Яндекс';
    if (_mapStyleIndex == 1) return 'Кокпит Ночь';
    return 'OSM Подробная';
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
    _fetchRealRoadRoute(_pointA, _pointB);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Smooth 60FPS Interactive FlutterMap Canvas (Drag, Pinch/Wheel Zoom, Tap to set Point A / Point B)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: _zoom,
                onTap: (TapPosition tapPos, LatLng tappedLatLng) =>
                    _onMapTapped(tappedLatLng),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: _activeTileUrl,
                  userAgentPackageName: 'com.antisleep.ai',
                ),
                // Traveled trail + Active A -> B Road Route Polyline
                PolylineLayer(
                  polylines: <Polyline>[
                    if (_traveledTrail.length > 1)
                      Polyline(
                        points: _traveledTrail,
                        strokeWidth: 4.0,
                        color: CockpitColors.textMuted.withValues(alpha: 0.55),
                      ),
                    if (_routeWaypoints.length > 1)
                      Polyline(
                        points: _routeWaypoints,
                        strokeWidth: 7.0,
                        color: const Color(0xFF00C853), // 2GIS / Navigation green-gold route line
                        borderStrokeWidth: 2.5,
                        borderColor: const Color(0xFF003314),
                      ),
                  ],
                ),
                // Point A Marker, Point B Marker, & Live Driver GPS Arrow
                MarkerLayer(
                  markers: <Marker>[
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
                      width: 46,
                      height: 46,
                      child: Transform.rotate(
                        angle: _headingDeg * math.pi / 180.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFCC00).withValues(alpha: 0.28),
                            border: Border.all(
                              color: const Color(0xFFFFCC00),
                              width: 2.2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.navigation_rounded,
                              color: Color(0xFFFFCC00),
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 2. Top Navigation Header + Expandable 2GIS/Yandex-Style "Откуда (А) -> Куда (Б)" Route Builder
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Compact Turn-by-Turn & A -> B Summary Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: CockpitColors.card.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CockpitColors.cardBorder),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: CockpitColors.safeGreen.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            _nextManeuverIcon,
                            color: CockpitColors.safeGreen,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showRouteBuilderPanel = !_showRouteBuilderPanel;
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
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '• $_nextStreetInstruction',
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
                                      : 'А: $_pointALabel  →  Б: $_pointBLabel',
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
                        // Toggle "Маршрут А -> Б" panel button
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _showRouteBuilderPanel = !_showRouteBuilderPanel;
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

                  // Expandable 2GIS / Yandex Style "Откуда (А) -> Куда (Б)" Panel
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
                                      hintText: 'Куда (Точка Б — адрес или место)',
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
                                  minimumSize: const Size(42, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _applyCustomRouteFromFields,
                                child: const Text(
                                  'Старт',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Map tap target selector + Quick Presets
                          Row(
                            children: <Widget>[
                              Text(
                                _mapTapTarget == 'A'
                                    ? 'Нажатие на карту выберет: Точку А'
                                    : 'Нажатие на карту выберет: Точку Б',
                                style: TextStyle(
                                  color: _mapTapTarget == 'A'
                                      ? CockpitColors.safeGreen
                                      : const Color(0xFFFFCC00),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _mapTapTarget =
                                        _mapTapTarget == 'A' ? 'B' : 'A';
                                  });
                                },
                                child: Text(
                                  _mapTapTarget == 'A'
                                      ? 'Переключить на Б'
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
                                      });
                                      _mapController.move(place.coords, 13.2);
                                      _fetchRealRoadRoute(_pointA, _pointB);
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // External Navigation Launchers: 2GIS & Yandex.Maps
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: _openRouteIn2Gis,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF19AA1E),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        Icon(
                                          Icons.navigation_rounded,
                                          color: Colors.white,
                                          size: 15,
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'Маршрут в 2ГИС (PiP)',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: _openRouteInYandexMaps,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFCC00),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        Icon(
                                          Icons.near_me_rounded,
                                          color: Colors.black,
                                          size: 15,
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'Яндекс.Карты (PiP)',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 3. Left Map Controls (Zoom +, Zoom -, Recenter GPS, Map Layer Switcher)
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
                      _mapController.move(_mapController.camera.center, _zoom);
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMapIconButton(
                    icon: Icons.remove_rounded,
                    onTap: () {
                      _zoom = (_zoom - 1.0).clamp(3.0, 18.5);
                      _mapController.move(_mapController.camera.center, _zoom);
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMapIconButton(
                    icon: Icons.my_location_rounded,
                    color: CockpitColors.safeGreen,
                    onTap: () {
                      _mapController.move(_currentLocation, _zoom);
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

            // 4. Bottom Navigation ETA + Speed Limit & Current Speed Bar (Zero Overflow)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: CockpitColors.card.withValues(alpha: 0.95),
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
                            '${_currentSpeedKmh.round()} ${appState.t('speedUnit')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CockpitColors.textWhite,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: CockpitColors.safeGreen.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        '$_routeEtaMinutes ${appState.t('etaMin')} • ${_formatMeters(_routeTotalMeters)}',
                        style: const TextStyle(
                          color: CockpitColors.safeGreen,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
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
              width: _isPipMinimized ? 54 : 104,
              height: _isPipMinimized ? 54 : 136,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isPipMinimized = !_isPipMinimized);
                },
                onPanUpdate: (DragUpdateDetails details) {
                  setState(() {
                    final double maxRight = math.max(
                      8.0,
                      constraints.maxWidth - (_isPipMinimized ? 64.0 : 114.0),
                    );
                    final double maxTop = math.max(
                      70.0,
                      constraints.maxHeight - (_isPipMinimized ? 70.0 : 150.0),
                    );
                    final double newRight =
                        (_pipOffset.dx - details.delta.dx).clamp(8.0, maxRight);
                    final double newTop =
                        (_pipOffset.dy + details.delta.dy).clamp(70.0, maxTop);
                    _pipOffset = Offset(newRight, newTop);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: CockpitColors.bg,
                    borderRadius:
                        BorderRadius.circular(_isPipMinimized ? 27 : 16),
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
                        BorderRadius.circular(_isPipMinimized ? 25 : 14),
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
