import 'package:flutter/foundation.dart';

import 'web_face_bridge.dart';

/// Intelligent AI Voice Co-Pilot & Interactive Audio Dialog Service.
/// Provides trilingual (KK / RU / EN) spoken warnings, cognitive guidance,
/// and interactive verbal feedback to eliminate driver micro-sleep.
class VoiceAssistantService {
  static DateTime _lastWarningTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _debounceInterval = Duration(seconds: 5);

  /// Speaks the critical emergency wake-up alert.
  static void speakDrowsinessAlert(String lang) {
    String text;
    switch (lang) {
      case 'kk':
        text = 'Жүргізуші! Назар аударыңыз! Сіз ұйықтап бара жатырсыз! Дереу жолға қараңыз!';
        break;
      case 'ru':
        text = 'Внимание, водитель! Вы засыпаете! Срочно откройте глаза и сфокусируйтесь на дороге!';
        break;
      case 'en':
      default:
        text = 'Attention driver! Drowsiness detected! Keep your eyes on the road immediately!';
        break;
    }
    _speakImmediate(text, lang);
  }

  /// Speaks the cognitive challenge instructions.
  static void speakChallengePrompt(String lang) {
    String text;
    switch (lang) {
      case 'kk':
        text = 'Ояныңыз! Зейініңізді растау үшін экрандағы есепті шешіңіз!';
        break;
      case 'ru':
        text = 'Проснитесь! Подтвердите внимание: выберите правильный ответ на экране!';
        break;
      case 'en':
      default:
        text = 'Wake up! Confirm alertness: solve the challenge on your screen!';
        break;
    }
    _speakImmediate(text, lang);
  }

  /// Speaks celebratory confirmation when cognitive challenge is successfully solved.
  static void speakChallengeSuccess(String lang) {
    String text;
    switch (lang) {
      case 'kk':
        text = 'Тамаша! Назарыңыз қалпына келтірілді. Жолға абай болыңыз, ақ жол!';
        break;
      case 'ru':
        text = 'Отлично! Внимание восстановлено. Счастливого и безопасного пути!';
        break;
      case 'en':
      default:
        text = 'Excellent! Focus restored. Drive safely!';
        break;
    }
    _speakImmediate(text, lang);
  }

  /// Speaks debounced yawn fatigue warning.
  static void speakYawnWarning(String lang) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastWarningTime) < _debounceInterval) return;
    _lastWarningTime = now;

    String text;
    switch (lang) {
      case 'kk':
        text = 'Сіз есінеп жатырсыз. Шаршау белгісі, қауіпсіз жерге тоқтап демалыңыз.';
        break;
      case 'ru':
        text = 'Обнаружено частое зевание. Первые признаки усталости. Рекомендуется сделать остановку.';
        break;
      case 'en':
      default:
        text = 'Frequent yawning detected. Fatigue signs. Pull over and rest if needed.';
        break;
    }
    _speakImmediate(text, lang);
  }

  /// Speaks debounced head nodding warning.
  static void speakHeadNodWarning(String lang) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastWarningTime) < _debounceInterval) return;
    _lastWarningTime = now;

    String text;
    switch (lang) {
      case 'kk':
        text = 'Басыңыз иілді! Жолға тік қараңыз!';
        break;
      case 'ru':
        text = 'Наклон головы вниз! Держите взгляд прямо на дорогу!';
        break;
      case 'en':
      default:
        text = 'Head nod detected! Keep your head up and eyes on the road!';
        break;
    }
    _speakImmediate(text, lang);
  }

  /// Speaks system readiness greeting during Pre-Drive check.
  static void speakGreeting(String lang) {
    String text;
    switch (lang) {
      case 'kk':
        text = 'AntiSleep AI дауыстық көмекшісі қосулы. Қауіпсіз сапар тілейміз!';
        break;
      case 'ru':
        text = 'Голосовой штурман AntiSleep AI активен. Безопасной дороги!';
        break;
      case 'en':
      default:
        text = 'AntiSleep AI Voice Co-Pilot active. Safe travels!';
        break;
    }
    _speakImmediate(text, lang);
  }

  /// Stops current speech output.
  static void stop() {
    try {
      WebFaceBridge.stopSpeech();
    } catch (e) {
      debugPrint('VoiceAssistant stop error: $e');
    }
  }

  static void _speakImmediate(String text, String lang) {
    try {
      WebFaceBridge.speakText(text, lang);
    } catch (e) {
      debugPrint('VoiceAssistant speak error: $e');
    }
  }
}

