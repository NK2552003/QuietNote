import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/security/app_lock_controller.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';

/// Wraps the root Navigator. When App Lock is enabled and active, presents
/// [AppLockScreen] over the app with a frosted blur backdrop and smooth unlock reveal.
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
        if (showLock)
          const AppLockScreen(key: ValueKey('active_app_lock_screen')),
      ],
    );
  }
}

/// The full-screen lock overlay with frosted glass blur, pulse aura, and
/// smooth sliding window reveal transition upon device biometric / screen lock authentication.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen>
    with TickerProviderStateMixin {
  bool _isUnlocking = false;
  bool _hasAutoPrompted = false;
  String _biometricLabel = 'Biometrics & Screen Lock';

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
      duration: const Duration(milliseconds: 500),
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

    _logoScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _textSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
      ),
    );

    _contentSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _contentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.85, curve: Curves.easeOut),
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
      duration: const Duration(milliseconds: 360),
    );

    _exitSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0), // Smooth slide to the right
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

    _exitScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _entranceController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAndAutoPrompt();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _exitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initAndAutoPrompt() async {
    final service = ref.read(biometricServiceProvider);
    final label = await service.getBiometricLabel();

    if (mounted) {
      setState(() {
        _biometricLabel = label;
      });
    }

    if (!_hasAutoPrompted && mounted) {
      _hasAutoPrompted = true;
      // Slight delay to ensure Flutter frame rendering completes smoothly before OS dialog appears
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _triggerBiometricAuth();
    }
  }

  Future<void> _triggerBiometricAuth() async {
    if (_isUnlocking) return;

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

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lockState = ref.watch(appLockProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    final Color glassTint = isDark
        ? const Color(0xFF100F0E).withValues(alpha: 0.94)
        : const Color(0xFFFAF8F5).withValues(alpha: 0.95);

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
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            children: [
                              const Spacer(flex: 3),

                              // 1. Glowing Security / QuietNote Mark
                              ScaleTransition(
                                scale: _logoScaleAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: GestureDetector(
                                    onTap: (lockState.isAuthenticating ||
                                            _isUnlocking)
                                        ? null
                                        : _triggerBiometricAuth,
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: settings.accent.swatch.withValues(
                                            alpha: 0.10 + 0.06 * pulseVal),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: settings.accent.swatch
                                              .withValues(
                                                  alpha: 0.24 +
                                                      0.18 * pulseVal),
                                          width: 2.0,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: settings.accent.swatch
                                                .withValues(
                                              alpha: 0.15 + 0.15 * pulseVal,
                                            ),
                                            blurRadius: 28 + 14 * pulseVal,
                                            spreadRadius: 3 + 4 * pulseVal,
                                          ),
                                        ],
                                      ),
                                      child: const QuietNoteMark(size: 64),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 28),

                              // 2. Title and Description
                              SlideTransition(
                                position: _textSlideAnimation,
                                child: FadeTransition(
                                  opacity: _textFadeAnimation,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'QuietNote is Protected',
                                        textAlign: TextAlign.center,
                                        style: context.uiText.title.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 23,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Use your fingerprint, face, or device screen lock to continue',
                                        textAlign: TextAlign.center,
                                        style: context.uiText.body.copyWith(
                                          color: theme.colors.foregroundMuted,
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // 3. Error Banner (if any)
                              if (lockState.errorMessage != null &&
                                  lockState.errorMessage!.isNotEmpty) ...[
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: theme.colors.destructive
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: theme.colors.destructive
                                          .withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 16,
                                        color: theme.colors.destructive,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          lockState.errorMessage!,
                                          textAlign: TextAlign.center,
                                          style:
                                              context.uiText.caption.copyWith(
                                            color: theme.colors.destructive,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const Spacer(flex: 2),

                              // 4. Primary Unlock Action Button
                              SlideTransition(
                                position: _contentSlideAnimation,
                                child: FadeTransition(
                                  opacity: _contentFadeAnimation,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        constraints:
                                            const BoxConstraints(maxWidth: 300),
                                        height: 52,
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              (lockState.isAuthenticating ||
                                                      _isUnlocking)
                                                  ? null
                                                  : _triggerBiometricAuth,
                                          icon: lockState.isAuthenticating
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.lock_open_rounded,
                                                  size: 20),
                                          label: Text(
                                            lockState.isAuthenticating
                                                ? 'Authenticating…'
                                                : 'Unlock QuietNote',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                settings.accent.swatch,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            elevation: 0,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.shield_outlined,
                                            size: 13,
                                            color: theme.colors.foregroundMuted
                                                .withValues(alpha: 0.7),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Secured by $_biometricLabel',
                                            style:
                                                context.uiText.caption.copyWith(
                                              color:
                                                  theme.colors.foregroundMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
}
