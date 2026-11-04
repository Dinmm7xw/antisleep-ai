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

/// Preset destination model for quick 1-tap routing.
class _PresetPlace {
  final String title;
  final LatLng coords;
  const _PresetPlace(this.title, this.coords);
}

/// Interactive Real-Time Map & Road Routing HUD (Yandex Road Routing + OSRM Street Geometry + Live GPS + Draggable PiP Camera).
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
    _PresetPlace('Достык / Аль-Фараби', LatLng(43.2220, 76.9585)),
    _PresetPlace('ТРЦ Mega', LatLng(43.2016, 76.8924)),
    _PresetPlace('Аэропорт', LatLng(43.3521, 77.0405)),
    _PresetPlace('Вокзал Алматы-2', LatLng(43.2736, 76.9390)),
    _PresetPlace('Астана Байтерек', LatLng(51.1283, 71.4305)),
  ];

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final Distance _distanceCalc = const Distance();

  // Default coordinates: Almaty (Abay / Dostyk Ave) until live GPS fix arrives
  LatLng _currentLocation = const LatLng(43.2415, 76.9562);
  LatLng _destination = const LatLng(43.2220, 76.9585);
  String _destinationLabel = 'пр. Достык / пр. Аль-Фараби';
  String _nextStreetInstruction = 'пр. Достык';
  IconData _nextManeuverIcon = Icons.turn_right_rounded;
  double _nextStepDistanceMeters = 250.0;

  final List<LatLng> _traveledTrail = <LatLng>[];
  List<LatLng> _routeWaypoints = <LatLng>[];
  int _simRouteIndex = 0;

  double _routeTotalMeters = 2400.0;
  int _routeEtaMinutes = 6;
  double _currentSpeedKmh = 48.0;
  double _headingDeg = 180.0;
  double _zoom = 13.8;

  // 0 = Yandex Dark Cockpit, 1 = Yandex Bright Scheme (Voyager), 2 = OSM Standard
  int _mapStyleIndex = 0;
  bool _hasRealGpsFix = false;
  bool _isCalculatingRoute = false;
  bool _showSearchBar = false;

  // Draggable PiP camera overlay position inside the viewport
  Offset _pipOffset = const Offset(12, 134);

  Timer? _gpsPollTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebFaceBridge.registerYandexMapView(
        'antisleep-yandex-map',
        _currentLocation.latitude,
        _currentLocation.longitude,
        _destination.latitude,
        _destination.longitude,
      );
    }
    _traveledTrail.add(_currentLocation);
    _fetchRealRoadRoute(_currentLocation, _destination);
    _startGpsTracking();
  }

  void _syncRouteToRealYandexMap() {
    if (!kIsWeb) return;
    final List<List<double>> pts = _routeWaypoints
        .map((LatLng p) => <double>[p.latitude, p.longitude])
        .toList();
    WebFaceBridge.updateYandexRoute(
      pts,
      _currentLocation.latitude,
      _currentLocation.longitude,
      _destination.latitude,
      _destination.longitude,
    );
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

          // Extract first turn-by-turn maneuver & street name
          String streetName = _destinationLabel;
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
              stepDist =
                  (step['distance'] as num?)?.toDouble() ?? stepDist;
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
              _routeTotalMeters = distMeters;
              _routeEtaMinutes = math.max(1, (durationSec / 60.0).round());
              _nextStreetInstruction = streetName;
              _nextStepDistanceMeters = stepDist;
              _nextManeuverIcon = turnIcon;
              _isCalculatingRoute = false;
            });
            _syncRouteToRealYandexMap();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM route fallback: $e');
    }

    // Fallback multi-segment route if offline
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
      _routeTotalMeters = fallbackDist;
      _routeEtaMinutes = math.max(1, (fallbackDist / 750.0).round());
      _isCalculatingRoute = false;
    });
    _syncRouteToRealYandexMap();
  }

  /// Geocodes a user-entered address query via OpenStreetMap Nominatim and builds the road route.
  Future<void> _searchAddressAndBuildRoute(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isCalculatingRoute = true;
      _showSearchBar = false;
    });

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

          final LatLng target = LatLng(lat, lon);
          setState(() {
            _destination = target;
            _destinationLabel = displayName;
          });
          if (kIsWeb && _mapStyleIndex == 0) {
            WebFaceBridge.moveYandexCenter(target.latitude, target.longitude, 13);
          } else {
            _mapController.move(target, 13.5);
          }
          await _fetchRealRoadRoute(_currentLocation, target);
          return;
        }
      }
    } catch (e) {
      debugPrint('Address search error: $e');
    }

    if (mounted) {
      setState(() => _isCalculatingRoute = false);
    }
  }

  /// Launches the built route directly in Yandex.Maps / Yandex.Navigator while keeping AntiSleep AI in PiP mode.
  Future<void> _openRouteInYandexMaps() async {
    HapticFeedback.mediumImpact();
    final String yandexRouteUrl =
        'https://yandex.kz/maps/?rtext=${_currentLocation.latitude},${_currentLocation.longitude}'
        '~${_destination.latitude},${_destination.longitude}&rtt=auto';

    if (kIsWeb) {
      WebFaceBridge.toggleWebPictureInPicture();
      WebFaceBridge.openExternalUrl(yandexRouteUrl);
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _bgChannel.invokeMethod<bool>(
          'openUrl',
          <String, dynamic>{'url': yandexRouteUrl},
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

      // 0. Check if user clicked on the real Yandex Map (ymaps.Map) to set destination
      if (kIsWeb) {
        final Offset? clicked = WebFaceBridge.pollClickedYandexCoords();
        if (clicked != null) {
          final LatLng tappedLatLng = LatLng(clicked.dx, clicked.dy);
          setState(() {
            _destination = tappedLatLng;
            _destinationLabel =
                '${tappedLatLng.latitude.toStringAsFixed(4)}, ${tappedLatLng.longitude.toStringAsFixed(4)}';
          });
          await _fetchRealRoadRoute(_currentLocation, tappedLatLng);
        }
      }

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
            _mapController.move(newPos, _zoom);
            await _fetchRealRoadRoute(newPos, _destination);
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
              _mapController.move(newPos, _zoom);
              await _fetchRealRoadRoute(newPos, _destination);
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
            _distanceCalc.as(LengthUnit.Meter, _currentLocation, _destination),
          );
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _gpsPollTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String _formatMeters(double m) {
    if (m >= 1000) {
      return '${(m / 1000).toStringAsFixed(1)} km';
    }
    return '${m.round()} m';
  }

  String get _activeTileUrl {
    if (_mapStyleIndex == 1) {
      // Dark Cockpit Navigation Map
      return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    } else if (_mapStyleIndex == 2) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    return 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  }

  String get _activeMapStyleLabel {
    if (_mapStyleIndex == 0) return 'Яндекс.Карта 2.1';
    if (_mapStyleIndex == 1) return 'Кокпит Ночь';
    return 'OSM Схема';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Official Real Yandex Map 2.1 (with Live Traffic / Пробки) on Web OR FlutterMap
            if (kIsWeb && _mapStyleIndex == 0)
              const HtmlElementView(viewType: 'antisleep-yandex-map')
            else
              FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: _zoom,
                onTap: (TapPosition tapPos, LatLng tappedLatLng) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _destination = tappedLatLng;
                    _destinationLabel =
                        '${tappedLatLng.latitude.toStringAsFixed(4)}, ${tappedLatLng.longitude.toStringAsFixed(4)}';
                  });
                  _fetchRealRoadRoute(_currentLocation, tappedLatLng);
                },
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: _activeTileUrl,
                  userAgentPackageName: 'com.antisleep.ai',
                ),
                // Traveled trail + Active Yandex/OSRM Road Route Polyline
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
                        strokeWidth: 6.5,
                        color: const Color(0xFFFFCC00), // Yandex Navigation Yellow-Gold route line
                        borderStrokeWidth: 2.5,
                        borderColor: const Color(0xFF332600),
                      ),
                  ],
                ),
                // Destination Pin & Driver GPS Arrow Marker
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: _destination,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: CockpitColors.dangerRed,
                        size: 40,
                      ),
                    ),
                    Marker(
                      point: _currentLocation,
                      width: 48,
                      height: 48,
                      child: Transform.rotate(
                        angle: _headingDeg * math.pi / 180.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: CockpitColors.safeGreen.withValues(alpha: 0.25),
                            border: Border.all(
                              color: CockpitColors.safeGreen,
                              width: 2.2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.navigation_rounded,
                              color: CockpitColors.safeGreen,
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

            // 2. Top Turn-by-Turn Road Navigation Card + Search Toggle + Yandex Maps Button
            Positioned(
              top: 46,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: CockpitColors.card.withValues(alpha: 0.95),
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
                            color: const Color(0xFFFFCC00).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            _nextManeuverIcon,
                            color: const Color(0xFFFFCC00),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
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
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '• $_nextStreetInstruction',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFFFCC00),
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
                                    ? appState.t('buildingRoute')
                                    : '→ $_destinationLabel (${_formatMeters(_routeTotalMeters)})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CockpitColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Search Address Button
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: appState.t('searchHint'),
                          onPressed: () {
                            setState(() => _showSearchBar = !_showSearchBar);
                          },
                          icon: Icon(
                            _showSearchBar
                                ? Icons.close_rounded
                                : Icons.search_rounded,
                            color: CockpitColors.textWhite,
                            size: 20,
                          ),
                        ),
                        // Direct Yandex.Maps Route Launch Button
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _openRouteInYandexMaps,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFCC00),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(
                                  Icons.near_me_rounded,
                                  color: Colors.black,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  appState.t('openYandexBtn'),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Expandable Address Search Bar + 1-Tap Quick Route Presets
                  if (_showSearchBar)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CockpitColors.card.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: CockpitColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _searchController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: _searchAddressAndBuildRoute,
                                    decoration: InputDecoration(
                                      hintText: appState.t('searchHint'),
                                      hintStyle: const TextStyle(
                                        color: CockpitColors.textMuted,
                                        fontSize: 12,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      filled: true,
                                      fillColor: CockpitColors.bg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: CockpitColors.cardBorder,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFCC00),
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(44, 38),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () => _searchAddressAndBuildRoute(
                                  _searchController.text,
                                ),
                                child: const Icon(
                                  Icons.directions_car_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _presets.map((_PresetPlace place) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
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
                                        _destination = place.coords;
                                        _destinationLabel = place.title;
                                        _showSearchBar = false;
                                      });
                                      if (kIsWeb && _mapStyleIndex == 0) {
                                        WebFaceBridge.moveYandexCenter(
                                          place.coords.latitude,
                                          place.coords.longitude,
                                          13,
                                        );
                                      } else {
                                        _mapController.move(place.coords, 13.0);
                                      }
                                      _fetchRealRoadRoute(
                                        _currentLocation,
                                        place.coords,
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

            // 3. Left Map Controls (Zoom +, Zoom -, Recenter GPS, Yandex Map Layer Switcher)
            Positioned(
              left: 12,
              bottom: 66,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildMapIconButton(
                    icon: Icons.add_rounded,
                    onTap: () {
                      _zoom = (_zoom + 1.0).clamp(3.0, 18.5);
                      if (kIsWeb && _mapStyleIndex == 0) {
                        WebFaceBridge.moveYandexCenter(
                          _currentLocation.latitude,
                          _currentLocation.longitude,
                          _zoom,
                        );
                      } else {
                        _mapController.move(_mapController.camera.center, _zoom);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMapIconButton(
                    icon: Icons.remove_rounded,
                    onTap: () {
                      _zoom = (_zoom - 1.0).clamp(3.0, 18.5);
                      if (kIsWeb && _mapStyleIndex == 0) {
                        WebFaceBridge.moveYandexCenter(
                          _currentLocation.latitude,
                          _currentLocation.longitude,
                          _zoom,
                        );
                      } else {
                        _mapController.move(_mapController.camera.center, _zoom);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMapIconButton(
                    icon: Icons.my_location_rounded,
                    color: CockpitColors.safeGreen,
                    onTap: () {
                      if (kIsWeb && _mapStyleIndex == 0) {
                        WebFaceBridge.moveYandexCenter(
                          _currentLocation.latitude,
                          _currentLocation.longitude,
                          _zoom,
                        );
                      } else {
                        _mapController.move(_currentLocation, _zoom);
                      }
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
                      height: 38,
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
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _activeMapStyleLabel,
                            style: const TextStyle(
                              color: Color(0xFFFFCC00),
                              fontSize: 11,
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

            // 4. Bottom Navigation ETA + Speed Limit & Current Speed Bar
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: CockpitColors.card.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        // Speed Limit Sign (60)
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: CockpitColors.dangerRed,
                              width: 3.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '60',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${_currentSpeedKmh.round()} ${appState.t('speedUnit')}',
                              style: const TextStyle(
                                color: CockpitColors.textWhite,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              _destinationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CockpitColors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFCC00).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFCC00).withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        '$_routeEtaMinutes ${appState.t('etaMin')} • ${_formatMeters(_routeTotalMeters)}',
                        style: const TextStyle(
                          color: Color(0xFFFFCC00),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. Draggable Floating PiP Live Camera Preview Window
            Positioned(
              right: _pipOffset.dx,
              top: _pipOffset.dy,
              width: 118,
              height: 154,
              child: GestureDetector(
                onPanUpdate: (DragUpdateDetails details) {
                  setState(() {
                    final double newRight = (_pipOffset.dx - details.delta.dx)
                        .clamp(8.0, constraints.maxWidth - 126.0);
                    final double newTop = (_pipOffset.dy + details.delta.dy)
                        .clamp(48.0, constraints.maxHeight - 210.0);
                    _pipOffset = Offset(newRight, newTop);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: CockpitColors.bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.isEyesOpen
                          ? CockpitColors.safeGreen
                          : CockpitColors.dangerRed,
                      width: 2.2,
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Colors.black87, blurRadius: 16),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        widget.pipCameraPreview,
                        Positioned(
                          bottom: 4,
                          left: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.isEyesOpen
                                  ? appState.t('eyeOpen')
                                  : appState.t('eyeClosed'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: widget.isEyesOpen
                                    ? CockpitColors.safeGreen
                                    : CockpitColors.dangerRed,
                                fontSize: 10,
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CockpitColors.cardBorder),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
