import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/cockpit_colors.dart';
import '../services/ai_voice_copilot_service.dart';

/// Pure Hands-Free Siri / Alice style Voice Assistant Capsule.
/// Activated automatically when the driver says «Антислип» (or «Antisleep»).
/// No clicking, no bulky chat modals — 100% natural verbal in-car conversation.
class AiCopilotOrbWidget extends StatefulWidget {
  const AiCopilotOrbWidget({super.key});

  @override
  State<AiCopilotOrbWidget> createState() => _AiCopilotOrbWidgetState();
}

class _AiCopilotOrbWidgetState extends State<AiCopilotOrbWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Automatically ensure continuous background hands-free listening is running
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
    _waveController.dispose();
    super.dispose();
  }

  void _handleManualWakeTap() {
    HapticFeedback.mediumImpact();
    // Tapping also wakes it up as an optional shortcut, but voice "Антислип" works 100% hands-free!
    aiCopilotService.handleUserSpeech('Антислип');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDialogueActive = aiCopilotService.isDialogueActive;
    final bool isSpeaking = aiCopilotService.isSpeaking;
    final bool hasInterim = aiCopilotService.interimSpeech.isNotEmpty;
    final String statusText = aiCopilotService.activeStatusText;
    final String lastAi = aiCopilotService.lastAiResponse;
    final String liveInterim = aiCopilotService.interimSpeech;

    final bool isExpanded = isDialogueActive || isSpeaking || hasInterim;

    return AnimatedBuilder(
      animation: _waveController,
      builder: (BuildContext context, _) {
        final double wave = _waveController.value;

        return GestureDetector(
          onTap: _handleManualWakeTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 16 : 12,
              vertical: isExpanded ? 10 : 8,
            ),
            constraints: BoxConstraints(
              maxWidth: isExpanded ? 340 : 180,
              minHeight: 44,
            ),
            decoration: BoxDecoration(
              color: isExpanded
                  ? const Color(0xFF0F172A).withValues(alpha: 0.94)
                  : const Color(0xFF1E293B).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isSpeaking
                    ? const Color(0xFF00F5D4)
                    : isExpanded
                        ? const Color(0xFF7209B7)
                        : CockpitColors.cardBorder,
                width: isExpanded ? 2.0 : 1.2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: isSpeaking
                      ? const Color(0xFF00F5D4).withValues(alpha: 0.35 + 0.2 * wave)
                      : isExpanded
                          ? const Color(0xFF7209B7).withValues(alpha: 0.4 + 0.2 * wave)
                          : Colors.black.withValues(alpha: 0.4),
                  blurRadius: isExpanded ? 16 : 8,
                  spreadRadius: isExpanded ? 2 : 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Glowing Animated Siri/Alice Hologram Sphere
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isSpeaking
                          ? const <Color>[Color(0xFF00F5D4), Color(0xFF00BBF9)]
                          : isExpanded
                              ? const <Color>[Color(0xFF7209B7), Color(0xFFF72585)]
                              : const <Color>[Color(0xFF334155), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: <BoxShadow>[
                      if (isExpanded)
                        BoxShadow(
                          color: isSpeaking
                              ? const Color(0xFF00F5D4)
                              : const Color(0xFFF72585),
                          blurRadius: 8 * wave,
                        ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isSpeaking
                          ? Icons.volume_up_rounded
                          : isExpanded
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Live Conversational Status & Speech Subtitle
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            statusText,
                            style: TextStyle(
                              color: isSpeaking
                                  ? const Color(0xFF00F5D4)
                                  : isExpanded
                                      ? const Color(0xFFF72585)
                                      : CockpitColors.textWhite,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (isExpanded) ...<Widget>[
                            const SizedBox(width: 6),
                            // Mini audio equalizer bars
                            _buildAudioEqualizer(wave, isSpeaking),
                          ],
                        ],
                      ),
                      if (hasInterim) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          liveInterim,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (isSpeaking && lastAi.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          lastAi,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioEqualizer(double wave, bool isSpeaking) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (int index) {
        final double height = 4.0 + (index == 1 ? 10.0 * wave : 7.0 * (1.0 - wave));
        return Container(
          width: 2.5,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 1.2),
          decoration: BoxDecoration(
            color: isSpeaking ? const Color(0xFF00F5D4) : const Color(0xFFF72585),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
