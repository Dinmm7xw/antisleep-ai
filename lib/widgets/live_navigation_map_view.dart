import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/web_face_bridge.dart';
import '../state/app_session_state.dart';

/// Interactive Real-Time Map & Navigation HUD (OpenStreetMap / Carto Dark Matter + Live GPS + Draggable PiP Camera).
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

  final MapController _mapController = MapController();
  final Distance _distanceCalc = const Distance();

  // Default coordinates: Almaty (Abay / Dostyk Ave) until live GPS fix arrives
  LatLng _currentLocation = const LatLng(43.2415, 76.9562);
  LatLng _destination = const LatLng(43.2220, 76.9455); // Al-Farabi / Dostyk
  final List<LatLng> _traveledTrail = <LatLng>[];
  List<LatLng> _routeWaypoints = <LatLng>[];

  double _currentSpeedKmh = 48.0;
  double _headingDeg = 185.0;
  double _zoom = 14.5;
  bool _isDarkMapStyle = true;
  bool _hasRealGpsFix = false;
  final bool _simulateDrive = true;

  // Draggable PiP camera overlay position inside the viewport
  Offset _pipOffset = const Offset(14, 118);

  Timer? _gpsPollTimer;

  @override
  void initState() {
    super.initState();
    _traveledTrail.add(_currentLocation);
    _rebuildRouteWaypoints();
    _startGpsTracking();
  }

  void _rebuildRouteWaypoints() {
    final double midLat1 =
        _currentLocation.latitude + (_destination.latitude - _currentLocation.latitude) * 0.35;
    final double midLng1 = _currentLocation.longitude;
    final double midLat2 =
        _currentLocation.latitude + (_destination.latitude - _currentLocation.latitude) * 0.70;
    final double midLng2 = _destination.longitude;

    _routeWaypoints = <LatLng>[
      _currentLocation,
      LatLng(midLat1, midLng1),
      LatLng(midLat2, midLng2),
      _destination,
    ];
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
            _destination = LatLng(newPos.latitude + 0.015, newPos.longitude + 0.012);
            _mapController.move(newPos, _zoom);
          }
          _rebuildRouteWaypoints();
          setState(() {});
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
              _destination =
                  LatLng(newPos.latitude + 0.015, newPos.longitude + 0.012);
              _mapController.move(newPos, _zoom);
            }
            _rebuildRouteWaypoints();
            if (mounted) setState(() {});
            return;
          }
        } catch (_) {}
      }

      // 3. Smooth route progression when stationary/testing so telemetry & map stay live
      if (_simulateDrive && !_hasRealGpsFix) {
        final double dLat = (_destination.latitude - _currentLocation.latitude);
        final double dLng =
            (_destination.longitude - _currentLocation.longitude);
        final double distDeg = math.sqrt(dLat * dLat + dLng * dLng);
        if (distDeg > 0.0004) {
          const double step = 0.00014;
          _currentLocation = LatLng(
            _currentLocation.latitude + (dLat / distDeg) * step,
            _currentLocation.longitude + (dLng / distDeg) * step,
          );
          _headingDeg = (math.atan2(dLng, dLat) * 180 / math.pi + 360) % 360;
          _currentSpeedKmh = 46.0 + (DateTime.now().second % 9);
          _traveledTrail.add(_currentLocation);
          _rebuildRouteWaypoints();
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _gpsPollTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  double get _remainingMeters {
    return _distanceCalc.as(LengthUnit.Meter, _currentLocation, _destination);
  }

  String get _formattedDistance {
    final double m = _remainingMeters;
    if (m >= 1000) {
      return '${(m / 1000).toStringAsFixed(1)} km';
    }
    return '${m.round()} m';
  }

  int get _etaMinutes {
    final double km = _remainingMeters / 1000.0;
    final double speed = _currentSpeedKmh < 15 ? 40.0 : _currentSpeedKmh;
    return math.max(1, ((km / speed) * 60).round());
  }

  @override
  Widget build(BuildContext context) {
    final String tileUrl = _isDarkMapStyle
        ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Interactive FlutterMap with Real Tiles, Route Polylines & GPS Marker
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: _zoom,
                onTap: (TapPosition tapPos, LatLng tappedLatLng) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _destination = tappedLatLng;
                    _rebuildRouteWaypoints();
                  });
                },
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: tileUrl,
                  userAgentPackageName: 'com.antisleep.ai',
                ),
                // Traveled trail + Active Navigation Route Polyline
                PolylineLayer(
                  polylines: <Polyline>[
                    if (_traveledTrail.length > 1)
                      Polyline(
                        points: _traveledTrail,
                        strokeWidth: 4.0,
                        color: CockpitColors.textMuted.withValues(alpha: 0.5),
                      ),
                    Polyline(
                      points: _routeWaypoints,
                      strokeWidth: 6.0,
                      color: CockpitColors.safeGreen,
                      borderStrokeWidth: 2.0,
                      borderColor: const Color(0xFF05331C),
                    ),
                  ],
                ),
                // Destination Pin & Driver GPS Arrow Marker
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: _destination,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: CockpitColors.dangerRed,
                        size: 38,
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
                            color: CockpitColors.safeGreen.withValues(alpha: 0.24),
                            border: Border.all(
                              color: CockpitColors.safeGreen,
                              width: 2,
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

            // 2. Top Turn-by-Turn 2GIS-Style Navigation Banner
            Positioned(
              top: 48,
              left: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: CockpitColors.card.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CockpitColors.cardBorder),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black54, blurRadius: 12),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.turn_right_rounded,
                        color: CockpitColors.safeGreen,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                _formattedDistance,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _hasRealGpsFix
                                      ? CockpitColors.safeGreen
                                          .withValues(alpha: 0.2)
                                      : CockpitColors.cardBorder,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _hasRealGpsFix ? 'GPS LIVE' : '2GIS ROUTE',
                                  style: TextStyle(
                                    color: _hasRealGpsFix
                                        ? CockpitColors.safeGreen
                                        : CockpitColors.textWhite,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            appState.t('tapMapHint'),
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
                    // Button to pop out system-wide floating PiP camera window
                    IconButton(
                      tooltip: appState.t('pipFloatBtn'),
                      onPressed: widget.onTriggerSystemPip,
                      icon: const Icon(
                        Icons.open_in_new_rounded,
                        color: CockpitColors.safeGreen,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Left Map Controls (Zoom +, Zoom -, Recenter GPS, Dark/Light Map Toggle)
            Positioned(
              left: 12,
              bottom: 66,
              child: Column(
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
                  _buildMapIconButton(
                    icon: _isDarkMapStyle
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    onTap: () {
                      setState(() => _isDarkMapStyle = !_isDarkMapStyle);
                    },
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
                              '${_currentLocation.latitude.toStringAsFixed(4)}, ${_currentLocation.longitude.toStringAsFixed(4)}',
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
                        color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: CockpitColors.safeGreen.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '$_etaMinutes ${appState.t('etaMin')} • $_formattedDistance',
                        style: const TextStyle(
                          color: CockpitColors.safeGreen,
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
              width: 122,
              height: 158,
              child: GestureDetector(
                onPanUpdate: (DragUpdateDetails details) {
                  setState(() {
                    final double newRight = (_pipOffset.dx - details.delta.dx)
                        .clamp(8.0, constraints.maxWidth - 130.0);
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

