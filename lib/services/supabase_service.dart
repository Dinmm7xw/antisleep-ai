import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/driver_profile.dart';
import '../state/app_session_state.dart';

/// Supabase Cloud PostgreSQL Service for AntiSleep AI.
class SupabaseService {
  static const String supabaseUrl = 'https://pdxdemibwkaftfyavjsg.supabase.co';
  static const String supabasePublishableKey =
      'sb_publishable_TZLphx7IT7V-E3mmLKzfzw_WBHGU6OY';

  static bool _isReady = false;
  static bool get isReady => _isReady;

  static SupabaseClient? get client {
    if (!_isReady) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Initializes Supabase Cloud connection safely
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabasePublishableKey,
      );
      _isReady = true;
      debugPrint('⚡ [Supabase] Connected successfully to Cloud PostgreSQL');
    } catch (e) {
      _isReady = false;
      debugPrint('⚠️ [Supabase] Initialization warning (offline fallback active): $e');
    }
  }

  /// Syncs driver registration/login to cloud table `drivers`
  static Future<void> syncDriverProfile(DriverProfile profile) async {
    if (!_isReady || client == null) return;
    try {
      await client!.from('drivers').upsert(
        <String, dynamic>{
          'name': profile.name,
          'email_or_phone': profile.emailOrPhone,
          'car_plate': profile.carPlate,
          'language': profile.language,
          'sos_phone': profile.sosPhone,
          'is_guest': profile.isGuest,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'email_or_phone',
      );
      debugPrint('⚡ [Supabase] Synced driver profile: ${profile.name} (${profile.carPlate})');
    } catch (e) {
      debugPrint('⚠️ [Supabase] syncDriverProfile warning: $e');
    }
  }

  /// Syncs completed driving trip session to cloud table `trips`
  static Future<void> syncTripRecord(
    TripRecord trip, {
    String? driverIdentifier,
  }) async {
    if (!_isReady || client == null) return;
    try {
      await client!.from('trips').insert(
        <String, dynamic>{
          'driver_identifier': driverIdentifier ?? 'guest',
          'duration_seconds': trip.durationSeconds,
          'safety_score': trip.safetyScore,
          'microsleep_count': trip.microSleepTriggers,
          'yawns_count': trip.yawnsDetected,
          'blinks_count': trip.totalBlinks,
          'average_ear': trip.averageEar,
          'perclos_percent': trip.perclosPercent,
          'created_at': trip.timestamp.toIso8601String(),
        },
      );
      debugPrint('⚡ [Supabase] Synced completed trip to PostgreSQL (Score: ${trip.safetyScore})');
    } catch (e) {
      debugPrint('⚠️ [Supabase] syncTripRecord warning: $e');
    }
  }

  /// Syncs real-time drowsiness incident event to cloud table `incidents`
  static Future<void> syncIncident({
    required String driverIdentifier,
    required String eventType, // 'microsleep', 'yawn', 'head_nod'
    required double ear,
    double? lat,
    double? lng,
  }) async {
    if (!_isReady || client == null) return;
    try {
      await client!.from('incidents').insert(
        <String, dynamic>{
          'driver_identifier': driverIdentifier,
          'event_type': eventType,
          'ear': ear,
          'lat': lat,
          'lng': lng,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('⚡ [Supabase] Logged $eventType event to PostgreSQL');
    } catch (e) {
      debugPrint('⚠️ [Supabase] syncIncident warning: $e');
    }
  }
}

