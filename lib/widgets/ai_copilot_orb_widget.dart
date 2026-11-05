import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ai_voice_copilot_service.dart';

/// Luxury Siri / Alice style AI Voice Hologram Orb.
/// Compact 46x46 circular sphere with neon audio aura and non-intrusive floating voice toast.
class AiCopilotOrbWidget extends StatefulWidget {
  const AiCopilotOrbWidget({super.key});

  @override
  State<AiCopilotOrbWidget> createState() => _AiCopilotOrbWidgetState();
}

class _AiCopilotOrbWidgetState extends State<AiCopilotOrbWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      aiCopilotService.ensureAutoListening();
    });

    aiCopilotService.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    aiCopilotService.removeListener(_onServiceUpdate);
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    aiCopilotService.handleUserSpeech('Антислип');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDialogueActive = aiCopilotService.isDialogueActive;
    final bool isSpeaking = aiCopilotService.isSpeaking;
    final bool hasInterim = aiCopilotService.interimSpeech.isNotEmpty;
    final String liveInterim = aiCopilotService.interimSpeech;
    final String lastAi = aiCopilotService.lastAiResponse;

    final bool showVoiceToast = (isDialogueActive || isSpeaking || hasInterim) &&
        (hasInterim || (isSpeaking && lastAi.isNotEmpty));

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (BuildContext context, _) {
        final double pulse = _pulseController.value;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Elegant Frosted Glass Voice Subtitle (appears only while speaking / listening)
            if (showVoiceToast)
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  constraints: const BoxConstraints(maxWidth: 220),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSpeaking
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.6)
                          : const Color(0xFF7209B7).withValues(alpha: 0.6),
                      width: 1.0,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildEqualizerMini(pulse, isSpeaking),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          hasInterim ? liveInterim : lastAi,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontStyle: hasInterim ? FontStyle.italic : FontStyle.normal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Ultra-Compact Siri / Alice Glowing Orb (46x46)
            GestureDetector(
              onTap: _handleTap,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // Pulsing Holographic Glow Ring
                  if (isDialogueActive || isSpeaking)
                    Container(
                      width: 48 + (6.0 * pulse),
                      height: 48 + (6.0 * pulse),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: isSpeaking
                                ? const Color(0xFF00F5D4).withValues(alpha: 0.5)
                                : const Color(0xFF7209B7).withValues(alpha: 0.55),
                            blurRadius: 12 + (6.0 * pulse),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),

                  // Metallic Obsidian Spherical Core
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isSpeaking
                            ? const <Color>[Color(0xFF00F5D4), Color(0xFF00BBF9)]
                            : isDialogueActive
                                ? const <Color>[Color(0xFF7209B7), Color(0xFFF72585)]
                                : const <Color>[Color(0xFF1E293B), Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: isSpeaking
                            ? const Color(0xFF00F5D4)
                            : isDialogueActive
                                ? const Color(0xFFF72585)
                                : Colors.white24,
                        width: 1.8,
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        isSpeaking
                            ? Icons.volume_up_rounded
                            : isDialogueActive
                                ? Icons.mic_rounded
                                : Icons.auto_awesome,
                        color: isSpeaking || isDialogueActive
                            ? Colors.white
                            : const Color(0xFF38BDF8),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEqualizerMini(double pulse, bool isSpeaking) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (int i) {
        final double h = 4.0 + (i == 1 ? 8.0 * pulse : 6.0 * (1.0 - pulse));
        return Container(
          width: 2,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isSpeaking ? const Color(0xFF00F5D4) : const Color(0xFFF72585),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
