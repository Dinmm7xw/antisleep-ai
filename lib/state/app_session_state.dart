import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../core/localization/app_localizations.dart';
import '../models/driver_profile.dart';
import '../services/supabase_service.dart';
import '../services/web_face_bridge.dart';

/// Global list of available device cameras initialized at startup.
List<CameraDescription> globalCameras = <CameraDescription>[];

/// Sensitivity profiles for driver fatigue detection
enum SensitivityMode {
  city,
  highway,
  strict,
}

/// Immutable model representing a completed and saved driving session.
class TripRecord {
  final DateTime timestamp;
  final int durationSeconds;
  final int safetyScore;
  final int microSleepTriggers;
  final int yawnsDetected;
  final int totalBlinks;
  final double averageEar;
  final double perclosPercent;

  const TripRecord({
    required this.timestamp,
    required this.durationSeconds,
    required this.safetyScore,
    required this.microSleepTriggers,
    required this.yawnsDetected,
    required this.totalBlinks,
    required this.averageEar,
    required this.perclosPercent,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'durationSeconds': durationSeconds,
        'safetyScore': safetyScore,
        'microSleepTriggers': microSleepTriggers,
        'yawnsDetected': yawnsDetected,
        'totalBlinks': totalBlinks,
        'averageEar': averageEar,
        'perclosPercent': perclosPercent,
      };

  factory TripRecord.fromJson(Map<String, dynamic> json) {
    return TripRecord(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      safetyScore: (json['safetyScore'] as num?)?.toInt() ?? 100,
      microSleepTriggers: (json['microSleepTriggers'] as num?)?.toInt() ?? 0,
      yawnsDetected: (json['yawnsDetected'] as num?)?.toInt() ?? 0,
      totalBlinks: (json['totalBlinks'] as num?)?.toInt() ?? 0,
      averageEar: (json['averageEar'] as num?)?.toDouble() ?? 0.30,
      perclosPercent: (json['perclosPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Global Application State Controller (Language + Real-Time Session Telemetry + Persistent History)
class AppSessionState extends ChangeNotifier {
  String _lang = 'kk'; // Default language: 'kk'
  Duration driveDuration = Duration.zero;
  int microSleepEvents = 0;
  int totalYawns = 0;
  int totalBlinks = 0;
  int headNodEvents = 0;

  // Real-time statistical accumulators for PERCLOS and Average EAR
  int _totalFramesAnalyzed = 0;
  int _closedEyeFrames = 0;
  double _earSum = 0.0;

  // Hardware readiness states probed dynamically on HomeScreen
  bool isCameraReady = false;
  bool isSensorReady = true;
  bool isHapticsSupported = false;
  String activeCameraName = '';

  // Advanced Cockpit Settings
  SensitivityMode sensitivityMode = SensitivityMode.highway;
  bool isNightLightEnabled = false;
  double personalEarOffset = 0.0;

  // Saved trip history loaded/persisted on device
  final List<TripRecord> savedTrips = <TripRecord>[];

  // Authenticated Driver Profile State
  DriverProfile? currentDriver;
  bool get isAuthenticated => currentDriver != null;

  String get lang => _lang;

  double get averageEar =>
      _totalFramesAnalyzed > 0 ? (_earSum / _totalFramesAnalyzed) : 0.31;

  /// Effective EAR threshold taking into account sensitivity mode and personal calibration
  /// Effective EAR threshold taking into account sensitivity mode and personal calibration.
  /// Calibrated specifically for Asian / Central Asian almond eye shapes:
  /// Natural open eye EAR: 0.17 - 0.24, True closed eye EAR: 0.08 - 0.13.
  double get effectiveEarThreshold {
    double base;
    switch (sensitivityMode) {
      case SensitivityMode.city:
        base = 0.145; // City / Gentle Mode (triggers only on true deep eye closure < 0.145)
        break;
      case SensitivityMode.highway:
        base = 0.155; // Highway Standard Mode (safely below 0.19, triggers on real closure < 0.155)
        break;
      case SensitivityMode.strict:
        base = 0.170; // Strict Alert Mode (< 0.170)
        break;
    }
    return (base + personalEarOffset).clamp(0.12, 0.24);
  }

  /// PERCLOS: Percentage of time eyes were closed over the trip
  double get perclosPercent => _totalFramesAnalyzed > 0
      ? ((_closedEyeFrames / _totalFramesAnalyzed) * 100.0).clamp(0.0, 100.0)
      : 0.0;

  void setLanguage(String newLang) {
    if (_lang != newLang &&
        (newLang == 'kk' || newLang == 'ru' || newLang == 'en')) {
      _lang = newLang;
      notifyListeners();
    }
  }

  void setSensitivity(SensitivityMode mode) {
    sensitivityMode = mode;
    notifyListeners();
  }

  void setSensitivityMode(SensitivityMode mode) => setSensitivity(mode);

  void toggleNightLight() {
    isNightLightEnabled = !isNightLightEnabled;
    notifyListeners();
  }

  void setPersonalEarOffset(double offset) {
    personalEarOffset = offset;
    notifyListeners();
  }

  String t(String key) => AppLocalizations.tr(_lang, key);

  int get calculatedSafetyScore {
    final int alertPenalty = microSleepEvents * 22;
    final int yawnPenalty = totalYawns * 5;
    final int nodPenalty = headNodEvents * 6;
    final int perclosPenalty = (perclosPercent * 0.8).round();
    return (100 - alertPenalty - yawnPenalty - nodPenalty - perclosPenalty)
        .clamp(0, 100);
  }

  void recordBiometricFrame({
    required double ear,
    required bool eyesClosed,
  }) {
    _totalFramesAnalyzed++;
    _earSum += ear;
    if (eyesClosed) {
      _closedEyeFrames++;
    }
  }

  void resetTrip() {
    driveDuration = Duration.zero;
    microSleepEvents = 0;
    totalYawns = 0;
    totalBlinks = 0;
    headNodEvents = 0;
    _totalFramesAnalyzed = 0;
    _closedEyeFrames = 0;
    _earSum = 0.0;
    notifyListeners();
  }

  void incrementDangerTrigger() {
    microSleepEvents++;
    notifyListeners();
  }

  void incrementYawn() {
    totalYawns++;
    notifyListeners();
  }

  void incrementBlink() {
    totalBlinks++;
    notifyListeners();
  }

  void incrementHeadNod() {
    headNodEvents++;
    notifyListeners();
  }

  void updateDuration(Duration d) {
    driveDuration = d;
    notifyListeners();
  }

  void updateHardwareStatus({
    required bool cameraReady,
    required bool sensorReady,
    required bool hapticsReady,
    required String cameraName,
  }) {
    isCameraReady = cameraReady;
    isSensorReady = sensorReady;
    isHapticsSupported = hapticsReady;
    activeCameraName = cameraName;
    notifyListeners();
  }

  /// Persists the current completed trip to local storage
  Future<TripRecord> saveCurrentTripToDisk() async {
    final TripRecord record = TripRecord(
      timestamp: DateTime.now(),
      durationSeconds: driveDuration.inSeconds,
      safetyScore: calculatedSafetyScore,
      microSleepTriggers: microSleepEvents,
      yawnsDetected: totalYawns,
      totalBlinks: totalBlinks,
      averageEar: averageEar,
      perclosPercent: perclosPercent,
    );

    savedTrips.insert(0, record);
    notifyListeners();

    // Sync to Supabase Cloud PostgreSQL asynchronously
    SupabaseService.syncTripRecord(
      record,
      driverIdentifier: currentDriver?.emailOrPhone ?? 'guest',
    );

    if (!kIsWeb) {
      try {
        final File file =
            File('${Directory.systemTemp.path}/antisleep_trips.json');
        final List<Map<String, dynamic>> serialized =
            savedTrips.map((TripRecord r) => r.toJson()).toList();
        await file.writeAsString(jsonEncode(serialized));
      } catch (e) {
        debugPrint('Failed to write trip history: $e');
      }
    }

    return record;
  }

  /// Loads previously saved trips from local disk
  Future<void> loadSavedTripsFromDisk() async {
    if (kIsWeb) return;
    try {
      final File file =
          File('${Directory.systemTemp.path}/antisleep_trips.json');
      if (await file.exists()) {
        final String content = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
        savedTrips
          ..clear()
          ..addAll(
            decoded.map(
              (dynamic item) =>
                  TripRecord.fromJson(item as Map<String, dynamic>),
            ),
          );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load trip history: $e');
    }
  }

  /// Loads stored driver profile from localStorage (Web) or filesystem (Mobile)
  Future<void> loadDriverProfileFromDisk() async {
    try {
      if (kIsWeb) {
        final String raw = WebFaceBridge.loadDriverProfile();
        if (raw.isNotEmpty) {
          final DriverProfile? profile = DriverProfile.fromJsonString(raw);
          if (profile != null) {
            currentDriver = profile;
            _lang = profile.language;
            notifyListeners();
          }
        }
      } else {
        final File file =
            File('${Directory.systemTemp.path}/antisleep_driver.json');
        if (await file.exists()) {
          final String raw = await file.readAsString();
          final DriverProfile? profile = DriverProfile.fromJsonString(raw);
          if (profile != null) {
            currentDriver = profile;
            _lang = profile.language;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading driver profile: $e');
    }
  }

  /// Persists driver profile
  Future<void> saveDriverProfileToDisk(DriverProfile profile) async {
    currentDriver = profile;
    _lang = profile.language;
    notifyListeners();

    // Sync to Supabase Cloud PostgreSQL asynchronously
    SupabaseService.syncDriverProfile(profile);

    try {
      final String jsonStr = profile.toJsonString();
      if (kIsWeb) {
        WebFaceBridge.saveDriverProfile(jsonStr);
      } else {
        final File file =
            File('${Directory.systemTemp.path}/antisleep_driver.json');
        await file.writeAsString(jsonStr);
      }
    } catch (e) {
      debugPrint('Error saving driver profile: $e');
    }
  }

  /// One-click Demo/Guest Login for fast testing & project defense
  Future<void> loginAsGuest() async {
    final DriverProfile guest = DriverProfile(
      name: _lang == 'kk'
          ? 'Димаш (Қонақ)'
          : (_lang == 'ru' ? 'Димаш (Гость)' : 'Dimash (Guest)'),
      emailOrPhone: 'guest@antisleep.kz',
      carPlate: '777 AAA 02',
      language: _lang,
      sosPhone: '+7 (777) 123-45-67',
      isGuest: true,
    );
    await saveDriverProfileToDisk(guest);
  }

  /// Email/Password Login
  Future<bool> login({
    required String emailOrPhone,
    required String password,
  }) async {
    // Determine driver name from email/phone
    String derivedName = emailOrPhone.split('@').first;
    if (derivedName.length > 1) {
      derivedName = derivedName[0].toUpperCase() + derivedName.substring(1);
    } else {
      derivedName = 'Жүргізуші / Водитель';
    }

    final DriverProfile profile = DriverProfile(
      name: derivedName,
      emailOrPhone: emailOrPhone.trim(),
      carPlate: '777 AAA 02',
      language: _lang,
      sosPhone: '+7 (777) 123-45-67',
      isGuest: false,
    );
    await saveDriverProfileToDisk(profile);
    return true;
  }

  /// Full Registration
  Future<bool> register({
    required String name,
    required String emailOrPhone,
    required String password,
    required String carPlate,
    required String language,
  }) async {
    final DriverProfile profile = DriverProfile(
      name: name.trim().isEmpty ? 'Жүргізуші / Водитель' : name.trim(),
      emailOrPhone: emailOrPhone.trim(),
      carPlate: carPlate.trim().isEmpty ? 'KZ 000 AAA 01' : carPlate.trim().toUpperCase(),
      language: language,
      sosPhone: '', // Left empty as SOS is configured optionally in Settings
      isGuest: false,
    );
    await saveDriverProfileToDisk(profile);
    return true;
  }

  /// Update SOS phone from Settings screen
  Future<void> updateSosPhone(String phone) async {
    if (currentDriver != null) {
      final DriverProfile updated = currentDriver!.copyWith(sosPhone: phone.trim());
      await saveDriverProfileToDisk(updated);
    }
  }

  /// Logout and clear saved driver profile
  Future<void> logout() async {
    currentDriver = null;
    notifyListeners();
    try {
      if (kIsWeb) {
        WebFaceBridge.clearDriverProfile();
      } else {
        final File file =
            File('${Directory.systemTemp.path}/antisleep_driver.json');
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Error logging out: $e');
    }
  }
}

final AppSessionState appState = AppSessionState();
