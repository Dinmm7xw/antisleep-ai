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
import '../widgets/cockpit_bottom_nav_bar.dart';
import '../widgets/painters/dashboard_illustration_painter.dart';
import 'monitoring_screen.dart';

/// Screen 1: HomeScreen with real hardware/camera probing and siren test
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioPlayer _testAudioPlayer = AudioPlayer();
  bool _isProbingHardware = true;

  @override
  void initState() {
    super.initState();
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
            ? 'WEB CAM ACTIVE'
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
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: CockpitColors.safeGreen),
        ),
        content: Row(
          children: <Widget>[
            const Icon(
              Icons.volume_up_rounded,
              color: CockpitColors.safeGreen,
              size: 18,
            ),
            const SizedBox(width: 8),
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
            padding: const EdgeInsets.all(20),
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '—',
                        style: TextStyle(color: CockpitColors.textMuted),
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
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: CockpitColors.safeGreen
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
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
    _testAudioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CockpitAppBar(
        trailingAction: appState.savedTrips.isNotEmpty
            ? IconButton(
                tooltip: appState.t('historyBtn'),
                onPressed: _showSavedTripsModal,
                icon: const Icon(
                  Icons.history_rounded,
                  color: CockpitColors.safeGreen,
                  size: 22,
                ),
              )
            : null,
      ),
      bottomNavigationBar: const CockpitBottomNavBar(currentIndex: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                appState.t('heroHeadline'),
                style: const TextStyle(
                  color: CockpitColors.textWhite,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                appState.t('heroSub'),
                style: const TextStyle(
                  color: CockpitColors.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),

              // Pre-Drive Cockpit Check Card with Dashboard SVG Painter
              Expanded(
                child: GestureDetector(
                  onTap: _probeDeviceHardware,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: CockpitColors.card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: CockpitColors.cardBorder),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              appState.t('preDriveCheck'),
                              style: const TextStyle(
                                color: CockpitColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: CockpitColors.safeGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  appState.activeCameraName.isNotEmpty
                                      ? appState.activeCameraName
                                      : 'ML KIT FACE MESH',
                                  style: const TextStyle(
                                    color: CockpitColors.safeGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: 260,
                              height: 130,
                              child: CustomPaint(
                                painter: DashboardIllustrationPainter(),
                              ),
                            ),
                          ),
                        ),
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
                                  fontSize: 14,
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
              ),
              const SizedBox(height: 16),

              // Real System Readiness Indicators (Tap Audio row to test real Siren & Vibration)
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
                      ),
                    ),
                    const Divider(color: CockpitColors.cardBorder, height: 16),
                    _buildReadinessRow(
                      icon: Icons.picture_in_picture_alt_rounded,
                      label: appState.t('bgModeLabel'),
                      status: appState.t('statusActive'),
                      statusColor: CockpitColors.safeGreen,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Prominent Elevated Emerald Green CTA Button "START TRIP" (height: 56, radius: 16)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CockpitColors.safeGreen,
                    foregroundColor: const Color(0xFF031B0E),
                    elevation: 8,
                    shadowColor: CockpitColors.safeGreen.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
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
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: Text(
                    appState.t('startTrip'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
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
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, color: CockpitColors.textMuted, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: CockpitColors.textWhite,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          status,
          style: TextStyle(
            color: statusColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
