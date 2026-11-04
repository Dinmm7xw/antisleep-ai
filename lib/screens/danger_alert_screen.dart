import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/siren_wav_generator.dart';
import '../services/web_face_bridge.dart';
import '../state/app_session_state.dart';
import '../widgets/painters/sound_wave_bars_painter.dart';

/// Screen 3: DangerAlertScreen (Full-screen Emergency Strobe Overlay)
/// Triggers continuous AudioPlayer / WebAudio siren + continuous heavy flutter_vibrate
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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..repeat(reverse: true);

    _startEmergencySirenAndVibration();
  }

  Future<void> _startEmergencySirenAndVibration() async {
    if (kIsWeb) {
      WebFaceBridge.startWebSiren();
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
      const Duration(milliseconds: 700),
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
            CockpitColors.dangerRed,
            const Color(0xFFB00020),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
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
                    Column(
                      children: <Widget>[
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              Transform.scale(
                                scale: 1.0 + (_pulseController.value * 0.28),
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 1.0 - _pulseController.value * 0.7,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.notifications_active_rounded,
                                  color: Colors.white,
                                  size: 46,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          appState.t('dangerTitle'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 28),
                        SizedBox(
                          width: 220,
                          height: 54,
                          child: CustomPaint(
                            painter: SoundWaveBarsPainter(
                              phase: _pulseController.value,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          appState.t('alarmMaxVol'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: <Widget>[
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: CockpitColors.dangerRed,
                              elevation: 10,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _dismissAlarm,
                            child: Text(
                              appState.t('dismissAlarm'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
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

