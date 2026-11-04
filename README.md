# AntiSleep AI — Driver Safety & Drowsiness Detection System

**AntiSleep AI** is a cross-platform mobile and web application built with **Flutter** (`Android`, `iOS`, `Web`) designed to prevent highway micro-sleep and driver fatigue in real time.

---

## ✨ Key Features

- **Trilingual Interface (`KK` / `RU` / `EN`)**: Instant reactive language switching in the top cockpit bar across all screens.
- **Real-Time Biometric Computer Vision**:
  - **Android & iOS**: Powered by `google_mlkit_face_detection` with custom `YUV_420_888 → NV21` and `BGRA8888` frame conversion.
  - **Web (Chrome / Edge)**: Powered by a 468-landmark **MediaPipe Face Mesh** bridge tracking live webcam `<video>` streams at 30 FPS.
- **Drowsiness & Fatigue Algorithms**:
  - **EAR (Eye Aspect Ratio)**: Continuous eye closure (`EAR < 0.22` / `eyeOpenProbability < 0.25`) for `> 1.5s` immediately triggers the fullscreen crimson emergency strobe and dual-tone `880Hz / 440Hz` siren.
  - **MAR (Mouth Aspect Ratio)**: Prolonged mouth opening (`MAR > 0.48` for `> 2.0s`) logs yawn events and alerts the driver.
  - **Head Pose (Pitch & Yaw)**: Detects forward head nodding (`Pitch < -15°`) and distraction.
  - **PERCLOS & Blink Counter**: Tracks natural blinks and calculates the percentage of eyelid closure over the trip.
- **4-Screen Automotive Cockpit Flow + 2GIS PiP Mode**:
  1. **HomeScreen**: Hardware & camera readiness diagnostics + sound/vibration check.
  2. **MonitoringScreen**: Live mirrored camera HUD, dynamic emerald green (`#00E676`) face mesh contour overlay, live telemetry gauges, and 2GIS Picture-in-Picture navigation overlay mode.
  3. **DangerAlertScreen**: Full-screen crimson strobe (`#FF1744`), animated sound-wave equalizer bars, continuous `880Hz / 440Hz` square-wave siren, and heavy haptic vibration.
  4. **SummaryScreen**: Animated radial Safety Score (`0–100%`), `2x2` telemetry breakdown, persistent trip history storage, and driver safety recommendations.

---

## 📂 Project Architecture

```text
lib/
├── main.dart                                      # Application entry point
├── core/
│   ├── localization/app_localizations.dart        # KK / RU / EN dictionary
│   └── theme/cockpit_colors.dart                  # Automotive dark cockpit theme (#0D1117 / #00E676 / #FF1744)
├── state/
│   └── app_session_state.dart                     # Session telemetry, PERCLOS, Safety Score & JSON persistence
├── services/
│   ├── mlkit_image_converter.dart                 # YUV420->NV21 converter & geometric EAR/MAR/HeadPose extractor
│   ├── siren_wav_generator.dart                   # In-memory 880Hz/440Hz PCM WAV synthesizer
│   ├── web_face_bridge.dart                       # Conditional Web/Native export
│   ├── web_face_bridge_stub.dart                  # Native stub (Android/iOS)
│   └── web_face_bridge_web.dart                   # Web JS interop bridge for MediaPipe 468-point mesh
├── screens/
│   ├── home_screen.dart                           # Screen 1: Pre-drive check & diagnostics
│   ├── monitoring_screen.dart                     # Screen 2: Live HUD & PiP navigation overlay
│   ├── danger_alert_screen.dart                   # Screen 3: Emergency wake-up alarm modal
│   └── summary_screen.dart                        # Screen 4: Trip analytics & safety score
└── widgets/
    ├── cockpit_app_bar.dart                       # Top bar with instant KK | RU | EN switcher
    └── painters/
        ├── dashboard_illustration_painter.dart    # Cockpit dashboard graphic
        ├── face_mesh_overlay_painter.dart         # Real-time face contours, eye/lip mesh & 2GIS map painter
        ├── radial_safety_score_painter.dart       # Circular safety score gauge
        └── sound_wave_bars_painter.dart           # Equalizer bars for emergency alarm
```

---

## 🚀 Getting Started

```bash
# 1. Install dependencies
flutter pub get

# 2. Run on Chrome / Edge (Web) or connected Android / iOS device
flutter run -d chrome
# or
flutter run

# 3. Build release Android APK
flutter build apk --release
```
