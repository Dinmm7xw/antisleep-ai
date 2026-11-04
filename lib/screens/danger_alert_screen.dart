import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/siren_wav_generator.dart';
import '../services/web_face_bridge.dart';
import '../services/kazakh_voice_audio.dart';
import '../state/app_session_state.dart';
import '../widgets/painters/sound_wave_bars_painter.dart';

/// Screen 3: DangerAlertScreen (Full-screen Emergency Strobe Overlay + Slide to Dismiss)
class DangerAlertScreen extends StatefulWidget {
  const DangerAlertScreen({super.key});

  @override
  State<DangerAlertScreen> createState() => _DangerAlertScreenState();
}

class _DangerAlertScreenState extends State<DangerAlertScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _vibrationTimer;
  bool _canVibrateDevice = false;

  // Slide to Dismiss State
  double _sliderProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..repeat(reverse: true);

    _startEmergencySirenAndVibration();
  }

  Future<void> _startEmergencySirenAndVibration() async {
    if (kIsWeb) {
      WebFaceBridge.startWebSiren();
      KazakhVoiceAudio.playDrowsinessAlert();
    } else {
      try {
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.setVolume(1.0);
        final Uint8List wavBytes = SirenWavGenerator.generateDualToneSirenWav();
        await _audioPlayer.play(BytesSource(wavBytes));
      } catch (e) {
        debugPrint('AudioPlayer error: $e');
      }

      try {
        _canVibrateDevice = await Vibrate.canVibrate;
      } catch (_) {
        _canVibrateDevice = false;
      }
    }

    _triggerVibrationPulse();
    _vibrationTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _triggerVibrationPulse(),
    );
  }

  void _triggerVibrationPulse() {
    if (!kIsWeb && _canVibrateDevice) {
      Vibrate.vibrate();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _dismissAlarm() async {
    _vibrationTimer?.cancel();
    if (kIsWeb) {
      WebFaceBridge.stopWebSiren();
      WebFaceBridge.stopKazakhVoice();
      KazakhVoiceAudio.playAwakeConfirmed();
    } else {
      try {
        await _audioPlayer.stop();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _vibrationTimer?.cancel();
    if (kIsWeb) {
      WebFaceBridge.stopWebSiren();
      WebFaceBridge.stopKazakhVoice();
    }
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (BuildContext context, _) {
          final Color bgColor = Color.lerp(
            const Color(0xFFFF0D36),
            const Color(0xFF7A0014),
            _pulseController.value,
          )!;

          return Scaffold(
            backgroundColor: bgColor,
            body: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // Top Warning Strip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            appState.t('criticalFatigue'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center Emergency Siren Pulsation & Text
                    Column(
                      children: <Widget>[
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              Transform.scale(
                                scale: 1.0 + (_pulseController.value * 0.35),
                                child: Container(
                                  width: 130,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha:
                                            1.0 - _pulseController.value * 0.7,
                                      ),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.4 * _pulseController.value,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.notifications_active_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          appState.t('dangerTitle'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appState.t('dangerSub'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 240,
                          height: 52,
                          child: CustomPaint(
                            painter: SoundWaveBarsPainter(
                              phase: _pulseController.value,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appState.t('alarmMaxVol'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),

                    // Bottom: Slide To Dismiss Track (Requires deliberate driver action)
                    Column(
                      children: <Widget>[
                        LayoutBuilder(
                          builder:
                              (BuildContext context, BoxConstraints constraints) {
                            final double trackWidth = constraints.maxWidth;
                            const double thumbSize = 54;
                            final double maxDrag = trackWidth - thumbSize - 8;

                            return Container(
                              height: 62,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  width: 2,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.centerLeft,
                                children: <Widget>[
                                  Center(
                                    child: Text(
                                      appState.t('swipeToDismiss'),
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: _sliderProgress * maxDrag,
                                    child: GestureDetector(
                                      onHorizontalDragUpdate:
                                          (DragUpdateDetails details) {
                                        setState(() {
                                          final double next = _sliderProgress +
                                              (details.primaryDelta ?? 0) /
                                                  maxDrag;
                                          _sliderProgress = next.clamp(0.0, 1.0);
                                        });
                                      },
                                      onHorizontalDragEnd: (_) {
                                        if (_sliderProgress >= 0.82) {
                                          HapticFeedback.heavyImpact();
                                          _dismissAlarm();
                                        } else {
                                          setState(() => _sliderProgress = 0.0);
                                        }
                                      },
                                      child: Container(
                                        width: thumbSize,
                                        height: thumbSize,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: <BoxShadow>[
                                            BoxShadow(
                                              color: Colors.black38,
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.arrow_forward_rounded,
                                          color: CockpitColors.dangerRed,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        // Quick fallback button
                        TextButton(
                          onPressed: _dismissAlarm,
                          child: Text(
                            appState.t('dismissAlarm'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Text(
                          appState.t('restAdvice'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
