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
  static final AiVoiceCopilotService _instance =
      AiVoiceCopilotService._internal();
  factory AiVoiceCopilotService() => _instance;
  AiVoiceCopilotService._internal();

  bool _isListening = false;
  bool _isSpeaking = false;
  String _lastUserSpeech = '';
  String _lastAiResponse = '';
  String _interimSpeech = '';
  Timer? _pollingTimer;
  DateTime? _lastAutoPromptTime;

  final List<AiVoiceMessage> _messages = <AiVoiceMessage>[];

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String get lastUserSpeech => _lastUserSpeech;
  String get lastAiResponse => _lastAiResponse;
  String get interimSpeech => _interimSpeech;
  List<AiVoiceMessage> get messages => List.unmodifiable(_messages);

  void startListening() {
    _isListening = true;
    _interimSpeech = '';
    final String lang = appState.lang;
    WebFaceBridge.startListening(lang);

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _pollSpeechRecognition();
    });
    notifyListeners();
  }

  void stopListening() {
    _isListening = false;
    _interimSpeech = '';
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
    // 1. Check live interim speech (words being spoken in real-time)
    final String? liveInterim = WebFaceBridge.pollInterimSpeechInput();
    if (liveInterim != null && liveInterim.trim().isNotEmpty) {
      if (_interimSpeech != liveInterim.trim()) {
        _interimSpeech = liveInterim.trim();
        notifyListeners();
      }
    } else if (_interimSpeech.isNotEmpty) {
      _interimSpeech = '';
      notifyListeners();
    }

    // 2. Check finalized user utterance
    final String? finalText = WebFaceBridge.pollLatestSpeechInput();
    if (finalText != null && finalText.trim().isNotEmpty) {
      _interimSpeech = '';
      handleUserSpeech(finalText.trim());
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
        _respondStudio(
          kk: 'Сәлеметсіз бе! Мен AntiSleep көмекшісімін. Жолда сергек болыңыз, мен сізбен біргемін!',
          ru: 'Привет! Я ваш голосовой помощник AntiSleep. Слежу за вашей бодростью и безопасностью!',
          en: 'Hello! I am your AntiSleep co-pilot. Staying alert with you on the road!',
          playAudio: () => KazakhVoiceAudio.playCopilotGreet(),
        );
        break;

      case QuickCopilotAction.citiesGame:
        _respondStudio(
          kk: 'Керемет! Ұйқыны ашу үшін қалалар ойынын ойнайық. Мен бастаймын: Алматы! Сізге «Ы» әрпінен қала кезегі!',
          ru: 'Отличная идея! Сыграем в города, чтобы прогнать сонливость. Я начинаю: Астана! Вам на букву «А»!',
          en: "Great idea! Let's play the cities game to stay sharp. I'll start: London! Your turn with letter 'N'!",
          playAudio: () => KazakhVoiceAudio.playCityGameStart(),
        );
        break;

      case QuickCopilotAction.mathPuzzle:
        _respondStudio(
          kk: 'Миды сергітейік! 8 көбейту 12 неше болады? Жылдам жауап беріңіз!',
          ru: 'Разминка для мозга! Сколько будет 8 умножить на 12? Быстрый ответ!',
          en: 'Brain exercise! What is 8 times 12? Quick answer!',
          playAudio: () => KazakhVoiceAudio.playMathPrompt(),
        );
        break;

      case QuickCopilotAction.triviaQuiz:
        _respondStudio(
          kk: 'Қызықты сұрақ: әлемдегі ең үлкен көл қалай аталады? Ойланып көріңізші!',
          ru: 'Интересный вопрос: какое самое большое озеро в мире? Жду ответ!',
          en: 'Trivia time: what is the largest lake in the world? Let us hear your guess!',
          playAudio: () => KazakhVoiceAudio.playTriviaPrompt(),
        );
        break;

      case QuickCopilotAction.funnyJoke:
        _respondStudio(
          kk: 'Бір жүргізуші көлігіне жасанды интеллект орнатыпты. Интеллект бірінші күні: «Бауырым, жылдамдықты азайтшы, мен әлі өмір сүргім келеді» депті!',
          ru: 'Водитель установил в авто умный ИИ. Через пять минут ИИ говорит: «Брат, сбавь скорость, у меня еще гарантия не закончилась»!',
          en: "A driver installed an AI copilot. After five minutes the AI says: 'Hey, slow down, my cloud subscription isn't backed up yet'!",
          playAudio: () => KazakhVoiceAudio.playJokeCar(),
        );
        break;

      case QuickCopilotAction.fatigueAdvice:
        _respondStudio(
          kk: 'Егер қатты ұйқыңыз келсе, жақын жердегі май құю бекетіне тоқтап, ыстық кофе ішіп 15 минут көз шырымын алғаныңыз дұрыс!',
          ru: 'Если чувствуете сильную усталость, рекомендую остановиться на ближайшей АЗС, выпить кофе и вздремнуть 15 минут!',
          en: 'If you feel drowsy, please pull over at the nearest service station, grab a coffee, and take a quick 15-minute power nap!',
          playAudio: () => KazakhVoiceAudio.playAdviceCoffee(),
        );
        break;

      case QuickCopilotAction.checkIn:
        _respondStudio(
          kk: 'Жол тәртібін жақсы сақтап келесіз. Бақылаудасыз, ақ жол!',
          ru: 'Вы отлично управляете автомобилем. Безопасность под контролем, счастливого пути!',
          en: 'You are driving very smoothly. Safety parameters are normal, have a great trip!',
          playAudio: () => KazakhVoiceAudio.playPraiseDriving(),
        );
        break;
    }
  }

  void _dispatchIntent(String rawText, String clean) {
    // 1. Pavlodar (Specific question asked by user!)
    if (clean.contains('павлодар') || clean.contains('pavlodar')) {
      _respondHuman(
        kk: 'Павлодарда бүгін ауа райы қалыпты, Ертіс бойында сергітетін самал жел. Егер Павлодар тасжолында келе жатсаңыз, жол жамылғысына абай болыңыз, жылдамдықты асырмай, қауіпсіз қашықтық сақтаңыз. Ақ жол!',
        ru: 'В Павлодаре сегодня спокойная погода, свежий воздух у Иртыша. Если вы на павлодарской трассе, соблюдайте скоростной режим и дистанцию. Счастливого и безопасного пути!',
        en: 'Pavlodar has good weather today along the Irtysh river. Maintain a safe speed and following distance on the highway. Have a safe journey!',
      );
      return;
    }

    // 2. Astana / Nur-Sultan
    if (clean.contains('астана') || clean.contains('astana')) {
      _respondHuman(
        kk: 'Елордамыз Астанада көлік қозғалысы өте тығыз. Бағдаршамдарға, айналма жолдар мен жаяу жүргіншілерге аса мұқият болыңыз. Асықпай, сабырмен жүріңіз!',
        ru: 'В Астане движение довольно плотное. Будьте предельно внимательны на развязках и светофорах. Держите дистанцию и не спешите!',
        en: 'Astana has busy urban traffic today. Stay focused at intersections and keep a safe following distance!',
      );
      return;
    }

    // 3. Almaty
    if (clean.contains('алматы') || clean.contains('almaty')) {
      _respondHuman(
        kk: 'Алматының тау бөктері тамаша, бірақ орталық көшелерде кептеліс жиі болады. Сабыр сақтап, жаяу жүргіншілерге жол беріңіз. Жолыңыз сәтті өтсін!',
        ru: 'В Алматы отличный вид на горы, но на дорогах возможны заторы. Соблюдайте рядность и пропускайте пешеходов. Приятной поездки!',
        en: 'Almaty has beautiful mountain views, but watch for city slowdowns. Stay patient and drive smoothly!',
      );
      return;
    }

    // 4. Shymkent / Karaganda / Aktau / Atyrau
    if (clean.contains('шымкент') || clean.contains('shymkent')) {
      _respondHuman(
        kk: 'Шымкентте күн ашық, жолдар жылы әрі кең. Жылдамдықты шамадан асырмай, жол ережесін сақтаңыз!',
        ru: 'В Шымкенте тепло и солнечно. Соблюдайте скоростной режим и уважайте других участников движения!',
        en: 'Shymkent has warm sunny weather. Keep your eyes on the road and drive safely!',
      );
      return;
    }

    if (clean.contains('қарағанды') || clean.contains('караганд')) {
      _respondHuman(
        kk: 'Қарағанды өңірінде жолдар ұзақ әрі түзу. Біркелкі ұзақ жолда көз тез талуы мүмкін. Мезгіл-мезгіл терезені ашып, таза ауа жұтыңыз!',
        ru: 'На карагандинской трассе длинные прямые участки. Не допускайте монотонной усталости — впустите свежий воздух и пейте воду!',
        en: 'Karaganda highways are long and straight. Prevent highway hypnosis by keeping the cabin well ventilated!',
      );
      return;
    }

    // 5. Weather / Road conditions
    if (clean.contains('ауа райы') ||
        clean.contains('погода') ||
        clean.contains('жаңбыр') ||
        clean.contains('қар') ||
        clean.contains('тайғақ') ||
        clean.contains('weather')) {
      _respondHuman(
        kk: 'Қазіргі маусымда тасжолдарда көру қашықтығы төмендеуі және тайғақ болуы мүмкін. Тұман мен ылғалда жарықты қосып, жылдамдықты 20 пайызға азайтыңыз.',
        ru: 'На трассе возможны участки с переменной видимостью и влажным покрытием. Включите ближний свет и снизьте скорость на 15-20%.',
        en: 'Road conditions vary with seasonal changes. Keep your headlights on and reduce speed on damp surfaces.',
      );
      return;
    }

    // 6. Current Time
    if (clean.contains('сағат') ||
        clean.contains('уақыт') ||
        clean.contains('время') ||
        clean.contains('time')) {
      final DateTime now = DateTime.now();
      final String timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      _respondHuman(
        kk: 'Қазіргі нақты уақыт: сағат $timeStr. ${now.hour >= 23 || now.hour < 6 ? 'Түнгі уақыт – ұйқының ең қауіпті мезгілі, сергек болыңыз!' : 'Күндізгі уақытта жақсы әрі қауіпсіз сапар тілеймін!'}',
        ru: 'Текущее время: $timeStr. ${now.hour >= 23 || now.hour < 6 ? 'Ночное время требует максимальной концентрации за рулем!' : 'Счастливой и бодрой дневной поездки!'}',
        en: 'The current time is $timeStr. Stay alert and drive safely!',
      );
      return;
    }

    // 7. Greetings
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

    // 8. Math response check
    if (clean.contains('96') ||
        clean.contains('тоқсан алты') ||
        clean.contains('девяносто шесть') ||
        clean.contains('ninety six')) {
      _respondStudio(
        kk: 'Жарайсыз! Дұрыс жауап: 96! Миыңыз қайта сергіді!',
        ru: 'Браво! Абсолютно верно: 96! Ваш мозг полностью проснулся!',
        en: 'Spot on! That is correct: 96! Feeling sharp and energized!',
        playAudio: () => KazakhVoiceAudio.playMathCorrect(),
      );
      return;
    }

    // 9. Math prompt request
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

    // 10. Cities Game response check
    if (clean.contains('астана') ||
        clean.contains('ақтау') ||
        clean.contains('атырау') ||
        clean.contains('шымкент') ||
        clean.contains('ыстықкөл') ||
        clean.contains('новгород') ||
        clean.contains('москва') ||
        clean.contains('new york') ||
        clean.contains('london')) {
      _respondStudio(
        kk: 'Тамаша қала! Менің кезегім: Ыстықкөл! Сіздің кезегіңіз келді!',
        ru: 'Отличный город! Мой ответ: Новгород! Теперь ваш черед!',
        en: 'Great city! My turn: Newcastle! Now your turn!',
        playAudio: () => KazakhVoiceAudio.playCityGameAlmatyReply(),
      );
      return;
    }

    // 11. Game request
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

    // 12. Trivia Caspian Answer check
    if (clean.contains('каспий') ||
        clean.contains('каспийск') ||
        clean.contains('caspian')) {
      _respondStudio(
        kk: 'Өте тамаша! Каспий теңізі – әлемдегі ең үлкен көл. Жадыңыз керемет!',
        ru: 'Великолепно! Каспийское море — самое большое бессточное озеро Земли. Отличная эрудиция!',
        en: "Brilliant! The Caspian Sea is the world's largest inland lake. Great knowledge!",
        playAudio: () => KazakhVoiceAudio.playTriviaCaspian(),
      );
      return;
    }

    // 13. Trivia request
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

    // 14. Jokes / Humor
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

    // 15. Drowsiness / Fatigue / Sleep
    if (clean.contains('шаршадым') ||
        clean.contains('ұйқым') ||
        clean.contains('ұйықта') ||
        clean.contains('устал') ||
        clean.contains('спать') ||
        clean.contains('сонн') ||
        clean.contains('tired') ||
        clean.contains('sleepy')) {
      _respondHuman(
        kk: 'Бауырым, ұйқымен ойнауға мүлдем болмайды! Көз 1 секундқа жұмылса да қауіпті. Дереу жақын май құю бекетіне тоқтаңыз, бетіңізді суық сумен шайып, 15 минут тынығып алыңыз. Мен сізді бақылап отырмын!',
        ru: 'Друг, со сном шутить нельзя! Даже секундный микросон опасен. Пожалуйста, остановитесь на ближайшей АЗС, умойтесь холодной водой и отдохните 15 минут. Я слежу за вами!',
        en: 'Please do not fight drowsiness on the road! Pull over safely at the nearest station, drink some water, and take a 15-minute power nap. Your life is the priority!',
      );
      return;
    }

    // 16. Driving performance / Praise
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

    // 17. Music / Radio
    if (clean.contains('ән') ||
        clean.contains('музыка') ||
        clean.contains('песн') ||
        clean.contains('радио') ||
        clean.contains('music')) {
      _respondHuman(
        kk: 'Жолда ұйқыны серпілту үшін ырғақты, жігерлі әуен қосыңыз! Домбыра күйлері немесе көңілді динамикалық әндер ми белсенділігін керемет арттырады.',
        ru: 'Чтобы взбодриться, включите ритмичную динамичную музыку! Энергичный бит помогает удерживать концентрацию на дороге.',
        en: 'Turn on some upbeat, rhythmic music! A lively tempo keeps your brain stimulated and alert.',
      );
      return;
    }

    // 18. Identity / Assistant info
    if (clean.contains('кімсің') ||
        clean.contains('сен кім') ||
        clean.contains('кто ты') ||
        clean.contains('ты кто') ||
        clean.contains('who are you')) {
      _respondHuman(
        kk: 'Мен AntiSleep AI – көлік жүргізушісінің сенімді дауыстық серігімін. Сіздің ұйықтап кетпеуіңізді қадағалап, жолда қауіпсіз әрі сергек жүруіңізге көмектесемін. Сұрақтарыңыз болса қоя беріңіз!',
        ru: 'Я AntiSleep AI — ваш умный голосовой штурман. Контролирую внимание водителя, чтобы вы не заснули, и помогаю безопасно добраться до цели.',
        en: 'I am AntiSleep AI, your smart voice co-pilot. I monitor alertness and chat with you to keep you safe and energized behind the wheel.',
      );
      return;
    }

    // 19. Open-ended Conversational Human Response (For ANY other statement/question)
    _respondHuman(
      kk: 'Сізді түсіндім: «$rawText». Жолда сергек әрі көңілді келе жатқаныңызға қуаныштымын. Қандай тақырыпта әңгімелескіңіз келеді? Мысалы, қалалар ойынын ойнайық па немесе бір әзіл айтайын ба?',
      ru: 'Вас понял: «$rawText». Рад, что вы бодры за рулем! О чем побеседуем? Можем сыграть в города, решить пример или рассказать анекдот?',
      en: 'Understood: "$rawText". Glad to keep you company on the road! Shall we play the cities game or hear a quick joke?',
    );
  }

  /// Studio neural response (uses pre-recorded Azure clips)
  void _respondStudio({
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

  /// Dynamic human-like conversational response (synthesizes voice with WebFaceBridge.speakText)
  void _respondHuman({
    required String kk,
    required String ru,
    required String en,
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

    // Voice output via Browser Speech Synthesis
    WebFaceBridge.speakText(messageText, currentLang);

    // Approximate speaking duration: ~65 words per minute
    final int words = messageText.split(' ').length;
    final int durationMs = (words * 320).clamp(2500, 10000);

    Future<void>.delayed(Duration(milliseconds: durationMs), () {
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

    _respondStudio(
      kk: 'Шаршаған сияқтысыз. Жолда сергек болу үшін сөйлесейік!',
      ru: 'Кажется, вы утомлены. Давайте побеседуем, чтобы вы не уснули!',
      en: 'You seem tired. Let us talk to keep you awake and focused!',
      playAudio: () => KazakhVoiceAudio.playCopilotFatiguePrompt(),
    );
  }
}

final AiVoiceCopilotService aiCopilotService = AiVoiceCopilotService();
