import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/cockpit_colors.dart';
import '../screens/home_screen.dart';
import '../screens/monitoring_screen.dart';
import '../screens/summary_screen.dart';
import '../state/app_session_state.dart';

/// Shared Dark Cockpit Bottom Navigation Bar across all main screens:
/// 0: HomeScreen (Pre-Drive Check)
/// 1: MonitoringScreen (AI Face & Eye Camera HUD)
/// 2: MonitoringScreen in Live Map & Road Routing Mode (Yandex / OSRM + PiP Camera)
/// 3: SummaryScreen (Safety Score & Trip Statistics)
class CockpitBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTabSelected;

  const CockpitBottomNavBar({
    super.key,
    required this.currentIndex,
    this.onTabSelected,
  });

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    HapticFeedback.selectionClick();

    if (onTabSelected != null) {
      onTabSelected!(index);
      return;
    }

    Widget targetScreen;
    switch (index) {
      case 0:
        targetScreen = const HomeScreen();
        break;
      case 1:
        targetScreen = const MonitoringScreen(initialMapMode: false);
        break;
      case 2:
        targetScreen = const MonitoringScreen(initialMapMode: true);
        break;
      case 3:
      default:
        targetScreen = const SummaryScreen();
        break;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => targetScreen,
        transitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, Animation<double> anim, __, Widget child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CockpitColors.card,
        border: Border(
          top: BorderSide(color: CockpitColors.cardBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildNavItem(
                context: context,
                index: 0,
                icon: Icons.dashboard_rounded,
                label: appState.t('navHome'),
              ),
              _buildNavItem(
                context: context,
                index: 1,
                icon: Icons.videocam_rounded,
                label: appState.t('navMonitor'),
              ),
              _buildNavItem(
                context: context,
                index: 2,
                icon: Icons.map_rounded,
                label: appState.t('navMap'),
              ),
              _buildNavItem(
                context: context,
                index: 3,
                icon: Icons.analytics_rounded,
                label: appState.t('navSummary'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = currentIndex == index;
    final Color activeColor =
        index == 2 ? const Color(0xFFFFCC00) : CockpitColors.safeGreen;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _handleTap(context, index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 21,
                color: isSelected ? activeColor : CockpitColors.textMuted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? activeColor : CockpitColors.textMuted,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

