import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/cockpit_colors.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import 'danger_alert_screen.dart';

/// Preset automotive destination with distance and time estimates
class RouteDestination {
  final String title;
  final String subtitle;
  final double distanceKm;
  final int durationMinutes;
  final IconData icon;
  final List<String> restStops;

  const RouteDestination({
    required this.title,
    required this.subtitle,
    required this.distanceKm,
    required this.durationMinutes,
    required this.icon,
    required this.restStops,
  });
}

/// Interactive Automotive Map & Route Planning Screen with AntiSleep AI PiP Protection
class NavigationScreen extends StatefulWidget {
  final String? initialDestination;

  const NavigationScreen({
    super.key,
    this.initialDestination,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _carAnimController;
  final TextEditingController _searchController = TextEditingController();

  // Route presets popular in Kazakhstan
  final List<RouteDestination> _destinations = const <RouteDestination>[
    RouteDestination(
      title: 'Медеу (Medeu)',
      subtitle: 'Тау бөктері • Горный кластер',
      distanceKm: 14.8,
      durationMinutes: 24,
      icon: Icons.terrain_rounded,
      restStops: <String>['Compass АЗС (Достық)', 'Starbucks Coffee', 'Бұлақ демалысы'],
    ),
    RouteDestination(
      title: 'Қонаев қаласы (Қапшағай трассасы)',
      subtitle: 'А-3 тас жолы • Трасса',
      distanceKm: 78.4,
      durationMinutes: 58,
      icon: Icons.alt_route_rounded,
      restStops: <String>['QazaqOil Трасса АЗС', 'Compass Oasis Motel', 'Food Court 24/7'],
    ),
    RouteDestination(
      title: 'Астана (Нұр-Сұлтан)',
      subtitle: 'Трасса М-36 • Ұзақ сапар (1200 км)',
      distanceKm: 1210.0,
      durationMinutes: 840,
      icon: Icons.flight_takeoff_rounded,
      restStops: <String>['Балқаш демалыс бекеті', 'Қарағанды Кемпинг', 'Helios АЗС'],
    ),
    RouteDestination(
      title: 'Шымбұлақ (Shymbulak)',
      subtitle: 'Көкжайлау бұрылысы',
      distanceKm: 21.2,
      durationMinutes: 38,
      icon: Icons.downhill_skiing_rounded,
      restStops: <String>['Ecosphere Rest Stop', 'Кафе Алатау'],
    ),
    RouteDestination(
      title: 'Халықаралық Әуежай (ALA)',
      subtitle: 'Майлин көшесі',
      distanceKm: 16.5,
      durationMinutes: 28,
      icon: Icons.local_airport_rounded,
      restStops: <String>['Sinooil АЗС', 'Drive-Thru Coffee'],
    ),
  ];

  late RouteDestination _selectedDestination;
  bool _isNavigating = true;
  int _currentSpeed = 68;
  Timer? _speedTimer;
  Timer? _drowsinessSimulationCheck;

  // Selected filter category
  String _selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    _selectedDestination = _destinations.first;
    _searchController.text = _selectedDestination.title;

    _carAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    // Minor speed variance to simulate real driving HUD
    _speedTimer = Timer.periodic(const Duration(seconds: 2), (Timer t) {
      if (!mounted) return;
      setState(() {
        final math.Random rng = math.Random();
        _currentSpeed = 62 + rng.nextInt(12);
      });
    });

    // Background listener: if micro-sleep trigger happens, trigger alarm modal
    _drowsinessSimulationCheck =
        Timer.periodic(const Duration(milliseconds: 300), (Timer t) {
      if (!mounted) return;
      if (appState.microSleepEvents > 0 && !_isAlarmOpen) {
        _triggerAlarm();
      }
    });
  }

  bool _isAlarmOpen = false;
  Future<void> _triggerAlarm() async {
    _isAlarmOpen = true;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, __, ___) => const DangerAlertScreen(),
      ),
    );
    _isAlarmOpen = false;
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _drowsinessSimulationCheck?.cancel();
    _carAnimController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showRouteSearchSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CockpitColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext modalCtx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            final List<RouteDestination> filtered = _destinations.where((RouteDestination d) {
              final String q = _searchController.text.toLowerCase();
              return d.title.toLowerCase().contains(q) ||
                  d.subtitle.toLowerCase().contains(q);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: CockpitColors.cardBorder,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      appState.t('navRouteTitle'),
                      style: const TextStyle(
                        color: CockpitColors.textWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Search Text Field
                    TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0E131A),
                        hintText: appState.t('searchDestination'),
                        hintStyle: const TextStyle(color: CockpitColors.textMuted),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: CockpitColors.safeGreen,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54),
                                onPressed: () {
                                  _searchController.clear();
                                  setSheetState(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: CockpitColors.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: CockpitColors.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: CockpitColors.safeGreen,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quick POI Categories
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          _buildFilterChip('all', 'Барлығы / Все'),
                          const SizedBox(width: 8),
                          _buildFilterChip('gas', appState.t('categoryGas')),
                          const SizedBox(width: 8),
                          _buildFilterChip('coffee', appState.t('categoryCoffee')),
                          const SizedBox(width: 8),
                          _buildFilterChip('motel', appState.t('categoryMotel')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: CockpitColors.cardBorder, height: 1),
                    const SizedBox(height: 10),
                    // Destinations list
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: CockpitColors.cardBorder, height: 14),
                        itemBuilder: (BuildContext _, int idx) {
                          final RouteDestination d = filtered[idx];
                          final bool isSelected = _selectedDestination.title == d.title;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedDestination = d;
                                _searchController.text = d.title;
                              });
                              Navigator.pop(modalCtx);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? CockpitColors.safeGreen
                                          : const Color(0xFF161F2A),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      d.icon,
                                      color: isSelected
                                          ? const Color(0xFF031B0E)
                                          : CockpitColors.safeGreen,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          d.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          d.subtitle,
                                          style: const TextStyle(
                                            color: CockpitColors.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Text(
                                        '${d.distanceKm} ${appState.t('distanceKm')}',
                                        style: const TextStyle(
                                          color: CockpitColors.safeGreen,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '~${d.durationMinutes} ${appState.t('durationMin')}',
                                        style: const TextStyle(
                                          color: CockpitColors.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
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
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String code, String label) {
    final bool isSelected = _selectedCategory == code;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCategory = code);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? CockpitColors.safeGreen.withValues(alpha: 0.16)
              : const Color(0xFF131922),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? CockpitColors.safeGreen : CockpitColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? CockpitColors.safeGreen : CockpitColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CockpitAppBar(
        titleOverride: appState.t('navRouteTitle'),
        trailingAction: IconButton(
          tooltip: appState.t('searchDestination'),
          onPressed: _showRouteSearchSheet,
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: CockpitColors.safeGreen.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: CockpitColors.safeGreen.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: CockpitColors.safeGreen,
              size: 18,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 1. Full Automotive Map Viewport
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _carAnimController,
                builder: (BuildContext context, _) {
                  return CustomPaint(
                    painter: InteractiveAutomotiveMapPainter(
                      progress: _carAnimController.value,
                      destinationName: _selectedDestination.title,
                      restStops: _selectedDestination.restStops,
                    ),
                  );
                },
              ),
            ),

            // 2. Top Navigation Guidance Turn-by-Turn Card
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF121720).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: CockpitColors.safeGreen.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.turn_right_rounded,
                        color: CockpitColors.safeGreen,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            '250 м',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Достық даңғылы • ${_selectedDestination.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CockpitColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: _showRouteSearchSheet,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C2430),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          color: CockpitColors.safeGreen,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Top-Right AntiSleep AI Live Biometric PiP Floating Tile
            Positioned(
              top: 104,
              right: 14,
              child: Container(
                width: 110,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF121720).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: CockpitColors.safeGreen,
                    width: 1.5,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black54, blurRadius: 12),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: CockpitColors.safeGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'AI GUARD',
                          style: TextStyle(
                            color: CockpitColors.safeGreen,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.face_retouching_natural_rounded,
                      color: CockpitColors.safeGreen,
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'EAR: ${appState.averageEar.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Score: ${appState.calculatedSafetyScore}%',
                      style: const TextStyle(
                        color: CockpitColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Smart Rest Stop Prompt Pill (along route)
            Positioned(
              bottom: 115,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161E28).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_gas_station_rounded,
                        color: Colors.amber,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${appState.t('suggestedStops')} ${_selectedDestination.restStops.first}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '+2.4 км',
                        style: TextStyle(
                          color: CockpitColors.safeGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. Bottom Automotive Cockpit Nav Strip (Speed + Distance + ETA + Back)
            Positioned(
              bottom: 14,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10151E),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CockpitColors.cardBorder),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black87, blurRadius: 20),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // Speedometer pill
                    Row(
                      children: <Widget>[
                        Text(
                          '$_currentSpeed',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'км/сағ',
                              style: TextStyle(
                                color: CockpitColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '[60]',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Route metrics
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '${_selectedDestination.distanceKm} ${appState.t('distanceKm')} • ${_selectedDestination.durationMinutes} ${appState.t('durationMin')}',
                          style: const TextStyle(
                            color: CockpitColors.safeGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedDestination.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CockpitColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                    // Finish / Switch back button
                    IconButton(
                      tooltip: 'Жабу',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CockpitColors.dangerRed.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: CockpitColors.dangerRed),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: CockpitColors.dangerRed,
                          size: 18,
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
    );
  }
}

/// Vector Dark Automotive Map Canvas Painter with live road network and pulsing car position
class InteractiveAutomotiveMapPainter extends CustomPainter {
  final double progress;
  final String destinationName;
  final List<String> restStops;

  InteractiveAutomotiveMapPainter({
    required this.progress,
    required this.destinationName,
    required this.restStops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // 1. Dark Map Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0C1117),
    );

    // 2. City Blocks and Secondary Grid Roads
    final Paint secondaryRoadPaint = Paint()
      ..color = const Color(0xFF17202C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;

    // Horizontal secondary streets
    for (double y = 0.15; y < 0.95; y += 0.14) {
      canvas.drawLine(Offset(0, h * y), Offset(w, h * y), secondaryRoadPaint);
    }
    // Vertical secondary streets
    for (double x = 0.18; x < 0.95; x += 0.22) {
      canvas.drawLine(Offset(w * x, 0), Offset(w * x, h), secondaryRoadPaint);
    }

    // 3. Water feature / River curve (e.g. Esentai / Ile river)
    final Paint riverPaint = Paint()
      ..color = const Color(0xFF10283A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26
      ..strokeCap = StrokeCap.round;

    final Path river = Path()
      ..moveTo(0, h * 0.18)
      ..cubicTo(w * 0.35, h * 0.28, w * 0.65, h * 0.08, w, h * 0.32);
    canvas.drawPath(river, riverPaint);

    // 4. Primary Arterial Avenues (Dostyk / Al-Farabi highway)
    final Paint mainAvenuePaint = Paint()
      ..color = const Color(0xFF222F3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path mainAvenue = Path()
      ..moveTo(w * 0.25, h * 0.98)
      ..lineTo(w * 0.25, h * 0.58)
      ..lineTo(w * 0.72, h * 0.58)
      ..lineTo(w * 0.72, h * 0.16);
    canvas.drawPath(mainAvenue, mainAvenuePaint);

    // 5. Active Glowing GPS Route Line (Emerald Cyan Neon)
    final Paint routeGlowPaint = Paint()
      ..color = CockpitColors.safeGreen.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint routeLinePaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[
          Color(0xFF00E676),
          Color(0xFF00B0FF),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path activeRoute = Path()
      ..moveTo(w * 0.25, h * 0.92)
      ..lineTo(w * 0.25, h * 0.58)
      ..lineTo(w * 0.72, h * 0.58)
      ..lineTo(w * 0.72, h * 0.22);

    canvas.drawPath(activeRoute, routeGlowPaint);
    canvas.drawPath(activeRoute, routeLinePaint);

    // 6. Rest Stops & Gas Stations POI Markers along route
    final Offset gasStationPos = Offset(w * 0.48, h * 0.58);
    _drawPoiMarker(
      canvas: canvas,
      center: gasStationPos,
      color: Colors.amber,
      iconType: 'gas',
    );

    final Offset coffeeStopPos = Offset(w * 0.72, h * 0.42);
    _drawPoiMarker(
      canvas: canvas,
      center: coffeeStopPos,
      color: const Color(0xFF00B0FF),
      iconType: 'coffee',
    );

    // 7. Destination Target Marker (Checker Flag Point)
    final Offset destPos = Offset(w * 0.72, h * 0.22);
    final Paint destCirclePaint = Paint()
      ..color = CockpitColors.dangerRed
      ..style = PaintingStyle.fill;
    canvas.drawCircle(destPos, 10, destCirclePaint);
    canvas.drawCircle(
      destPos,
      16,
      Paint()
        ..color = CockpitColors.dangerRed.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // 8. Animated Current Vehicle Marker along route
    Offset currentCarPos;
    double carAngle = -math.pi * 0.5;

    if (progress < 0.4) {
      // Leg 1: Going north
      final double legP = progress / 0.4;
      final double y = math.max(h * 0.58, h * 0.92 - legP * (h * 0.34));
      currentCarPos = Offset(w * 0.25, y);
      carAngle = -math.pi * 0.5;
    } else if (progress < 0.75) {
      // Leg 2: Going east
      final double legP = (progress - 0.4) / 0.35;
      final double x = w * 0.25 + legP * (w * 0.47);
      currentCarPos = Offset(x, h * 0.58);
      carAngle = 0.0;
    } else {
      // Leg 3: Going north to destination
      final double legP = (progress - 0.75) / 0.25;
      final double y = h * 0.58 - legP * (h * 0.36);
      currentCarPos = Offset(w * 0.72, y);
      carAngle = -math.pi * 0.5;
    }

    _drawCarPuck(canvas: canvas, center: currentCarPos, angle: carAngle);
  }

  void _drawPoiMarker({
    required Canvas canvas,
    required Offset center,
    required Color color,
    required String iconType,
  }) {
    canvas.drawCircle(
      center,
      12,
      Paint()..color = const Color(0xFF151D28),
    );
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      4,
      Paint()..color = color,
    );
  }

  void _drawCarPuck({
    required Canvas canvas,
    required Offset center,
    required double angle,
  }) {
    // Pulse radar ring around vehicle
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..color = CockpitColors.safeGreen.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..color = CockpitColors.safeGreen
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Heading arrow triangle
    final Paint arrowPaint = Paint()
      ..color = const Color(0xFF031B0E)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final Path arrow = Path()
      ..moveTo(6, 0)
      ..lineTo(-4, -4)
      ..lineTo(-2, 0)
      ..lineTo(-4, 4)
      ..close();
    canvas.drawPath(arrow, arrowPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant InteractiveAutomotiveMapPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.destinationName != destinationName;
}
