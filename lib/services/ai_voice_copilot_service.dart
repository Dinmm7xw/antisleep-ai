import 'dart:async';
import 'package:flutter/foundation.dart';
import '../state/app_session_state.dart';
import 'kazakh_voice_audio.dart';
import 'web_face_bridge.dart';

enum QuickCopilotAction {
  greet,
  citiesGame,
  mathPuzzle,
  triviaQuiz,
  funnyJoke,
  fatigueAdvice,
  checkIn,
}

class AiVoiceMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  AiVoiceMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AiVoiceCopilotService extends ChangeNotifier {
  static final AiVoiceCopilotService _instance = AiVoiceCopilotService._internal();
  factory AiVoiceCopilotService() => _instance;
  AiVoiceCopilotService._internal();

  bool _isListening = false;
  bool _isSpeaking = false;
  String _lastUserSpeech = '';
  String _lastAiResponse = '';
  Timer? _pollingTimer;
  DateTime? _lastAutoPromptTime;

  final List<AiVoiceMessage> _messages = <AiVoiceMessage>[];

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String get lastUserSpeech => _lastUserSpeech;
  String get lastAiResponse => _lastAiResponse;
  List<AiVoiceMessage> get messages => List.unmodifiable(_messages);

  void startListening() {
    _isListening = true;
    final String lang = appState.lang;
    WebFaceBridge.startListening(lang);

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _pollSpeechRecognition();
    });
    notifyListeners();
  }

  void stopListening() {
    _isListening = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    WebFaceBridge.stopListening();
    notifyListeners();
  }

  void toggleListening() {
    if (_isListening) {
      stopListening();
    } else {
      startListening();
    }
  }

  void _pollSpeechRecognition() {
    final String? text = WebFaceBridge.pollLatestSpeechInput();
    if (text != null && text.trim().isNotEmpty) {
      handleUserSpeech(text.trim());
    }
  }

  void handleUserSpeech(String text) {
    if (text.isEmpty) return;
    _lastUserSpeech = text;
    _messages.add(AiVoiceMessage(text: text, isUser: true));
    notifyListeners();

    _dispatchIntent(text, text.toLowerCase());
  }

  void triggerQuickAction(QuickCopilotAction action) {
    switch (action) {
      case QuickCopilotAction.greet:
        _respond(
          kk: 'Сәлеметсіз бе! Мен AntiSleep көмекшісімін. Жолда сергек болыңыз, мен сізбен біргемін!',
          ru: 'Привет! Я ваш голосовой помощник AntiSleep. Слежу за вашей бодростью и безопасностью!',
          en: 'Hello! I am your AntiSleep co-pilot. Staying alert with you on the road!',
          playAudio: () => KazakhVoiceAudio.playCopilotGreet(),
        );
        break;

      case QuickCopilotAction.citiesGame:
        _respond(
          kk: 'Керемет! Ұйқыны ашу үшін қалалар ойынын ойнайық. Мен бастаймын: Алматы! Сізге «Ы» әрпінен қала кезегі!',
          ru: 'Отличная идея! Сыграем в города, чтобы прогнать сонливость. Я начинаю: Астана! Вам на букву «А»!',
          en: "Great idea! Let's play the cities game to stay sharp. I'll start: London! Your turn with letter 'N'!",
          playAudio: () => KazakhVoiceAudio.playCityGameStart(),
        );
        break;

      case QuickCopilotAction.mathPuzzle:
        _respond(
          kk: 'Миды сергітейік! 8 көбейту 12 неше болады? Жылдам жауап беріңіз!',
          ru: 'Разминка для мозга! Сколько будет 8 умножить на 12? Быстрый ответ!',
          en: 'Brain exercise! What is 8 times 12? Quick answer!',
          playAudio: () => KazakhVoiceAudio.playMathPrompt(),
        );
        break;

      case QuickCopilotAction.triviaQuiz:
        _respond(
          kk: 'Қызықты сұрақ: әлемдегі ең үлкен көл қалай аталады? Ойланып көріңізші!',
          ru: 'Интересный вопрос: какое самое большое озеро в мире? Жду ответ!',
          en: 'Trivia time: what is the largest lake in the world? Let us hear your guess!',
          playAudio: () => KazakhVoiceAudio.playTriviaPrompt(),
        );
        break;

      case QuickCopilotAction.funnyJoke:
        _respond(
          kk: 'Бір жүргізуші көлігіне жасанды интеллект орнатыпты. Интеллект бірінші күні: «Бауырым, жылдамдықты азайтшы, мен әлі өмір сүргім келеді» депті!',
          ru: 'Водитель установил в авто умный ИИ. Через пять минут ИИ говорит: «Брат, сбавь скорость, у меня еще гарантия не закончилась»!',
          en: "A driver installed an AI copilot. After five minutes the AI says: 'Hey, slow down, my cloud subscription isn't backed up yet'!",
          playAudio: () => KazakhVoiceAudio.playJokeCar(),
        );
        break;

      case QuickCopilotAction.fatigueAdvice:
        _respond(
          kk: 'Егер қатты ұйқыңыз келсе, жақын жердегі май құю бекетіне тоқтап, ыстық кофе ішіп 15 минут көз шырымын алғаныңыз дұрыс!',
          ru: 'Если чувствуете сильную усталость, рекомендую остановиться на ближайшей АЗС, выпить кофе и вздремнуть 15 минут!',
          en: 'If you feel drowsy, please pull over at the nearest service station, grab a coffee, and take a quick 15-minute power nap!',
          playAudio: () => KazakhVoiceAudio.playAdviceCoffee(),
        );
        break;

      case QuickCopilotAction.checkIn:
        _respond(
          kk: 'Жол тәртібін жақсы сақтап келесіз. Бақылаудасыз, ақ жол!',
          ru: 'Вы отлично управляете автомобилем. Безопасность под контролем, счастливого пути!',
          en: 'You are driving very smoothly. Safety parameters are normal, have a great trip!',
          playAudio: () => KazakhVoiceAudio.playPraiseDriving(),
        );
        break;
    }
  }

  void _dispatchIntent(String rawText, String clean) {
    // 1. Greetings
    if (clean.contains('сәлем') ||
        clean.contains('қалайсың') ||
        clean.contains('ассалаумағалейкум') ||
        clean.contains('привет') ||
        clean.contains('здравствуй') ||
        clean.contains('как дела') ||
        clean.contains('hello') ||
        clean.contains('hi') ||
        clean.contains('hey')) {
      triggerQuickAction(QuickCopilotAction.greet);
      return;
    }

    // 2. Math response check
    if (clean.contains('96') ||
        clean.contains('тоқсан алты') ||
        clean.contains('девяносто шесть') ||
        clean.contains('ninety six')) {
      _respond(
        kk: 'Жарайсыз! Дұрыс жауап: 96! Миыңыз қайта сергіді!',
        ru: 'Браво! Абсолютно верно: 96! Ваш мозг полностью проснулся!',
        en: 'Spot on! That is correct: 96! Feeling sharp and energized!',
        playAudio: () => KazakhVoiceAudio.playMathCorrect(),
      );
      return;
    }

    // 3. Math prompt request
    if (clean.contains('есеп') ||
        clean.contains('математика') ||
        clean.contains('сана') ||
        clean.contains('задач') ||
        clean.contains('пример') ||
        clean.contains('math') ||
        clean.contains('count')) {
      triggerQuickAction(QuickCopilotAction.mathPuzzle);
      return;
    }

    // 4. Cities Game answers check
    if (clean.contains('алматы') ||
        clean.contains('астана') ||
        clean.contains('ақтау') ||
        clean.contains('атырау') ||
        clean.contains('шымкент') ||
        clean.contains('ыстықкөл') ||
        clean.contains('новгород') ||
        clean.contains('москва') ||
        clean.contains('new york') ||
        clean.contains('london')) {
      _respond(
        kk: 'Тамаша қала! Менің кезегім: Ыстықкөл! Сіздің кезегіңіз келді!',
        ru: 'Отличный город! Мой ответ: Новгород! Теперь ваш черед!',
        en: 'Great city! My turn: Newcastle! Now your turn!',
        playAudio: () => KazakhVoiceAudio.playCityGameAlmatyReply(),
      );
      return;
    }

    // 5. Game request
    if (clean.contains('ойын') ||
        clean.contains('ойнайық') ||
        clean.contains('қалалар') ||
        clean.contains('игра') ||
        clean.contains('города') ||
        clean.contains('сыграем') ||
        clean.contains('play') ||
        clean.contains('game')) {
      triggerQuickAction(QuickCopilotAction.citiesGame);
      return;
    }

    // 6. Trivia Caspian Answer check
    if (clean.contains('каспий') ||
        clean.contains('каспийск') ||
        clean.contains('caspian')) {
      _respond(
        kk: 'Өте тамаша! Каспий теңізі – әлемдегі ең үлкен көл. Жадыңыз керемет!',
        ru: 'Великолепно! Каспийское море — самое большое бессточное озеро Земли. Отличная эрудиция!',
        en: "Brilliant! The Caspian Sea is the world's largest inland lake. Great knowledge!",
        playAudio: () => KazakhVoiceAudio.playTriviaCaspian(),
      );
      return;
    }

    // 7. Trivia request
    if (clean.contains('сұрақ') ||
        clean.contains('викторина') ||
        clean.contains('қызық') ||
        clean.contains('вопрос') ||
        clean.contains('викторин') ||
        clean.contains('trivia') ||
        clean.contains('quiz')) {
      triggerQuickAction(QuickCopilotAction.triviaQuiz);
      return;
    }

    // 8. Jokes / Humor
    if (clean.contains('әзіл') ||
        clean.contains('анекдот') ||
        clean.contains('күлдір') ||
        clean.contains('шутк') ||
        clean.contains('юмор') ||
        clean.contains('joke') ||
        clean.contains('funny')) {
      triggerQuickAction(QuickCopilotAction.funnyJoke);
      return;
    }

    // 9. Drowsiness / Fatigue
    if (clean.contains('шаршадым') ||
        clean.contains('ұйқым') ||
        clean.contains('ұйықта') ||
        clean.contains('устал') ||
        clean.contains('спать') ||
        clean.contains('сонн') ||
        clean.contains('tired') ||
        clean.contains('sleepy')) {
      triggerQuickAction(QuickCopilotAction.fatigueAdvice);
      return;
    }

    // 10. Driving performance / Praise
    if (clean.contains('қалай келем') ||
        clean.contains('қалай жүргізіп') ||
        clean.contains('рахмет') ||
        clean.contains('жақсы') ||
        clean.contains('как я еду') ||
        clean.contains('спасибо') ||
        clean.contains('хорошо') ||
        clean.contains('how am i driving') ||
        clean.contains('thanks')) {
      triggerQuickAction(QuickCopilotAction.checkIn);
      return;
    }

    // 11. Open-ended conversational fallback (Adaptive Smart Response)
    final String lang = appState.lang;
    if (lang == 'ru') {
      _respond(
        kk: '',
        ru: 'Слышу вас: «$rawText». Чтобы не уснуть за рулем, давайте сыграем в города или решим пример!',
        en: '',
        playAudio: () => KazakhVoiceAudio.playCopilotGreet(),
      );
    } else if (lang == 'en') {
      _respond(
        kk: '',
        ru: '',
        en: 'I hear you: "$rawText". To stay awake, let us play the cities game or solve a quick math riddle!',
        playAudio: () => KazakhVoiceAudio.playCopilotGreet(),
      );
    } else {
      _respond(
        kk: 'Сізді тыңдап тұрмын: «$rawText». Ұйқыны ашу үшін қалалар немесе есеп ойынын ойнайық па?',
        ru: '',
        en: '',
        playAudio: () => KazakhVoiceAudio.playCopilotGreet(),
      );
    }
  }

  void _respond({
    required String kk,
    required String ru,
    required String en,
    required VoidCallback playAudio,
  }) {
    final String currentLang = appState.lang;
    final String messageText = currentLang == 'ru'
        ? ru
        : currentLang == 'en'
            ? en
            : kk;

    _lastAiResponse = messageText;
    _messages.add(AiVoiceMessage(text: messageText, isUser: false));
    _isSpeaking = true;
    notifyListeners();

    playAudio();

    Future<void>.delayed(const Duration(seconds: 4), () {
      _isSpeaking = false;
      notifyListeners();
    });
  }

  void checkFatigueAutoPrompt(int fatigueScore, int yawns) {
    if (fatigueScore < 45 && yawns < 2) return;

    final DateTime now = DateTime.now();
    if (_lastAutoPromptTime != null &&
        now.difference(_lastAutoPromptTime!).inMinutes < 3) {
      return;
    }
    _lastAutoPromptTime = now;

    _respond(
      kk: 'Шаршаған сияқтысыз. Жолда сергек болу үшін сөйлесейік!',
      ru: 'Кажется, вы утомлены. Давайте побеседуем, чтобы вы не уснули!',
      en: 'You seem tired. Let us talk to keep you awake and focused!',
      playAudio: () => KazakhVoiceAudio.playCopilotFatiguePrompt(),
    );
  }
}

final AiVoiceCopilotService aiCopilotService = AiVoiceCopilotService();
