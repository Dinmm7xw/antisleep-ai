import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/cockpit_colors.dart';
import '../services/ai_voice_copilot_service.dart';
import '../state/app_session_state.dart';

/// Floating Futuristic Siri / Alice style AI Voice Co-Pilot Orb Widget.
/// Placed over the live monitoring screen for hands-free and 1-tap verbal interaction.
class AiCopilotOrbWidget extends StatefulWidget {
  final VoidCallback? onExpanded;

  const AiCopilotOrbWidget({
    super.key,
    this.onExpanded,
  });

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

    aiCopilotService.addListener(_onCopilotUpdate);
  }

  void _onCopilotUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    aiCopilotService.removeListener(_onCopilotUpdate);
    _pulseController.dispose();
    super.dispose();
  }

  void _openCopilotPanel() {
    HapticFeedback.mediumImpact();
    widget.onExpanded?.call();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return _AiCopilotHudSheet(
          onClose: () => Navigator.of(ctx).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isListening = aiCopilotService.isListening;
    final bool isSpeaking = aiCopilotService.isSpeaking;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (BuildContext ctx, Widget? child) {
        final double pulse = _pulseController.value;
        final double scale = isListening || isSpeaking
            ? 1.0 + (pulse * 0.18)
            : 1.0 + (pulse * 0.06);

        return GestureDetector(
          onTap: _openCopilotPanel,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Outer Glowing Aura Rings
              if (isListening || isSpeaking)
                Container(
                  width: 66 * scale,
                  height: 66 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: isSpeaking
                            ? const Color(0xFF00FFCC).withValues(alpha: 0.45)
                            : const Color(0xFF7B2CBF).withValues(alpha: 0.55),
                        blurRadius: 18,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),

              // Main High-Tech Hologram Sphere
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isSpeaking
                        ? const <Color>[Color(0xFF00F5D4), Color(0xFF00BBF9)]
                        : isListening
                            ? const <Color>[Color(0xFF7209B7), Color(0xFFF72585)]
                            : const <Color>[Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: isSpeaking
                        ? const Color(0xFF00F5D4)
                        : isListening
                            ? const Color(0xFFF72585)
                            : CockpitColors.cardBorder,
                    width: 2.0,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: isListening
                          ? const Color(0xFFF72585).withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: isSpeaking
                      ? const Icon(
                          Icons.volume_up_rounded,
                          color: Colors.black,
                          size: 26,
                        )
                      : isListening
                          ? const Icon(
                              Icons.mic_rounded,
                              color: Colors.white,
                              size: 26,
                            )
                          : const Icon(
                              Icons.smart_toy_rounded,
                              color: CockpitColors.safeGreen,
                              size: 26,
                            ),
                ),
              ),

              // Mini Micro-Indicator Badge
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isListening
                        ? const Color(0xFF00FF66)
                        : CockpitColors.cardBorder,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Cockpit Floating Voice HUD Modal
class _AiCopilotHudSheet extends StatefulWidget {
  final VoidCallback onClose;

  const _AiCopilotHudSheet({required this.onClose});

  @override
  State<_AiCopilotHudSheet> createState() => _AiCopilotHudSheetState();
}

class _AiCopilotHudSheetState extends State<_AiCopilotHudSheet> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    aiCopilotService.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    aiCopilotService.removeListener(_onServiceUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  String _getVoiceModelName(String lang) {
    switch (lang) {
      case 'ru':
        return '🇷🇺 Svetlana Neural (Studio)';
      case 'en':
        return '🇬🇧 Emma Neural (Studio)';
      default:
        return '🇰🇿 Daulet Neural (Studio)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentLang = appState.lang;
    final bool isListening = aiCopilotService.isListening;
    final List<AiVoiceMessage> messages = aiCopilotService.messages;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isListening
              ? const Color(0xFFF72585)
              : CockpitColors.cardBorder,
          width: 1.5,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black87,
            blurRadius: 30,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[Color(0xFF7209B7), Color(0xFF4CC9F0)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Text(
                            'AntiSleep AI Voice Co-Pilot',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: CockpitColors.safeGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'LIVE',
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
                        _getVoiceModelName(currentLang),
                        style: const TextStyle(
                          color: CockpitColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          const Divider(color: CockpitColors.cardBorder, height: 1),

          // Message Stream Area
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.record_voice_over_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          currentLang == 'ru'
                              ? 'Скажите что-нибудь или выберите тему ниже'
                              : currentLang == 'en'
                                  ? 'Say something or pick an action below'
                                  : 'Сөйлеңіз немесе төмендегі тақырыпты таңдаңыз',
                          style: const TextStyle(
                            color: CockpitColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (BuildContext ctx, int i) {
                      final AiVoiceMessage m = messages[i];
                      return _buildMessageBubble(m);
                    },
                  ),
          ),

          // Quick Voice Action Chips
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  _buildQuickChip(
                    icon: Icons.location_city_rounded,
                    label: currentLang == 'ru'
                        ? '🎮 Города'
                        : currentLang == 'en'
                            ? '🎮 Cities'
                            : '🎮 Қалалар',
                    color: const Color(0xFF00BBF9),
                    onTap: () => aiCopilotService.triggerQuickAction(
                      QuickCopilotAction.citiesGame,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildQuickChip(
                    icon: Icons.calculate_rounded,
                    label: currentLang == 'ru'
                        ? '🧮 Пример 8×12'
                        : currentLang == 'en'
                            ? '🧮 Math 8×12'
                            : '🧮 Есеп 8×12',
                    color: const Color(0xFFF72585),
                    onTap: () => aiCopilotService.triggerQuickAction(
                      QuickCopilotAction.mathPuzzle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildQuickChip(
                    icon: Icons.help_outline_rounded,
                    label: currentLang == 'ru'
                        ? '❓ Викторина'
                        : currentLang == 'en'
                            ? '❓ Trivia Quiz'
                            : '❓ Викторина',
                    color: const Color(0xFF7209B7),
                    onTap: () => aiCopilotService.triggerQuickAction(
                      QuickCopilotAction.triviaQuiz,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildQuickChip(
                    icon: Icons.sentiment_very_satisfied_rounded,
                    label: currentLang == 'ru'
                        ? '😄 Анекдот'
                        : currentLang == 'en'
                            ? '😄 Joke'
                            : '😄 Әзіл айтшы',
                    color: const Color(0xFFFFB703),
                    onTap: () => aiCopilotService.triggerQuickAction(
                      QuickCopilotAction.funnyJoke,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildQuickChip(
                    icon: Icons.coffee_rounded,
                    label: currentLang == 'ru'
                        ? '☕ Устал'
                        : currentLang == 'en'
                            ? '☕ Drowsy'
                            : '☕ Шаршадым',
                    color: const Color(0xFFFB8500),
                    onTap: () => aiCopilotService.triggerQuickAction(
                      QuickCopilotAction.fatigueAdvice,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Microphone Controller
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isListening
                          ? const Color(0xFFF72585)
                          : CockpitColors.card,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isListening
                              ? Colors.white
                              : CockpitColors.cardBorder,
                        ),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      aiCopilotService.toggleListening();
                    },
                    icon: Icon(
                      isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: isListening ? Colors.white : CockpitColors.safeGreen,
                    ),
                    label: Text(
                      isListening
                          ? (currentLang == 'ru'
                              ? 'Тыңдауды тоқтату'
                              : currentLang == 'en'
                                  ? 'Stop Listening'
                                  : 'Тыңдауды тоқтату')
                          : (currentLang == 'ru'
                              ? 'Микрофонды қосу'
                              : currentLang == 'en'
                                  ? 'Start Listening'
                                  : 'Микрофонды қосу'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AiVoiceMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: msg.isUser
              ? const Color(0xFF2563EB)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
          border: Border.all(
            color: msg.isUser
                ? const Color(0xFF3B82F6)
                : CockpitColors.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  msg.isUser ? Icons.person_rounded : Icons.smart_toy_rounded,
                  size: 13,
                  color: msg.isUser ? Colors.white70 : CockpitColors.safeGreen,
                ),
                const SizedBox(width: 4),
                Text(
                  msg.isUser ? 'Сіз' : 'AntiSleep Co-Pilot',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: msg.isUser ? Colors.white70 : CockpitColors.safeGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              msg.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 15, color: color),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.16),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}
