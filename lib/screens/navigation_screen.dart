import 'package:flutter/material.dart';

import 'monitoring_screen.dart';

/// Redirects any route/navigation screen entry directly to the full-screen Real Interactive Map + PiP Camera HUD.
class NavigationScreen extends StatelessWidget {
  final String? initialDestination;

  const NavigationScreen({
    super.key,
    this.initialDestination,
  });

  @override
  Widget build(BuildContext context) {
    return const MonitoringScreen(initialMapMode: true);
  }
}
