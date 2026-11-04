import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/cockpit_colors.dart';
import '../services/web_face_bridge.dart';
import '../state/app_session_state.dart';
import '../widgets/cockpit_app_bar.dart';
import '../widgets/cockpit_bottom_nav_bar.dart';

/// Screen 4: Advanced Cockpit Settings & AI Fatigue Sensitivity Calibration.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Settings local state mirrors appState
  double _earThreshold = 0.25;
  double _alarmTimeoutSec = 1.5;
  int _alarmSoundIndex = 0; // 0 = Сирена 880Гц, 1 = Голос ИИ, 2 = Мягкий гонг
  bool _sosAlertEnabled = true;
  final TextEditingController _sosPhoneController =
      TextEditingController(text: '+7 (777) 123-45-67');

  @override
  void initState() {
    super.initState();
    _earThreshold = appState.effectiveEarThreshold;
  }

  @override
  void dispose() {
    _sosPhoneController.dispose();
    super.dispose();
  }

  void _testAlarmSound() {
    HapticFeedback.heavyImpact();
    if (kIsWeb) {
      if (_alarmSoundIndex == 0) {
        WebFaceBridge.playAlarmSound();
      } else if (_alarmSoundIndex == 1) {
        WebFaceBridge.speakNavigationInstruction(
          'Внимание! Обнаружена усталость. Пожалуйста, откройте глаза!',
        );
      } else {
        WebFaceBridge.speakNavigationInstruction('[CHIME]');
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _alarmSoundIndex == 0
              ? 'Тест: Звучит громкая сирена (880 Гц / 440 Гц)'
              : (_alarmSoundIndex == 1
                  ? 'Тест: Голосовое ИИ-предупреждение'
                  : 'Тест: Мягкий звуковой сигнал'),
        ),
        backgroundColor: CockpitColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CockpitColors.background,
      appBar: CockpitAppBar(
        titleOverride: appState.t('navSettings'),
      ),
      bottomNavigationBar: const CockpitBottomNavBar(currentIndex: 4),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: <Widget>[
            // 1. Language Quick Switcher
            _buildSectionHeader('ЯЗЫК ИНТЕРФЕЙСА / ТІЛ ТАҢДАУ', Icons.language_rounded),
            _buildCard(
              child: Row(
                children: <Widget>[
                  _buildLangChip('kk', 'Қазақша'),
                  const SizedBox(width: 8),
                  _buildLangChip('ru', 'Русский'),
                  const SizedBox(width: 8),
                  _buildLangChip('en', 'English'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. AI Sensitivity & Driving Mode
            _buildSectionHeader('РЕЖИМ ПОЕЗДКИ И ЧУВСТВИТЕЛЬНОСТЬ ИИ', Icons.speed_rounded),
            _buildCard(
              child: Column(
                children: <Widget>[
                  _buildRadioOption<SensitivityMode>(
                    title: '🏙️ Городской режим',
                    subtitle: 'Меньше ложных тревог на светофорах и в пробках',
                    value: SensitivityMode.city,
                    groupValue: appState.sensitivityMode,
                    onChanged: (SensitivityMode? mode) {
                      if (mode != null) {
                        setState(() => appState.setSensitivityMode(mode));
                      }
                    },
                  ),
                  const Divider(color: CockpitColors.cardBorder, height: 16),
                  _buildRadioOption<SensitivityMode>(
                    title: '🛣️ Трасса (Рекомендуется)',
                    subtitle: 'Сбалансированный контроль морганий и микросна',
                    value: SensitivityMode.highway,
                    groupValue: appState.sensitivityMode,
                    onChanged: (SensitivityMode? mode) {
                      if (mode != null) {
                        setState(() => appState.setSensitivityMode(mode));
                      }
                    },
                  ),
                  const Divider(color: CockpitColors.cardBorder, height: 16),
                  _buildRadioOption<SensitivityMode>(
                    title: '🌙 Ночной экспресс (Строгий)',
                    subtitle: 'Быстрая реакция на слипание век (> 1.0 сек)',
                    value: SensitivityMode.strict,
                    groupValue: appState.sensitivityMode,
                    onChanged: (SensitivityMode? mode) {
                      if (mode != null) {
                        setState(() => appState.setSensitivityMode(mode));
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Eye Aspect Ratio (EAR) Threshold Calibration
            _buildSectionHeader('КАЛИБРОВКА ДАТЧИКА ГЛАЗ (EAR THRESHOLD)', Icons.visibility_rounded),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Порог закрытия век (EAR)',
                        style: TextStyle(
                          color: CockpitColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF19AA1E).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _earThreshold.toStringAsFixed(2),
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Настройте, если носите очки или у вас узкий разрез глаз:',
                    style: TextStyle(color: CockpitColors.textMuted, fontSize: 12),
                  ),
                  Slider(
                    value: _earThreshold,
                    min: 0.18,
                    max: 0.32,
                    divisions: 14,
                    activeColor: const Color(0xFF19AA1E),
                    inactiveColor: const Color(0xFF2C3238),
                    onChanged: (double val) {
                      setState(() {
                        _earThreshold = val;
                        appState.setPersonalEarOffset(val - 0.25);
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const <Widget>[
                      Text('0.18 (Узкие / Очки)', style: TextStyle(color: CockpitColors.textMuted, fontSize: 11)),
                      Text('0.25 (Стандарт)', style: TextStyle(color: CockpitColors.textMuted, fontSize: 11)),
                      Text('0.32 (Широкие)', style: TextStyle(color: CockpitColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Alert Sounds & Alarm Configuration
            _buildSectionHeader('ЗВУК И ТРЕВОГА ОПАСНОСТИ', Icons.volume_up_rounded),
            _buildCard(
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Тип сигнала пробуждения:',
                        style: TextStyle(
                          color: CockpitColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00E676),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _testAlarmSound,
                        icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                        label: const Text('Тест', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _buildSoundChip(0, '🚨 Сирена 880 Гц'),
                      _buildSoundChip(1, '🎙️ Голос ИИ'),
                      _buildSoundChip(2, '🔔 Мягкий гонг'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Время до сирены при закрытых глазах:',
                        style: TextStyle(color: CockpitColors.textPrimary, fontSize: 13),
                      ),
                      DropdownButton<double>(
                        value: _alarmTimeoutSec,
                        dropdownColor: CockpitColors.card,
                        underline: const SizedBox(),
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                        items: const <DropdownMenuItem<double>>[
                          DropdownMenuItem<double>(value: 1.0, child: Text('1.0 сек (Быстро)')),
                          DropdownMenuItem<double>(value: 1.5, child: Text('1.5 сек (Норма)')),
                          DropdownMenuItem<double>(value: 2.0, child: Text('2.0 сек (Мягко)')),
                        ],
                        onChanged: (double? val) {
                          if (val != null) setState(() => _alarmTimeoutSec = val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Emergency SOS Dispatcher Contact
            _buildSectionHeader('ЭКСТРЕННЫЙ SOS КОНТАКТ', Icons.contact_emergency_rounded),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF00E676),
                    title: const Text(
                      'SOS-уведомление при долгом сне',
                      style: TextStyle(
                        color: CockpitColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Отправка координат близким, если водитель не проснулся',
                      style: TextStyle(color: CockpitColors.textMuted, fontSize: 11.5),
                    ),
                    value: _sosAlertEnabled,
                    onChanged: (bool val) => setState(() => _sosAlertEnabled = val),
                  ),
                  if (_sosAlertEnabled) ...<Widget>[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _sosPhoneController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Номер телефона (WhatsApp / SMS)',
                        labelStyle: const TextStyle(color: CockpitColors.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF13171B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: CockpitColors.cardBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. Project & Defense Info
            _buildSectionHeader('О СИСТЕМЕ (ЗАЩИТА 13 НОЯБРЯ)', Icons.info_outline_rounded),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  Text(
                    'AntiSleep AI • Intelligent Driver Safety HUD',
                    style: TextStyle(
                      color: CockpitColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Нейросеть: Google ML Kit Face Mesh (468 биометрических точек)\n'
                    '• Карты и навигация: Официальный API 2ГИС (Астана / Алматы)\n'
                    '• Анализ микросна: Алгоритм PERCLOS + MAR (зевание) + Pitch/Yaw\n'
                    '• Платформы: Web, Android, iOS, Apple CarPlay / Android Auto',
                    style: TextStyle(color: CockpitColors.textMuted, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: const Color(0xFF19AA1E)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: CockpitColors.textMuted,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CockpitColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CockpitColors.cardBorder, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildLangChip(String code, String name) {
    final bool isSelected = appState.lang == code;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => appState.setLanguage(code));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF19AA1E) : const Color(0xFF13171B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.transparent : CockpitColors.cardBorder,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            name,
            style: TextStyle(
              color: isSelected ? Colors.white : CockpitColors.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoundChip(int index, String label) {
    final bool isSelected = _alarmSoundIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _alarmSoundIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF19AA1E).withValues(alpha: 0.22) : const Color(0xFF13171B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF19AA1E) : CockpitColors.cardBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00E676) : CockpitColors.textMuted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildRadioOption<T>({
    required String title,
    required String subtitle,
    required T value,
    required T groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    final bool isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Radio<T>(
            value: value,
            groupValue: groupValue,
            activeColor: const Color(0xFF00E676),
            onChanged: onChanged,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : CockpitColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: CockpitColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
