import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/mlkit_image_converter.dart';
import '../services/web_face_bridge.dart';
import '../services/kazakh_voice_audio.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import '../widgets/cockpit_bottom_nav_bar.dart';
import '../widgets/live_navigation_map_view.dart';
import '../widgets/painters/face_mesh_overlay_painter.dart';
import 'danger_alert_screen.dart';
import 'home_screen.dart';
import 'summary_screen.dart';

/// Screen 2: Active Monitoring HUD + Interactive Yandex GPS Map + Night Illumination + Background PiP Support.
class MonitoringScreen extends StatefulWidget {
  final bool initialMapMode;

  const MonitoringScreen({
    super.key,
    this.initialMapMode = false,
  });

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _bgChannel =
      MethodChannel('antisleep_ai/background');

  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessingFrame = false;
  bool _isCameraInitialized = false;
  bool _isAlarmRouteOpen = false;
  bool _isPipOverlayMode = false;
  bool _isBackgroundGuardEnabled = true;
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
  DateTime? _lastFaceDetectedAt;
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
    _isPipOverlayMode = widget.initialMapMode;
    _isNightScreenGlowActive = appState.isNightLightEnabled;
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      _initFaceDetector();
    } else {
      WebFaceBridge.startWebGps();
    }
    _initFrontCamera();
    _startTripClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isBackgroundGuardEnabled) {
      if (state == AppLifecycleState.resumed &&
          (_cameraController == null ||
              !_cameraController!.value.isInitialized)) {
        _initFrontCamera();
      }
      return;
    }

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

  Future<void> _triggerSystemPipWindow() async {
    HapticFeedback.mediumImpact();
    if (kIsWeb) {
      WebFaceBridge.toggleWebPictureInPicture();
      _showTemporaryBanner(appState.t('bgModeSub'));
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _bgChannel.invokeMethod<bool>('enterPip');
      } catch (_) {}
    }
  }

  Future<void> _toggleBackgroundGuard() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isBackgroundGuardEnabled = !_isBackgroundGuardEnabled;
    });
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _bgChannel.invokeMethod<bool>(
          'setAutoPip',
          <String, dynamic>{'enabled': _isBackgroundGuardEnabled},
        );
      } catch (_) {}
    }
    if (_isBackgroundGuardEnabled) {
      _showTemporaryBanner(appState.t('bgModeSub'));
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

  Future<void> _initFrontCamera({bool isRetry = false}) async {
    try {
      if (globalCameras.isEmpty) {
        globalCameras = await availableCameras();
      }

      if (globalCameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraErrorText = 'AI FaceMesh Active');
        }
        return;
      }

      final CameraDescription frontCamera = globalCameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => globalCameras.first,
      );
      _lensDirection = frontCamera.lensDirection;

      await _cameraController?.dispose();

      final CameraController controller = kIsWeb
          ? CameraController(
              frontCamera,
              ResolutionPreset.medium,
              enableAudio: false,
            )
          : CameraController(
              frontCamera,
              ResolutionPreset.medium,
              enableAudio: false,
              imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
                  ? ImageFormatGroup.yuv420
                  : ImageFormatGroup.bgra8888,
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
      if (kIsWeb) {
        try {
          WebFaceBridge.ensureWebcam();
        } catch (_) {}
      }
      if (!isRetry && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        if (mounted) {
          await _initFrontCamera(isRetry: true);
        }
        return;
      }
      if (mounted) {
        setState(() => _cameraErrorText = 'Камера занята другим приложением');
      }
    }
  }

  void _startTripClock() {
    _stopwatch.start();
    _tripClockTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      if (!mounted) return;
      appState.updateDuration(_stopwatch.elapsed);

      if (kIsWeb && !_isAlarmRouteOpen) {
        final WebFaceFrameData? data = WebFaceBridge.pollLatestWebFaceFrame();
        _webFaceData = data;
        if (data != null && data.faceFound) {
          _lastFaceDetectedAt = DateTime.now();
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
          final DateTime now = DateTime.now();
          if (_lastFaceDetectedAt == null ||
              now.difference(_lastFaceDetectedAt!).inMilliseconds > 1200) {
            _eyesClosedSince = null;
            _mouthOpenSince = null;
            _headDroopSince = null;
          }
          setState(() {});
          return;
        }
      }

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
        KazakhVoiceAudio.playYawnAlert();
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
        KazakhVoiceAudio.playHeadDroopAlert();
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
        titleOverride: _isPipOverlayMode
            ? appState.t('mapTabTitle')
            : appState.t('monitoringHeader'),
        trailingAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 1. Night Illumination toggle button
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: appState.t('nightLightBoost'),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isNightScreenGlowActive = !_isNightScreenGlowActive;
                });
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
                  size: 17,
                  color: _isNightScreenGlowActive
                      ? Colors.amber
                      : CockpitColors.textWhite,
                ),
              ),
            ),
            // 2. Pop-Out Floating PiP Window on top of other apps (2GIS, Yandex, Browser)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: appState.t('pipFloatBtn'),
              onPressed: _triggerSystemPipWindow,
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: CockpitColors.card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: const Icon(
                  Icons.picture_in_picture_alt_rounded,
                  size: 17,
                  color: CockpitColors.safeGreen,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CockpitBottomNavBar(
        currentIndex: _isPipOverlayMode ? 2 : 1,
        onTabSelected: (int index) {
          if (index == 1) {
            setState(() => _isPipOverlayMode = false);
          } else if (index == 2) {
            setState(() => _isPipOverlayMode = true);
          } else if (index == 0) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
            );
          } else if (index == 3) {
            _stopTripAndNavigateToSummary();
          }
        },
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _isPipOverlayMode ? 10 : 16,
            vertical: _isPipOverlayMode ? 6 : 8,
          ),
          child: Column(
            children: <Widget>[
              if (_activeWarningBannerText != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
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

              // Main Live Camera Viewport OR Full-Screen Interactive Map + Night Glow + PiP Overlay
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
                          LiveNavigationMapView(
                            pipCameraPreview: _buildCameraHudView(isEyesOpen),
                            isEyesOpen: isEyesOpen,
                            onTriggerSystemPip: _triggerSystemPipWindow,
                          )
                        else
                          _buildCameraHudView(isEyesOpen),

                        // Top Status Row (shown on Camera AI tab so it never overlaps the Map's route header)
                        if (!_isPipOverlayMode)
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 12,
                            child: Row(
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        CockpitColors.bg.withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: CockpitColors.cardBorder),
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
                                      const SizedBox(width: 5),
                                      Text(
                                        'LIVE • ${_formatDuration(appState.driveDuration)}',
                                        style: const TextStyle(
                                          color: CockpitColors.textWhite,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Live Safety Score Pill
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CockpitColors.bg
                                          .withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: liveScore >= 80
                                            ? CockpitColors.safeGreen
                                            : CockpitColors.warningAmber,
                                      ),
                                    ),
                                    child: Text(
                                      '${appState.t('liveScore')}: $liveScore%',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: liveScore >= 80
                                            ? CockpitColors.safeGreen
                                            : CockpitColors.warningAmber,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Background Guard Active Toggle Pill
                                Flexible(
                                  child: GestureDetector(
                                    onTap: _toggleBackgroundGuard,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _isBackgroundGuardEnabled
                                            ? CockpitColors.safeGreen
                                                .withValues(alpha: 0.18)
                                            : CockpitColors.bg
                                                .withValues(alpha: 0.84),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _isBackgroundGuardEnabled
                                              ? CockpitColors.safeGreen
                                              : CockpitColors.cardBorder,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(
                                            Icons.shield_rounded,
                                            size: 12,
                                            color: _isBackgroundGuardEnabled
                                                ? CockpitColors.safeGreen
                                                : CockpitColors.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              appState.t('bgModeLabel'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: _isBackgroundGuardEnabled
                                                    ? CockpitColors.safeGreen
                                                    : CockpitColors.textMuted,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Bottom Floating EAR Pill + Yawns & Blinks Counter
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

              // Real-Time Telemetry Bar (shown on Camera AI tab; hidden on Map tab so Map is 100% full-screen)
              if (!_isPipOverlayMode) ...<Widget>[
                const SizedBox(height: 12),
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
                          Flexible(
                            child: Text(
                              appState.t('tripInProgress'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CockpitColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'MAR: ${_liveMar.toStringAsFixed(2)} • Pitch: ${_headPitch.toStringAsFixed(0)}° • Yaw: ${_headYaw.toStringAsFixed(0)}°',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fatiguePct > 50
                                    ? CockpitColors.warningAmber
                                    : CockpitColors.safeGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
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
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.face_retouching_natural_rounded,
                    color: isEyesOpen
                        ? CockpitColors.safeGreen
                        : CockpitColors.dangerRed,
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cameraErrorText ?? 'EAR: ${_liveEar.toStringAsFixed(2)}',
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
