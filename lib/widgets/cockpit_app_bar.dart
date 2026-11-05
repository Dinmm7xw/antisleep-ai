import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/cockpit_colors.dart';
import '../state/app_session_state.dart';

/// Shared Top AppBar with Brand Logo & Instant Language Switcher (KK | RU | EN)
class CockpitAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? titleOverride;
  final Widget? trailingAction;

  const CockpitAppBar({
    super.key,
    this.titleOverride,
    this.trailingAction,
  });

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: CockpitColors.bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: CockpitColors.safeGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: CockpitColors.safeGreen.withValues(alpha: 0.45),
              ),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: CockpitColors.safeGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  titleOverride ?? appState.t('appTitle'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CockpitColors.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (appState.currentDriver != null)
                  Text(
                    '${appState.currentDriver!.name} • ${appState.currentDriver!.carPlate}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CockpitColors.safeGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        if (trailingAction != null) trailingAction!,
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: CockpitColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CockpitColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <String>['kk', 'ru', 'en'].map((String code) {
                  final bool selected = appState.lang == code;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      appState.setLanguage(code);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? CockpitColors.safeGreen
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        code.toUpperCase(),
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF041E0F)
                              : CockpitColors.textMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

