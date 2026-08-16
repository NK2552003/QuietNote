import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/security/biometric_auth_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';

final biometricServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService();
});

class AppLockState {
  const AppLockState({
    this.isLocked = true,
    this.hasUnlockedThisSession = false,
    this.isAuthenticating = false,
    this.pausedAt,
    this.errorMessage,
    this.showPinFallback = false,
  });

  final bool isLocked;
  final bool hasUnlockedThisSession;
  final bool isAuthenticating;
  final DateTime? pausedAt;
  final String? errorMessage;
  final bool showPinFallback;

  AppLockState copyWith({
    bool? isLocked,
    bool? hasUnlockedThisSession,
    bool? isAuthenticating,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    String? errorMessage,
    bool clearError = false,
    bool? showPinFallback,
  }) {
    return AppLockState(
      isLocked: isLocked ?? this.isLocked,
      hasUnlockedThisSession:
          hasUnlockedThisSession ?? this.hasUnlockedThisSession,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      showPinFallback: showPinFallback ?? this.showPinFallback,
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier(this.ref) : super(const AppLockState(isLocked: true)) {
    _init();
  }

  final Ref ref;

  void _init() {
    // Listen to settings changes and sync initial lock state
    ref.listen<AsyncValue<AppSettings>>(
      settingsProvider,
      (previous, next) {
        final settings = next.value;
        if (settings != null) {
          if (!settings.appLockEnabled) {
            state = state.copyWith(
              isLocked: false,
              hasUnlockedThisSession: true,
              clearError: true,
            );
          } else {
            // App lock enabled: if not unlocked yet this session, lock it
            if (!state.hasUnlockedThisSession) {
              final bool hasPin = settings.appLockCustomPin.trim().isNotEmpty;
              state = state.copyWith(
                isLocked: true,
                showPinFallback: !settings.appLockBiometricsEnabled && hasPin,
              );
            }
          }
        }
      },
      fireImmediately: true,
    );
  }

  void lock() {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final bool hasPin = settings.appLockCustomPin.trim().isNotEmpty;
    state = state.copyWith(
      isLocked: true,
      hasUnlockedThisSession: false,
      clearError: true,
      clearPausedAt: true,
      showPinFallback: !settings.appLockBiometricsEnabled && hasPin,
    );
  }

  void unlock() {
    HapticFeedback.lightImpact();
    state = state.copyWith(
      isLocked: false,
      hasUnlockedThisSession: true,
      isAuthenticating: false,
      clearError: true,
      clearPausedAt: true,
      showPinFallback: false,
    );
  }

  void togglePinFallback(bool show) {
    state = state.copyWith(showPinFallback: show, clearError: true);
  }

  bool isPinCorrect(String enteredPin) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final savedPin = settings.appLockCustomPin.trim();
    if (savedPin.isEmpty) return false;
    return enteredPin.trim() == savedPin;
  }

  void setErrorMessage(String message) {
    state = state.copyWith(errorMessage: message);
  }

  void clearErrorMessage() {
    state = state.copyWith(clearError: true);
  }

  Future<bool> authenticateBiometric({
    String reason = 'Unlock QuietNote',
    bool autoUnlock = true,
  }) async {
    if (state.isAuthenticating) return false;
    state = state.copyWith(isAuthenticating: true, clearError: true);
    try {
      final biometric = ref.read(biometricServiceProvider);
      final BiometricAuthResult result =
          await biometric.authenticateDetailed(
        localizedReason: reason,
        biometricOnly: false,
      );

      if (result.success) {
        state = state.copyWith(isAuthenticating: false, clearError: true);
        if (autoUnlock) {
          unlock();
        }
        return true;
      } else if (result.notEnrolled || result.notAvailable) {
        final settings =
            ref.read(settingsProvider).value ?? const AppSettings();
        state = state.copyWith(
          isAuthenticating: false,
          showPinFallback: settings.appLockCustomPin.isNotEmpty,
          errorMessage: settings.appLockCustomPin.isNotEmpty
              ? 'Biometrics not configured on device. Enter your PIN.'
              : 'Biometrics not enrolled. Set a fallback PIN in Settings.',
        );
        return false;
      } else if (result.userCanceled) {
        state = state.copyWith(isAuthenticating: false, clearError: true);
        return false;
      } else {
        HapticFeedback.mediumImpact();
        state = state.copyWith(
          isAuthenticating: false,
          errorMessage: result.errorMessage ?? 'Authentication failed.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isAuthenticating: false,
        errorMessage: 'Authentication error: $e',
      );
      return false;
    }
  }

  bool verifyPin(String enteredPin) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final savedPin = settings.appLockCustomPin.trim();

    if (savedPin.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No fallback PIN is configured. Use biometric unlock.',
      );
      HapticFeedback.vibrate();
      return false;
    }

    if (enteredPin.trim() == savedPin) {
      unlock();
      return true;
    } else {
      HapticFeedback.vibrate();
      state = state.copyWith(errorMessage: 'Incorrect PIN. Please try again.');
      return false;
    }
  }

  void onAppPaused() {
    // When biometric prompt or system dialog opens, don't treat as user leaving app
    if (state.isAuthenticating) return;
    if (state.pausedAt == null) {
      state = state.copyWith(pausedAt: DateTime.now());
    }
  }

  void onAppResumed() {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    if (!settings.appLockEnabled) {
      if (state.isLocked) {
        unlock();
      }
      return;
    }

    if (state.isAuthenticating) {
      return;
    }

    // If never unlocked this session, lock immediately
    if (!state.hasUnlockedThisSession) {
      lock();
      return;
    }

    if (state.isLocked) {
      return;
    }

    final pausedAt = state.pausedAt;
    if (pausedAt == null) {
      // If immediate timeout is configured or pause timestamp was lost, lock
      if (settings.appLockTimeoutSeconds == 0) {
        lock();
      }
      return;
    }

    final int timeoutSec = settings.appLockTimeoutSeconds;
    final int elapsedSec = DateTime.now().difference(pausedAt).inSeconds;

    if (timeoutSec == 0 || elapsedSec >= timeoutSec) {
      lock();
    } else {
      // Resumed before timeout expired; clear pause timestamp and keep unlocked
      state = state.copyWith(clearPausedAt: true);
    }
  }
}

final appLockProvider =
    StateNotifierProvider<AppLockNotifier, AppLockState>((ref) {
  return AppLockNotifier(ref);
});
