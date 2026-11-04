import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/cockpit_colors.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import '../widgets/cockpit_bottom_nav_bar.dart';
import '../widgets/painters/radial_safety_score_painter.dart';
import 'home_screen.dart';

/// Screen 4: SummaryScreen (Matches Figma Screen 5: Radial Score + 2x2 Grid + Save & Driving Tips)
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
    _autoSaveTrip();
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

    return Scaffold(
      appBar: const CockpitAppBar(),
      bottomNavigationBar: const CockpitBottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                appState.t('summaryTitle'),
                style: const TextStyle(
                  color: CockpitColors.textWhite,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
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
              const SizedBox(height: 10),

              // Drive Duration & Average EAR Badge
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: CockpitColors.safeGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: CockpitColors.safeGreen.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.timer_outlined,
                          color: CockpitColors.safeGreen,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatDuration(appState.driveDuration)} • ${appState.t('driveDuration').toUpperCase()}',
                          style: const TextStyle(
                            color: CockpitColors.safeGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isSaved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: CockpitColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: CockpitColors.cardBorder),
                      ),
                      child: Text(
                        'AVG EAR: ${appState.averageEar.toStringAsFixed(2)} • PERCLOS: ${appState.perclosPercent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: CockpitColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Animated Safety Score Card (0-100%)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CockpitColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CockpitColors.cardBorder),
                ),
                child: Row(
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: score / 100.0),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (BuildContext context, double val, _) {
                        return SizedBox(
                          width: 82,
                          height: 82,
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            appState.t('safetyScore'),
                            style: const TextStyle(
                              color: CockpitColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
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

              // 2x2 Statistics Grid
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.42,
                  physics: const NeverScrollableScrollPhysics(),
                  children: <Widget>[
                    _buildStatTile(
                      icon: Icons.schedule_rounded,
                      color: CockpitColors.safeGreen,
                      title: appState.t('driveDuration'),
                      value: _formatDuration(appState.driveDuration),
                    ),
                    _buildStatTile(
                      icon: Icons.notification_important_rounded,
                      color: CockpitColors.dangerRed,
                      title: appState.t('triggersCount'),
                      value: '${appState.microSleepEvents}',
                    ),
                    _buildStatTile(
                      icon: Icons.sentiment_neutral_rounded,
                      color: CockpitColors.warningAmber,
                      title: appState.t('yawns'),
                      value: '${appState.totalYawns}',
                    ),
                    _buildStatTile(
                      icon: Icons.remove_red_eye_outlined,
                      color: scoreColor,
                      title: appState.t('blinksLabel'),
                      value: '${appState.totalBlinks}',
                    ),
                  ],
                ),
              ),

              // Primary "New Trip" Button & Secondary "Driving Tips" Button (Matches Figma Screen 5)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CockpitColors.safeGreen,
                    foregroundColor: const Color(0xFF041E0F),
                    elevation: 6,
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
                  icon: const Icon(Icons.replay_rounded, size: 20),
                  label: Text(
                    appState.t('newTrip'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Text(
            value,
            style: const TextStyle(
              color: CockpitColors.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
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
