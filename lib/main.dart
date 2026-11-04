import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/cockpit_colors.dart';
import 'screens/home_screen.dart';
import 'state/app_session_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: CockpitColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    globalCameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera initialization warning: $e');
  }

  runApp(const AntiSleepAIApp());
}

class AntiSleepAIApp extends StatelessWidget {
  const AntiSleepAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: 'AntiSleep AI',
          debugShowCheckedModeBanner: false,
          theme: CockpitColors.darkTheme,
          home: const HomeScreen(),
        );
      },
    );
  }
}
