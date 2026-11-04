import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/cockpit_colors.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import '../widgets/cockpit_bottom_nav_bar.dart';
import '../widgets/painters/radial_safety_score_painter.dart';
import 'home_screen.dart';

/// Screen 4: SummaryScreen (Automotive Safety Analytics & Driver Performance)
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _autoSaveTrip();
      }
    });
  }

  Future<void> _autoSaveTrip() async {
    await appState.saveCurrentTripToDisk();
    if (mounted) {
      setState(() => _isSaved = true);
    }
  }

  String _formatDuration(Duration d) {
    final String h = d.inHours.toString().padLeft(2, '0');
    final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _showDrivingTipsModal() {
    HapticFeedback.selectionClick();
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
                  children: <Widget>[
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: CockpitColors.safeGreen,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appState.t('tipsTitle'),
                        style: const TextStyle(
                          color: CockpitColors.textWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  appState.t('tip1'),
                  style: const TextStyle(
                    color: CockpitColors.textWhite,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  appState.t('tip2'),
                  style: const TextStyle(
                    color: CockpitColors.textWhite,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  appState.t('tip3'),
                  style: const TextStyle(
                    color: CockpitColors.textWhite,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  appState.t('tip4'),
                  style: const TextStyle(
                    color: CockpitColors.textWhite,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int score = appState.calculatedSafetyScore;
    final String scoreRating = score >= 80
        ? appState.t('veryGood')
        : (score >= 55 ? appState.t('moderate') : appState.t('lowScore'));
    final Color scoreColor = score >= 80
        ? CockpitColors.safeGreen
        : (score >= 55 ? CockpitColors.warningAmber : CockpitColors.dangerRed);

    final String badgeText = score >= 85
        ? appState.t('badgeAlertDriver')
        : (score >= 60
            ? appState.t('badgeCautiousDriver')
            : appState.t('badgeFatiguedDriver'));

    return Scaffold(
      appBar: const CockpitAppBar(),
      bottomNavigationBar: const CockpitBottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                appState.t('summaryTitle'),
                style: const TextStyle(
                  color: CockpitColors.textWhite,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                appState.t('summarySub'),
                style: const TextStyle(
                  color: CockpitColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),

              // Driver Performance Badge Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scoreColor.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      score >= 80 ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                      color: scoreColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (_isSaved) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: CockpitColors.safeGreen,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Animated Radial Safety Score Card (0-100%)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFF161E28),
                      Color(0xFF121720),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CockpitColors.cardBorder),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: scoreColor.withValues(alpha: 0.12),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: score / 100.0),
                      duration: const Duration(milliseconds: 950),
                      curve: Curves.easeOutCubic,
                      builder: (BuildContext context, double val, _) {
                        return SizedBox(
                          width: 86,
                          height: 86,
                          child: CustomPaint(
                            painter: RadialSafetyScorePainter(
                              progress: val,
                              color: scoreColor,
                            ),
                            child: Center(
                              child: Text(
                                '${(val * 100).round()}%',
                                style: const TextStyle(
                                  color: CockpitColors.textWhite,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            appState.t('safetyScore'),
                            style: const TextStyle(
                              color: CockpitColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            scoreRating,
                            style: TextStyle(
                              color: scoreColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: score / 100.0,
                              minHeight: 6,
                              backgroundColor: CockpitColors.bg,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(scoreColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2x2 Telemetry Grid
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildStatTile(
                      icon: Icons.timer_outlined,
                      color: CockpitColors.safeGreen,
                      title: appState.t('driveDuration'),
                      value: _formatDuration(appState.driveDuration),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatTile(
                      icon: Icons.notification_important_rounded,
                      color: appState.microSleepEvents > 0
                          ? CockpitColors.dangerRed
                          : CockpitColors.safeGreen,
                      title: appState.t('triggersCount'),
                      value: '${appState.microSleepEvents}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildStatTile(
                      icon: Icons.sentiment_neutral_rounded,
                      color: appState.totalYawns > 2
                          ? CockpitColors.warningAmber
                          : CockpitColors.safeGreen,
                      title: appState.t('yawns'),
                      value: '${appState.totalYawns}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatTile(
                      icon: Icons.visibility_outlined,
                      color: const Color(0xFF00B0FF),
                      title: 'PERCLOS',
                      value: '${appState.perclosPercent.toStringAsFixed(1)}%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Primary "New Trip" Button & Secondary "Driving Tips" Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: <Color>[
                        Color(0xFF00E676),
                        Color(0xFF00C853),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: const Color(0xFF041E0F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      appState.resetTrip();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const HomeScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.replay_rounded, size: 22),
                    label: Text(
                      appState.t('newTrip'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CockpitColors.textWhite,
                    side: const BorderSide(color: CockpitColors.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _showDrivingTipsModal,
                  icon: const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: CockpitColors.safeGreen,
                    size: 18,
                  ),
                  label: Text(
                    appState.t('drivingTipsBtn'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CockpitColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CockpitColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: CockpitColors.textWhite,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CockpitColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
