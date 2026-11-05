import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/cockpit_colors.dart';
import '../state/app_session_state.dart';

/// Driver Authentication & Registration Screen (Dark Automotive Cockpit Style).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Controllers
  final TextEditingController _nameController =
      TextEditingController(text: 'Димаш');
  final TextEditingController _emailController =
      TextEditingController(text: 'driver@antisleep.kz');
  final TextEditingController _passwordController =
      TextEditingController(text: '123456');
  final TextEditingController _carPlateController =
      TextEditingController(text: '777 AAA 02');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _carPlateController.dispose();
    super.dispose();
  }

  Future<void> _handleGuestLogin() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await appState.loginAsGuest();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleSubmit() async {
    HapticFeedback.lightImpact();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (email.isEmpty) {
      _showError(appState.t('labelEmail'));
      return;
    }
    if (password.length < 4) {
      _showError(
        appState.lang == 'kk'
            ? 'Құпиясөз тым қысқа (кемінде 4 таңба)'
            : 'Пароль слишком короткий (минимум 4 символа)',
      );
      return;
    }

    setState(() => _isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));

    if (_isSignUp) {
      await appState.register(
        name: _nameController.text.trim(),
        emailOrPhone: email,
        password: password,
        carPlate: _carPlateController.text.trim(),
        language: appState.lang,
      );
    } else {
      await appState.login(
        emailOrPhone: email,
        password: password,
      );
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF5252),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String lang = appState.lang;

    return Scaffold(
      backgroundColor: CockpitColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Top Brand Header & Language Switcher
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: CockpitColors.safeGreen.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CockpitColors.safeGreen.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.radar_rounded,
                              color: CockpitColors.safeGreen,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'AntiSleep AI',
                                style: TextStyle(
                                  color: CockpitColors.textWhite,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              Text(
                                'DRIVER SAFETY SYSTEM',
                                style: TextStyle(
                                  color: CockpitColors.safeGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Language Selector Pill
                      _buildLangSwitcher(),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Welcome Card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: CockpitColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: CockpitColors.cardBorder),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // Auth Mode Toggle (Login vs Register)
                        _buildModeToggle(),
                        const SizedBox(height: 22),

                        // Form Fields
                        if (_isSignUp) ...<Widget>[
                          _buildFieldLabel(appState.t('labelName'), Icons.person_rounded),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _nameController,
                            hint: appState.t('hintName'),
                            icon: Icons.badge_rounded,
                          ),
                          const SizedBox(height: 14),

                          _buildFieldLabel(appState.t('labelCarPlate'), Icons.directions_car_rounded),
                          const SizedBox(height: 6),
                          _buildCarPlateField(),
                          const SizedBox(height: 14),
                        ],

                        _buildFieldLabel(appState.t('labelEmail'), Icons.alternate_email_rounded),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _emailController,
                          hint: appState.t('hintEmail'),
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),

                        _buildFieldLabel(appState.t('labelPassword'), Icons.lock_outline_rounded),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _passwordController,
                          hint: '••••••••',
                          icon: Icons.key_rounded,
                          isPassword: true,
                        ),
                        const SizedBox(height: 22),

                        // Submit Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CockpitColors.safeGreen,
                            foregroundColor: const Color(0xFF041E0F),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF041E0F),
                                    ),
                                  ),
                                )
                              : Text(
                                  _isSignUp
                                      ? appState.t('btnRegister')
                                      : appState.t('btnLogin'),
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),

                        // OR Divider
                        Row(
                          children: <Widget>[
                            const Expanded(child: Divider(color: CockpitColors.cardBorder)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                lang == 'kk' ? 'НЕМЕСЕ' : (lang == 'ru' ? 'ИЛИ' : 'OR'),
                                style: const TextStyle(
                                  color: CockpitColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: CockpitColors.cardBorder)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Quick Demo / Guest Button (Essential for Project Defense)
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleGuestLogin,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: BorderSide(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                              width: 1.3,
                            ),
                            backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.bolt_rounded, size: 20),
                          label: Text(
                            appState.t('btnGuest'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appState.t('guestNotice'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CockpitColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom Protection Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: CockpitColors.safeGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        lang == 'kk'
                            ? 'Деректер құрылғыда жергілікті қорғалған'
                            : (lang == 'ru'
                                ? 'Данные биометрии защищены локально на устройстве'
                                : 'Biometric data processed 100% locally on device'),
                        style: const TextStyle(
                          color: CockpitColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CockpitColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CockpitColors.cardBorder),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildToggleItem(
              title: appState.t('tabLogin'),
              isSelected: !_isSignUp,
              onTap: () => setState(() => _isSignUp = false),
            ),
          ),
          Expanded(
            child: _buildToggleItem(
              title: appState.t('tabRegister'),
              isSelected: _isSignUp,
              onTap: () => setState(() => _isSignUp = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? CockpitColors.safeGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFF041E0F) : CockpitColors.textMuted,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, IconData icon) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: CockpitColors.safeGreen),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: CockpitColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: CockpitColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CockpitColors.cardBorder),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: CockpitColors.textWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: CockpitColors.textMuted,
            fontSize: 13,
          ),
          prefixIcon: Icon(icon, color: CockpitColors.textMuted, size: 18),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: CockpitColors.textMuted,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCarPlateField() {
    return Container(
      decoration: BoxDecoration(
        color: CockpitColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CockpitColors.cardBorder),
      ),
      child: Row(
        children: <Widget>[
          // Kazakh Flag Badge simulation for Car Plate
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF007799),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(11),
                bottomLeft: Radius.circular(11),
              ),
            ),
            child: const Text(
              'KZ',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _carPlateController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: CockpitColors.textWhite,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                hintText: appState.t('hintCarPlate'),
                hintStyle: const TextStyle(
                  color: CockpitColors.textMuted,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLangSwitcher() {
    return Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? CockpitColors.safeGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                code.toUpperCase(),
                style: TextStyle(
                  color: selected ? const Color(0xFF041E0F) : CockpitColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

