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
    this.deviceSupported = true,
  });

  final bool isLocked;
  final bool hasUnlockedThisSession;
  final bool isAuthenticating;
  final DateTime? pausedAt;
  final String? errorMessage;
  final bool deviceSupported;

  AppLockState copyWith({
    bool? isLocked,
    bool? hasUnlockedThisSession,
    bool? isAuthenticating,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    String? errorMessage,
    bool clearError = false,
    bool? deviceSupported,
  }) {
    return AppLockState(
      isLocked: isLocked ?? this.isLocked,
      hasUnlockedThisSession:
          hasUnlockedThisSession ?? this.hasUnlockedThisSession,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      deviceSupported: deviceSupported ?? this.deviceSupported,
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier(this.ref) : super(const AppLockState(isLocked: true)) {
    _init();
  }

  final Ref ref;

  void _init() {
    // Listen to settings changes and sync lock state
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
              state = state.copyWith(isLocked: true);
            }
          }
        }
      },
      fireImmediately: true,
    );
  }

  void lock() {
    state = state.copyWith(
      isLocked: true,
      hasUnlockedThisSession: false,
      clearError: true,
      clearPausedAt: true,
      isAuthenticating: false,
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
    );
  }

  void setErrorMessage(String message) {
    state = state.copyWith(errorMessage: message);
  }

  void clearErrorMessage() {
    state = state.copyWith(clearError: true);
  }

  /// Triggers native Android/iOS biometric & device screen lock (PIN/Pattern/Password) prompt.
  Future<bool> authenticateBiometric({
    String reason = 'Unlock QuietNote',
    bool autoUnlock = true,
  }) async {
    if (state.isAuthenticating) return false;
    state = state.copyWith(isAuthenticating: true, clearError: true);

    try {
      final biometric = ref.read(biometricServiceProvider);
      final BiometricAuthResult result = await biometric.authenticateDetailed(
        localizedReason: reason,
        biometricOnly: false, // Allows native Android PIN/Pattern/Password & Biometrics
      );

      if (result.success) {
        state = state.copyWith(isAuthenticating: false, clearError: true);
        if (autoUnlock) {
          unlock();
        }
        return true;
      } else if (result.notEnrolled || result.notAvailable) {
        state = state.copyWith(
          isAuthenticating: false,
          errorMessage:
              'No screen lock or biometric enrolled in device settings.',
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

  void onAppPaused() {
    // When biometric prompt or system dialog opens, do NOT treat as user leaving app.
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

    // When returning from system biometric dialog, do not re-lock.
    if (state.isAuthenticating) {
      return;
    }

    // If never unlocked this session, keep locked
    if (!state.hasUnlockedThisSession) {
      if (!state.isLocked) {
        lock();
      }
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
