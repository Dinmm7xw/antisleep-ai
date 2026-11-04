import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/mlkit_image_converter.dart';
import '../services/web_face_bridge.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import '../widgets/painters/face_mesh_overlay_painter.dart';
import 'danger_alert_screen.dart';
import 'summary_screen.dart';

/// Screen 2: Active Monitoring HUD Screen with Live Telemetry & Night Illumination
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessingFrame = false;
  bool _isCameraInitialized = false;
  bool _isAlarmRouteOpen = false;
  bool _isPipOverlayMode = false;
  bool _isNightScreenGlowActive = false;
  String? _cameraErrorText;

  List<Face> _detectedFaces = <Face>[];
  WebFaceFrameData? _webFaceData;
  Size _imageSize = const Size(480, 640);
  InputImageRotation _rotation = InputImageRotation.rotation270deg;
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  // Live Biometric Telemetry
  double _leftEyeProb = 0.96;
  double _rightEyeProb = 0.96;
  double _liveEar = 0.32;
  double _liveMar = 0.14;
  double _headPitch = 0.0;
  double _headYaw = 0.0;

  // Continuous Timers for Micro-Sleep (> 1.5s), Yawn (> 2.0s), Blink, Head Nod (> 1.8s)
  DateTime? _eyesClosedSince;
  DateTime? _mouthOpenSince;
  DateTime? _headDroopSince;
  DateTime _yawnCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _nodCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Blink State Machine
  bool _wasEyeClosedForBlink = false;
  DateTime? _blinkStartedAt;

  // Active Warning Toast Banner
  String? _activeWarningBannerText;
  Timer? _bannerClearTimer;

  // Trip Duration & Web Face Polling Timer
  Timer? _tripClockTimer;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      _initFaceDetector();
    }
    _initFrontCamera();
    _startTripClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initFrontCamera();
    }
  }

  void _initFaceDetector() {
    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: true,
          enableContours: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.15,
        ),
      );
    } catch (e) {
      debugPrint('FaceDetector init error: $e');
    }
  }

  Future<void> _initFrontCamera() async {
    try {
      if (globalCameras.isEmpty) {
        globalCameras = await availableCameras();
      }

      if (globalCameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraErrorText = 'No front cameras detected.');
        }
        return;
      }

      final CameraDescription frontCamera = globalCameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => globalCameras.first,
      );
      _lensDirection = frontCamera.lensDirection;

      final CameraController controller = CameraController(
        frontCamera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      _cameraController = controller;
      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _cameraErrorText = null;
      });

      if (!kIsWeb) {
        await controller.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        setState(() => _cameraErrorText = 'Camera error: $e');
      }
    }
  }

  void _startTripClock() {
    _stopwatch.start();
    _tripClockTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      if (!mounted) return;
      appState.updateDuration(_stopwatch.elapsed);

      // Web: Read live biometric data directly from Web Face Bridge
      if (kIsWeb) {
        final WebFaceFrameData? data = WebFaceBridge.pollLatestWebFaceFrame();
        _webFaceData = data;
        if (data != null && data.faceFound) {
          _evaluateRealBiometrics(
            FaceBiometrics(
              ear: data.ear,
              mar: data.mar,
              leftEyeOpenProb:
                  data.ear >= appState.effectiveEarThreshold ? 0.95 : 0.05,
              rightEyeOpenProb:
                  data.ear >= appState.effectiveEarThreshold ? 0.95 : 0.05,
              headPitchX: data.pitch,
              headYawY: data.yaw,
              headRollZ: 0.0,
              isHeadDrooping: data.pitch < -15.0,
              isLookingAway: data.yaw.abs() > 30.0,
            ),
          );
          return;
        } else {
          _eyesClosedSince = null;
          _mouthOpenSince = null;
          _headDroopSince = null;
          setState(() {});
          return;
        }
      }

      // Check continuous eye closure threshold in real time
      if (_eyesClosedSince != null && !_isAlarmRouteOpen) {
        final int closedMs =
            DateTime.now().difference(_eyesClosedSince!).inMilliseconds;
        if (closedMs >= 1500) {
          _eyesClosedSince = null;
          _triggerDangerAlert();
        } else {
          setState(() {});
        }
      }
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingFrame || _isAlarmRouteOpen || !mounted) return;
    final CameraDescription? camera = _cameraController?.description;
    if (camera == null) return;

    _isProcessingFrame = true;

    try {
      _rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation270deg;

      final InputImage? inputImage = MlKitImageConverter.fromCameraImage(
        image: image,
        camera: camera,
      );

      if (inputImage != null && _faceDetector != null) {
        final List<Face> faces = await _faceDetector!.processImage(inputImage);
        if (!mounted) return;

        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        _detectedFaces = faces;

        if (faces.isNotEmpty) {
          final FaceBiometrics bio =
              MlKitImageConverter.extractBiometrics(faces.first);
          _evaluateRealBiometrics(bio);
        } else {
          _eyesClosedSince = null;
          _mouthOpenSince = null;
          _headDroopSince = null;
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('FaceDetector frame error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _evaluateRealBiometrics(FaceBiometrics bio) {
    if (!mounted || _isAlarmRouteOpen) return;

    final DateTime now = DateTime.now();
    _leftEyeProb = bio.leftEyeOpenProb;
    _rightEyeProb = bio.rightEyeOpenProb;
    _liveEar = bio.ear;
    _liveMar = bio.mar;
    _headPitch = bio.headPitchX;
    _headYaw = bio.headYawY;

    final double threshold = appState.effectiveEarThreshold;
    final bool eyesClosed =
        (bio.leftEyeOpenProb < 0.25 && bio.rightEyeOpenProb < 0.25) ||
            bio.ear < threshold;

    appState.recordBiometricFrame(ear: bio.ear, eyesClosed: eyesClosed);

    // 1. Continuous Eye Closure Check (> 1.5s) & Blink Counter
    if (eyesClosed) {
      _eyesClosedSince ??= now;
      if (!_wasEyeClosedForBlink) {
        _wasEyeClosedForBlink = true;
        _blinkStartedAt = now;
      }

      final int closedMs = now.difference(_eyesClosedSince!).inMilliseconds;
      if (closedMs >= 1500 && !_isAlarmRouteOpen) {
        _eyesClosedSince = null;
        _wasEyeClosedForBlink = false;
        _triggerDangerAlert();
        return;
      }
    } else {
      if (_wasEyeClosedForBlink && _blinkStartedAt != null) {
        final int blinkDurationMs =
            now.difference(_blinkStartedAt!).inMilliseconds;
        if (blinkDurationMs >= 50 && blinkDurationMs <= 550) {
          appState.incrementBlink();
        }
      }
      _wasEyeClosedForBlink = false;
      _blinkStartedAt = null;
      _eyesClosedSince = null;
    }

    // 2. Continuous Yawn Check (MAR > 0.48 for > 2.0s)
    if (bio.mar > 0.48) {
      _mouthOpenSince ??= now;
      final int yawnMs = now.difference(_mouthOpenSince!).inMilliseconds;
      if (yawnMs >= 2000 && now.isAfter(_yawnCooldownUntil)) {
        _mouthOpenSince = null;
        _yawnCooldownUntil = now.add(const Duration(seconds: 4));
        appState.incrementYawn();
        HapticFeedback.heavyImpact();
        _showTemporaryBanner(appState.t('yawnToast'));
      }
    } else {
      _mouthOpenSince = null;
    }

    // 3. Head Droop Check (Pitch < -15 deg for > 1.8s)
    if (bio.isHeadDrooping) {
      _headDroopSince ??= now;
      final int nodMs = now.difference(_headDroopSince!).inMilliseconds;
      if (nodMs >= 1800 && now.isAfter(_nodCooldownUntil)) {
        _headDroopSince = null;
        _nodCooldownUntil = now.add(const Duration(seconds: 4));
        appState.incrementHeadNod();
        HapticFeedback.heavyImpact();
        _showTemporaryBanner(appState.t('headNodToast'));
      }
    } else {
      _headDroopSince = null;
    }

    setState(() {});
  }

  void _showTemporaryBanner(String message) {
    _bannerClearTimer?.cancel();
    setState(() => _activeWarningBannerText = message);
    _bannerClearTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _activeWarningBannerText = null);
      }
    });
  }

  Future<void> _triggerDangerAlert() async {
    if (_isAlarmRouteOpen || !mounted) return;
    _isAlarmRouteOpen = true;
    appState.incrementDangerTrigger();

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, __, ___) => const DangerAlertScreen(),
        transitionsBuilder: (_, Animation<double> anim, __, Widget child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );

    if (mounted) {
      setState(() {
        _isAlarmRouteOpen = false;
        _eyesClosedSince = null;
      });
    }
  }

  Future<void> _stopTripAndNavigateToSummary() async {
    _stopwatch.stop();
    _tripClockTimer?.cancel();
    _bannerClearTimer?.cancel();
    try {
      if (!kIsWeb &&
          _cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const SummaryScreen(),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tripClockTimer?.cancel();
    _bannerClearTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final String h = d.inHours.toString().padLeft(2, '0');
    final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasFace = _detectedFaces.isNotEmpty ||
        (_webFaceData != null && _webFaceData!.faceFound);
    final double avgEyeOpen =
        ((_leftEyeProb + _rightEyeProb) / 2.0).clamp(0.0, 1.0);
    final double threshold = appState.effectiveEarThreshold;
    final bool isEyesOpen = avgEyeOpen >= 0.25 && _liveEar >= threshold;
    final int eyeOpenPct = (avgEyeOpen * 100).round();

    final int closedElapsedMs = _eyesClosedSince != null
        ? DateTime.now().difference(_eyesClosedSince!).inMilliseconds
        : 0;
    final double closureProgress = (closedElapsedMs / 1500.0).clamp(0.0, 1.0);

    final int liveScore = appState.calculatedSafetyScore;

    final int fatiguePct = (8 +
            (appState.perclosPercent * 1.4) +
            (appState.totalYawns * 9) +
            (appState.headNodEvents * 10) +
            (appState.microSleepEvents * 20) +
            (closureProgress * 45))
        .round()
        .clamp(5, 100);

    return Scaffold(
      appBar: CockpitAppBar(
        titleOverride: appState.t('monitoringHeader'),
        trailingAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Night Illumination toggle button
            IconButton(
              tooltip: appState.t('nightLightBoost'),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _isNightScreenGlowActive = !_isNightScreenGlowActive);
              },
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _isNightScreenGlowActive
                      ? Colors.amber.withValues(alpha: 0.2)
                      : CockpitColors.card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: _isNightScreenGlowActive
                        ? Colors.amber
                        : CockpitColors.cardBorder,
                  ),
                ),
                child: Icon(
                  Icons.wb_sunny_rounded,
                  size: 18,
                  color: _isNightScreenGlowActive
                      ? Colors.amber
                      : CockpitColors.textWhite,
                ),
              ),
            ),
            // PiP Navigation toggle
            IconButton(
              tooltip: appState.t('pipNavTitle'),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _isPipOverlayMode = !_isPipOverlayMode);
              },
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _isPipOverlayMode
                      ? CockpitColors.safeGreen.withValues(alpha: 0.2)
                      : CockpitColors.card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: _isPipOverlayMode
                        ? CockpitColors.safeGreen
                        : CockpitColors.cardBorder,
                  ),
                ),
                child: Icon(
                  Icons.map_rounded,
                  size: 18,
                  color: _isPipOverlayMode
                      ? CockpitColors.safeGreen
                      : CockpitColors.textWhite,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: <Widget>[
              // Warning Banner if active
              if (_activeWarningBannerText != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: CockpitColors.warningAmber.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CockpitColors.warningAmber),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: CockpitColors.warningAmber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _activeWarningBannerText!,
                          style: const TextStyle(
                            color: CockpitColors.textWhite,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Main Live Camera Viewport + Face Contour Overlay + Night Illumination Glow
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isNightScreenGlowActive
                          ? Colors.white
                          : (isEyesOpen
                              ? CockpitColors.cardBorder
                              : CockpitColors.dangerRed),
                      width: _isNightScreenGlowActive ? 6.0 : 1.5,
                    ),
                    boxShadow: _isNightScreenGlowActive
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.7),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (_isPipOverlayMode)
                          _buildPipNavigationView(isEyesOpen)
                        else
                          _buildCameraHudView(isEyesOpen),

                        // Top-Left LIVE Badge + Elapsed Duration
                        Positioned(
                          top: 14,
                          left: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: CockpitColors.bg.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: CockpitColors.cardBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: hasFace
                                        ? CockpitColors.safeGreen
                                        : CockpitColors.warningAmber,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'LIVE • ${_formatDuration(appState.driveDuration)}',
                                  style: const TextStyle(
                                    color: CockpitColors.textWhite,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Top-Center Live Safety Score HUD Pill
                        Positioned(
                          top: 14,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: CockpitColors.bg.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: liveScore >= 80
                                      ? CockpitColors.safeGreen
                                      : CockpitColors.warningAmber,
                                ),
                              ),
                              child: Text(
                                '${appState.t('liveScore')}: $liveScore%',
                                style: TextStyle(
                                  color: liveScore >= 80
                                      ? CockpitColors.safeGreen
                                      : CockpitColors.warningAmber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Top-Right Head Pose Pill
                        if (hasFace && !_isPipOverlayMode)
                          Positioned(
                            top: 14,
                            right: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: CockpitColors.bg.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: CockpitColors.cardBorder),
                              ),
                              child: Text(
                                'Pitch: ${_headPitch.toStringAsFixed(0)}° • Yaw: ${_headYaw.toStringAsFixed(0)}°',
                                style: const TextStyle(
                                  color: CockpitColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),

                        // Bottom Floating Telemetry: EAR + Left/Right Eye status + Yawns
                        if (!_isPipOverlayMode)
                          Positioned(
                            bottom: 14,
                            left: 14,
                            right: 14,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CockpitColors.bg
                                          .withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isEyesOpen
                                            ? CockpitColors.safeGreen
                                            : CockpitColors.dangerRed,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isEyesOpen
                                                ? CockpitColors.safeGreen
                                                : CockpitColors.dangerRed,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Flexible(
                                          child: Text(
                                            !hasFace
                                                ? appState.t('noFaceDetected')
                                                : 'EAR: ${_liveEar.toStringAsFixed(2)} (${isEyesOpen ? appState.t('eyeOpen') : appState.t('eyeClosed')})',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: !hasFace
                                                  ? CockpitColors.warningAmber
                                                  : (isEyesOpen
                                                      ? CockpitColors.safeGreen
                                                      : CockpitColors.dangerRed),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        CockpitColors.bg.withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: CockpitColors.cardBorder),
                                  ),
                                  child: Text(
                                    '${appState.t('yawns')}: ${appState.totalYawns} • ${appState.t('blinksLabel')}: ${appState.totalBlinks}',
                                    style: const TextStyle(
                                      color: CockpitColors.textWhite,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Bottom 1.5s Micro-Sleep Countdown Progress Bar
                        if (closureProgress > 0)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              value: closureProgress,
                              minHeight: 6,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                CockpitColors.dangerRed,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Real-Time Telemetry Bar (Fatigue Level, Eye Openness, Stop Trip Button)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CockpitColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          appState.t('tripInProgress'),
                          style: const TextStyle(
                            color: CockpitColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                        Text(
                          'MAR: ${_liveMar.toStringAsFixed(2)} • ${fatiguePct > 50 ? appState.t('warningStatus') : appState.t('optimalStatus')}',
                          style: TextStyle(
                            color: fatiguePct > 50
                                ? CockpitColors.warningAmber
                                : CockpitColors.safeGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _buildGaugeCard(
                            label: appState.t('fatigueLevel'),
                            valueText:
                                '${fatiguePct.toString().padLeft(2, '0')}%',
                            progress: fatiguePct / 100.0,
                            color: fatiguePct > 60
                                ? CockpitColors.dangerRed
                                : CockpitColors.safeGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildGaugeCard(
                            label: appState.t('eyeOpenness'),
                            valueText: '$eyeOpenPct%',
                            progress: avgEyeOpen,
                            color: isEyesOpen
                                ? CockpitColors.safeGreen
                                : CockpitColors.dangerRed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CockpitColors.dangerRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _stopTripAndNavigateToSummary,
                        icon: const Icon(Icons.stop_rounded, size: 22),
                        label: Text(
                          appState.t('stopTrip'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraHudView(bool isEyesOpen) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (_isCameraInitialized && _cameraController != null)
          CameraPreview(_cameraController!)
        else
          Container(
            color: const Color(0xFF090D12),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(
                  color: CockpitColors.safeGreen,
                ),
                if (_cameraErrorText != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _cameraErrorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CockpitColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        CustomPaint(
          painter: FaceMeshOverlayPainter(
            faces: _detectedFaces,
            webFaceData: _webFaceData,
            imageSize: _imageSize,
            rotation: _rotation,
            lensDirection: _lensDirection,
            isEyesOpen: isEyesOpen,
            isYawning: _liveMar > 0.48,
            liveEar: _liveEar,
          ),
        ),
      ],
    );
  }

  Widget _buildPipNavigationView(bool isEyesOpen) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(painter: MapNavigationBackgroundPainter()),
        Positioned(
          top: 52,
          left: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CockpitColors.card.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CockpitColors.cardBorder),
            ),
            child: const Row(
              children: <Widget>[
                Icon(
                  Icons.turn_right_rounded,
                  color: CockpitColors.safeGreen,
                  size: 28,
                ),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '250 m',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Dostyk Ave • 2GIS Navigation',
                      style: TextStyle(
                        color: CockpitColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 125,
          right: 14,
          width: 118,
          height: 152,
          child: Container(
            decoration: BoxDecoration(
              color: CockpitColors.bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isEyesOpen
                    ? CockpitColors.safeGreen
                    : CockpitColors.dangerRed,
                width: 2,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Colors.black54, blurRadius: 16),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildCameraHudView(isEyesOpen),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGaugeCard({
    required String label,
    required String valueText,
    required double progress,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CockpitColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CockpitColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: CockpitColors.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valueText,
            style: const TextStyle(
              color: CockpitColors.textWhite,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: CockpitColors.card,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
