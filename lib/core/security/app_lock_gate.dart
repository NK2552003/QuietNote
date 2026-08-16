import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/security/app_lock_controller.dart';
import 'package:quietnote/core/security/widgets/pin_dots_indicator.dart';
import 'package:quietnote/core/security/widgets/pin_keypad.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';

/// Wraps the root Navigator. When App Lock is enabled and active, presents
/// [AppLockScreen] with an animated blur backdrop and staggered reveal effect.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final lockState = ref.watch(appLockProvider);

    final bool showLock = settings.appLockEnabled &&
        (!lockState.hasUnlockedThisSession || lockState.isLocked);

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          reverseDuration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: showLock
              ? Positioned.fill(
                  key: const ValueKey('active_app_lock_screen'),
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => const AppLockScreen(),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('unlocked_empty_gate')),
        ),
      ],
    );
  }
}

/// The full-screen lock interface with frosted glass blur, pulse aura, and
/// smooth sliding window reveal transition upon correct passcode / biometric entry.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen>
    with TickerProviderStateMixin {
  static const int _pinLength = 4;
  String _enteredPin = '';
  bool _hasError = false;
  bool _isUnlocking = false;
  bool _deviceHasBiometrics = false;

  late final AnimationController _entranceController;
  late final AnimationController _exitController;
  late final AnimationController _pulseController;

  late final Animation<double> _blurAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<Offset> _textSlideAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<Offset> _contentSlideAnimation;
  late final Animation<double> _contentFadeAnimation;

  late final Animation<Offset> _exitSlideAnimation;
  late final Animation<double> _exitFadeAnimation;
  late final Animation<double> _exitScaleAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Entrance staggered animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _blurAnimation = Tween<double>(begin: 0.0, end: 24.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _textSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.7, curve: Curves.easeOut),
      ),
    );

    _contentSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    _contentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
      ),
    );

    // 2. Continuous breathing aura for lock badge
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // 3. Unlock exit slide-window animation
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _exitSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0), // Smooth slide to the right like a window curtain!
    ).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: Curves.easeInOutCubicEmphasized,
      ),
    );

    _exitFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _exitScaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _entranceController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBiometricsAndAutoPrompt();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _exitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricsAndAutoPrompt() async {
    final service = ref.read(biometricServiceProvider);
    final isSupported = await service.isDeviceSupported();
    final biometrics = await service.getAvailableBiometrics();
    final isEnrolled = await service.isBiometricsEnrolled();

    final bool deviceHasBiometrics =
        isSupported && isEnrolled && biometrics.isNotEmpty;

    if (!mounted) return;
    setState(() {
      _deviceHasBiometrics = deviceHasBiometrics;
    });

    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final lockState = ref.read(appLockProvider);

    // Only auto-trigger biometric prompt if device has biometrics AND enabled in settings
    if (deviceHasBiometrics &&
        settings.appLockBiometricsEnabled &&
        !lockState.showPinFallback) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _triggerBiometricAuth();
    }
  }

  Future<void> _triggerBiometricAuth() async {
    final success = await ref
        .read(appLockProvider.notifier)
        .authenticateBiometric(autoUnlock: false);

    if (success && mounted) {
      _performUnlockTransition();
    }
  }

  Future<void> _performUnlockTransition() async {
    if (_isUnlocking) return;
    setState(() {
      _isUnlocking = true;
    });
    HapticFeedback.lightImpact();

    await _exitController.forward();
    if (mounted) {
      ref.read(appLockProvider.notifier).unlock();
    }
  }

  void _onDigitPressed(String digit) {
    if (_isUnlocking) return;
    if (_enteredPin.length >= _pinLength) return;

    if (_hasError) {
      setState(() => _hasError = false);
      ref.read(appLockProvider.notifier).clearErrorMessage();
    }

    setState(() {
      _enteredPin += digit;
    });

    if (_enteredPin.length == _pinLength) {
      final isCorrect =
          ref.read(appLockProvider.notifier).isPinCorrect(_enteredPin);

      if (isCorrect) {
        _performUnlockTransition();
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _hasError = true;
          _enteredPin = '';
        });
        ref
            .read(appLockProvider.notifier)
            .setErrorMessage('Incorrect PIN. Please try again.');
      }
    }
  }

  void _onBackspacePressed() {
    if (_isUnlocking) return;
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _hasError = false;
      });
      ref.read(appLockProvider.notifier).clearErrorMessage();
    }
  }

  void _onClearAll() {
    if (_isUnlocking) return;
    setState(() {
      _enteredPin = '';
      _hasError = false;
    });
    ref.read(appLockProvider.notifier).clearErrorMessage();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lockState = ref.watch(appLockProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final bool hasPin = settings.appLockCustomPin.isNotEmpty;

    // Determine whether to show PIN keypad or Biometrics screen:
    // If device doesn't support biometrics, always show PIN keypad.
    // If biometrics is enabled and device has biometrics, DO NOT display keypad by default.
    final bool biometricsActive =
        _deviceHasBiometrics && settings.appLockBiometricsEnabled;
    final bool showPinMode = !biometricsActive || lockState.showPinFallback;

    final Color glassTint = isDark
        ? const Color(0xFF121110).withValues(alpha: 0.90)
        : const Color(0xFFFAF8F5).withValues(alpha: 0.92);

    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _entranceController,
            _pulseController,
            _exitController,
          ]),
          builder: (context, child) {
            final double blurVal =
                _blurAnimation.value * (1.0 - _exitController.value);
            final double pulseVal =
                0.5 + 0.5 * sin(_pulseController.value * 2 * pi);

            return SlideTransition(
              position: _exitSlideAnimation,
              child: FadeTransition(
                opacity: _exitFadeAnimation,
                child: ScaleTransition(
                  scale: _exitScaleAnimation,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blurVal, sigmaY: blurVal),
                    child: Container(
                      color: glassTint,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              const Spacer(flex: 2),

                              // 1. Branding Badge with breathing radiant aura
                              ScaleTransition(
                                scale: _logoScaleAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: settings.accent.swatch.withValues(
                                          alpha: 0.12 + 0.06 * pulseVal),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: settings.accent.swatch.withValues(
                                            alpha: 0.28 + 0.18 * pulseVal),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: settings.accent.swatch
                                              .withValues(
                                            alpha: 0.16 + 0.14 * pulseVal,
                                          ),
                                          blurRadius: 20 + 16 * pulseVal,
                                          spreadRadius: 2 + 4 * pulseVal,
                                        ),
                                      ],
                                    ),
                                    child: const QuietNoteMark(size: 56),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // 2. Animated Title & Subtitle
                              SlideTransition(
                                position: _textSlideAnimation,
                                child: FadeTransition(
                                  opacity: _textFadeAnimation,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        showPinMode
                                            ? 'Enter Passcode'
                                            : 'QuietNote Locked',
                                        style: context.uiText.title.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 22,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        showPinMode
                                            ? 'Enter your 4-digit PIN to continue'
                                            : 'Unlock using biometric authentication',
                                        textAlign: TextAlign.center,
                                        style: context.uiText.caption.copyWith(
                                          color: theme.colors.foregroundMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Error message banner
                              if (lockState.errorMessage != null &&
                                  lockState.errorMessage!.isNotEmpty) ...[
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: theme.colors.destructive
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colors.destructive
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    lockState.errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: context.uiText.caption.copyWith(
                                      color: theme.colors.destructive,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],

                              const Spacer(flex: 1),

                              // 3. Animated PIN Dots & Keypad OR Biometric Scanner
                              SlideTransition(
                                position: _contentSlideAnimation,
                                child: FadeTransition(
                                  opacity: _contentFadeAnimation,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    child: showPinMode
                                        ? _buildPinMode(
                                            context,
                                            settings,
                                            biometricsActive,
                                          )
                                        : _buildBiometricMode(
                                            context,
                                            settings,
                                            hasPin,
                                            lockState,
                                          ),
                                  ),
                                ),
                              ),

                              const Spacer(flex: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPinMode(
    BuildContext context,
    AppSettings settings,
    bool biometricsActive,
  ) {
    return Column(
      key: const ValueKey('pin_keypad_mode'),
      mainAxisSize: MainAxisSize.min,
      children: [
        PinDotsIndicator(
          pinLength: _pinLength,
          enteredLength: _enteredPin.length,
          accentColor: settings.accent.swatch,
          hasError: _hasError,
        ),
        const SizedBox(height: 24),
        PinKeypad(
          onDigitPressed: _onDigitPressed,
          onBackspacePressed: _onBackspacePressed,
          onBackspaceLongPressed: _onClearAll,
          enabled: !_isUnlocking,
          leftAccessory: biometricsActive
              ? InkResponse(
                  radius: 28,
                  onTap: _isUnlocking
                      ? null
                      : () {
                          ref
                              .read(appLockProvider.notifier)
                              .togglePinFallback(false);
                          _triggerBiometricAuth();
                        },
                  child: Icon(
                    Icons.fingerprint_rounded,
                    color: settings.accent.swatch,
                    size: 28,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildBiometricMode(
    BuildContext context,
    AppSettings settings,
    bool hasPin,
    AppLockState lockState,
  ) {
    return Column(
      key: const ValueKey('biometric_mode'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Biometric Sensor Button with pulse glow
        GestureDetector(
          onTap: (lockState.isAuthenticating || _isUnlocking)
              ? null
              : _triggerBiometricAuth,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: settings.accent.swatch.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: settings.accent.swatch.withValues(alpha: 0.35),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: settings.accent.swatch.withValues(alpha: 0.22),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.fingerprint_rounded,
              size: 52,
              color: settings.accent.swatch,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Primary Unlock Button
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 280),
          height: 48,
          child: ElevatedButton.icon(
            onPressed: (lockState.isAuthenticating || _isUnlocking)
                ? null
                : _triggerBiometricAuth,
            icon: lockState.isAuthenticating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_open_rounded, size: 18),
            label: Text(
              lockState.isAuthenticating
                  ? 'Authenticating…'
                  : 'Unlock with Biometrics',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: settings.accent.swatch,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Secondary Option: Enter PIN
        if (hasPin)
          TextButton.icon(
            onPressed: _isUnlocking
                ? null
                : () {
                    setState(() => _enteredPin = '');
                    ref.read(appLockProvider.notifier).togglePinFallback(true);
                  },
            icon: const Icon(Icons.pin_outlined, size: 18),
            label: const Text('Use PIN Passcode'),
            style: TextButton.styleFrom(
              foregroundColor: context.ui.colors.foregroundMuted,
            ),
          ),
      ],
    );
  }
}
