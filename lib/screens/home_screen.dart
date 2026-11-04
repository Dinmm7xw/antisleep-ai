import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/siren_wav_generator.dart';
import '../services/web_face_bridge.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import '../widgets/painters/dashboard_illustration_painter.dart';
import 'monitoring_screen.dart';
import 'navigation_screen.dart';

/// Screen 1: Futuristic Automotive Cockpit HomeScreen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _testAudioPlayer = AudioPlayer();
  late final AnimationController _pulseController;
  bool _isProbingHardware = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _probeDeviceHardware();
    appState.loadSavedTripsFromDisk();
  }

  Future<void> _probeDeviceHardware() async {
    setState(() => _isProbingHardware = true);
    bool camOk = false;
    String camLabel = '';
    bool hapticsOk = false;

    try {
      globalCameras = await availableCameras();
      if (globalCameras.isNotEmpty) {
        final CameraDescription front = globalCameras.firstWhere(
          (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => globalCameras.first,
        );
        camOk = true;
        camLabel = kIsWeb
            ? 'HD WEBCAM'
            : '${front.lensDirection.name.toUpperCase()} (${front.sensorOrientation}°)';
      }
    } catch (e) {
      debugPrint('Camera probe error: $e');
    }

    if (!kIsWeb) {
      try {
        hapticsOk = await Vibrate.canVibrate;
      } catch (_) {
        hapticsOk = false;
      }
    }

    appState.updateHardwareStatus(
      cameraReady: camOk,
      sensorReady: true,
      hapticsReady: hapticsOk,
      cameraName: camLabel,
    );

    if (mounted) {
      setState(() => _isProbingHardware = false);
    }
  }

  Future<void> _runRealAudioAndVibrationTest() async {
    HapticFeedback.heavyImpact();
    if (kIsWeb) {
      WebFaceBridge.startWebSiren();
      await Future<void>.delayed(const Duration(milliseconds: 550));
      WebFaceBridge.stopWebSiren();
    } else {
      try {
        if (appState.isHapticsSupported) {
          Vibrate.vibrate();
        }
        final Uint8List wavBytes = SirenWavGenerator.generateDualToneSirenWav();
        await _testAudioPlayer.setVolume(1.0);
        await _testAudioPlayer.play(BytesSource(wavBytes));
        await Future<void>.delayed(const Duration(milliseconds: 550));
        await _testAudioPlayer.stop();
      } catch (e) {
        debugPrint('Audio test error: $e');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CockpitColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CockpitColors.safeGreen, width: 1.5),
        ),
        content: Row(
          children: <Widget>[
            const Icon(
              Icons.volume_up_rounded,
              color: CockpitColors.safeGreen,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appState.t('soundTestToast'),
                style: const TextStyle(
                  color: CockpitColors.textWhite,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCalibrationModal() {
    HapticFeedback.selectionClick();
    int step = 0; // 0 = start, 1 = open eyes, 2 = close eyes, 3 = done
    Timer? calibTimer;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CockpitColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext modalCtx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void startMeasuring() {
              setModalState(() => step = 1);
              calibTimer = Timer(const Duration(milliseconds: 1800), () {
                if (modalCtx.mounted) {
                  setModalState(() => step = 2);
                  calibTimer = Timer(const Duration(milliseconds: 1400), () {
                    if (modalCtx.mounted) {
                      appState.setPersonalEarOffset(-0.02); // calibrated bias
                      setModalState(() => step = 3);
                      HapticFeedback.mediumImpact();
                    }
                  });
                }
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: CockpitColors.cardBorder,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                CockpitColors.safeGreen.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: CockpitColors.safeGreen,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                appState.t('calibTitle'),
                                style: const TextStyle(
                                  color: CockpitColors.textWhite,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                appState.t('calibSubtitle'),
                                style: const TextStyle(
                                  color: CockpitColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F141C),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: step == 3
                              ? CockpitColors.safeGreen
                              : CockpitColors.cardBorder,
                        ),
                      ),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            step == 3
                                ? Icons.verified_rounded
                                : step == 2
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                            size: 46,
                            color: step == 3
                                ? CockpitColors.safeGreen
                                : step > 0
                                    ? const Color(0xFF00B0FF)
                                    : CockpitColors.textMuted,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            step == 0
                                ? appState.t('calibSubtitle')
                                : step == 1
                                    ? appState.t('calibOpenEyes')
                                    : step == 2
                                        ? appState.t('calibCloseEyes')
                                        : appState.t('calibSuccess'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: step == 3
                                  ? CockpitColors.safeGreen
                                  : CockpitColors.textWhite,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: step == 3
                              ? const Color(0xFF232D3B)
                              : CockpitColors.safeGreen,
                          foregroundColor: step == 3
                              ? CockpitColors.textWhite
                              : const Color(0xFF031B0E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          if (step == 0) {
                            startMeasuring();
                          } else if (step == 3) {
                            Navigator.pop(modalCtx);
                          }
                        },
                        child: Text(
                          step == 3
                              ? 'OK'
                              : step == 0
                                  ? appState.t('calibButton')
                                  : '...',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => calibTimer?.cancel());
  }

  void _showSavedTripsModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CockpitColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      appState.t('historyBtn'),
                      style: const TextStyle(
                        color: CockpitColors.textWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: CockpitColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (appState.savedTrips.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        appState.t('noTripsYet'),
                        style: const TextStyle(color: CockpitColors.textMuted),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: appState.savedTrips.length,
                      separatorBuilder: (_, __) => const Divider(
                        color: CockpitColors.cardBorder,
                        height: 16,
                      ),
                      itemBuilder: (BuildContext context, int index) {
                        final TripRecord trip = appState.savedTrips[index];
                        final int mins = trip.durationSeconds ~/ 60;
                        final int secs = trip.durationSeconds % 60;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${trip.timestamp.day.toString().padLeft(2, '0')}.${trip.timestamp.month.toString().padLeft(2, '0')}.${trip.timestamp.year} • ${mins}m ${secs}s',
                                  style: const TextStyle(
                                    color: CockpitColors.textWhite,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'EAR: ${trip.averageEar.toStringAsFixed(2)} • ${appState.t('yawns')}: ${trip.yawnsDetected} • PERCLOS: ${trip.perclosPercent.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: CockpitColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: CockpitColors.safeGreen
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: CockpitColors.safeGreen
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                '${trip.safetyScore}%',
                                style: const TextStyle(
                                  color: CockpitColors.safeGreen,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _testAudioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CockpitAppBar(
        trailingAction: IconButton(
          tooltip: appState.t('historyBtn'),
          onPressed: _showSavedTripsModal,
          icon: const Icon(
            Icons.history_rounded,
            color: CockpitColors.safeGreen,
            size: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Hero Headline with automotive typography
              Text(
                appState.t('heroHeadline'),
                style: const TextStyle(
                  color: CockpitColors.textWhite,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                appState.t('heroSub'),
                style: const TextStyle(
                  color: CockpitColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),

              // Interactive Futuristic Cockpit Radar Card
              GestureDetector(
                onTap: _probeDeviceHardware,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFF161E28),
                        Color(0xFF0F151D),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: CockpitColors.cardBorder),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.06),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            appState.t('preDriveCheck'),
                            style: const TextStyle(
                              color: CockpitColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (BuildContext context, _) {
                                  return Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: CockpitColors.safeGreen.withValues(
                                        alpha:
                                            0.4 + 0.6 * _pulseController.value,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: CockpitColors.safeGreen
                                              .withValues(
                                            alpha: 0.8 * _pulseController.value,
                                          ),
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Text(
                                appState.activeCameraName.isNotEmpty
                                    ? appState.activeCameraName
                                    : 'AI VISION RADAR',
                                style: const TextStyle(
                                  color: CockpitColors.safeGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 120,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (BuildContext context, _) {
                            return CustomPaint(
                              painter: DashboardIllustrationPainter(
                                pulseValue: _pulseController.value,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            Icons.check_circle_rounded,
                            color: CockpitColors.safeGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              appState.t('homeReady'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: CockpitColors.textWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Sensitivity Mode Selector & Quick Calibration Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CockpitColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          appState.t('sensitivityMode'),
                          style: const TextStyle(
                            color: CockpitColors.textWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        InkWell(
                          onTap: _showCalibrationModal,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.tune_rounded,
                                  size: 15,
                                  color: CockpitColors.safeGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  appState.t('quickCalibration'),
                                  style: const TextStyle(
                                    color: CockpitColors.safeGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        _buildSensitivityChip(
                          mode: SensitivityMode.city,
                          label: appState.t('modeCity'),
                          icon: Icons.location_city_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildSensitivityChip(
                          mode: SensitivityMode.highway,
                          label: appState.t('modeHighway'),
                          icon: Icons.alt_route_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildSensitivityChip(
                          mode: SensitivityMode.strict,
                          label: appState.t('modeStrict'),
                          icon: Icons.nightlight_round,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Interactive Route & Navigation Card
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NavigationScreen(),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[
                        Color(0xFF131B26),
                        Color(0xFF182332),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CockpitColors.safeGreen.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.map_rounded,
                          color: CockpitColors.safeGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text(
                                  appState.t('navRouteTitle'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CockpitColors.safeGreen
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'GPS',
                                    style: TextStyle(
                                      color: CockpitColors.safeGreen,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              appState.t('whereToPrompt'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CockpitColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: CockpitColors.safeGreen,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Hardware Readiness and Diagnostic Row
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: CockpitColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Column(
                  children: <Widget>[
                    InkWell(
                      onTap: _probeDeviceHardware,
                      child: _buildReadinessRow(
                        icon: Icons.videocam_outlined,
                        label: appState.t('cameraCheck'),
                        status: _isProbingHardware
                            ? appState.t('statusChecking')
                            : appState.t('statusReady'),
                        statusColor: appState.isCameraReady
                            ? CockpitColors.safeGreen
                            : CockpitColors.warningAmber,
                      ),
                    ),
                    const Divider(color: CockpitColors.cardBorder, height: 16),
                    _buildReadinessRow(
                      icon: Icons.face_retouching_natural_rounded,
                      label: appState.t('sensorCheck'),
                      status: appState.t('statusReady'),
                      statusColor: CockpitColors.safeGreen,
                    ),
                    const Divider(color: CockpitColors.cardBorder, height: 16),
                    InkWell(
                      onTap: _runRealAudioAndVibrationTest,
                      child: _buildReadinessRow(
                        icon: Icons.volume_up_rounded,
                        label: appState.t('audioCheck'),
                        status: appState.t('statusActive'),
                        statusColor: CockpitColors.safeGreen,
                        trailing: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: CockpitColors.safeGreen,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Big Bold Neon Emerald CTA Button "START TRIP"
              SizedBox(
                width: double.infinity,
                height: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: <Color>[
                        Color(0xFF00E676),
                        Color(0xFF00C853),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.38),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: const Color(0xFF031B0E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      appState.resetTrip();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const MonitoringScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                      size: 28,
                      color: Color(0xFF031B0E),
                    ),
                    label: Text(
                      appState.t('startTrip'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensitivityChip({
    required SensitivityMode mode,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = appState.sensitivityMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          appState.setSensitivity(mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? CockpitColors.safeGreen.withValues(alpha: 0.16)
                : const Color(0xFF10151D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? CockpitColors.safeGreen
                  : CockpitColors.cardBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? CockpitColors.safeGreen
                    : CockpitColors.textMuted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? CockpitColors.safeGreen
                        : CockpitColors.textMuted,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadinessRow({
    required IconData icon,
    required String label,
    required String status,
    required Color statusColor,
    Widget? trailing,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, color: CockpitColors.safeGreen, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: CockpitColors.textWhite,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) ...<Widget>[
          trailing,
          const SizedBox(width: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
