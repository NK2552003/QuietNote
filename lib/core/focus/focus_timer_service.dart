import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/audio/ambient_audio_service.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/flutter-ui/components/ui_common.dart';
import 'package:quietnote/core/flutter-ui/components/ui_toast.dart';
import 'package:quietnote/core/focus/floating_bubble_service.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/clock/focus_preset.dart';

class FocusTimerService {
  FocusTimerService._();
  static final FocusTimerService _instance = FocusTimerService._();
  factory FocusTimerService() => _instance;

  bool _isHandlingExpiry = false;

  /// Starts a new focus session and synchronizes all global app state & notifications.
  Future<void> startSession(
    WidgetRef ref, {
    required int workMinutes,
    int? breakMinutes,
    FocusPreset? preset,
    String? courseId,
    String? taskId,
    String? habitId,
    String? linkedTitle,
  }) async {
    final now = DateTime.now();
    final scheduled = now.add(Duration(minutes: workMinutes));
    final int effectiveBreakMinutes = breakMinutes ?? (preset?.config?.brk ?? 5);

    await ref.read(focusSessionRepositoryProvider).start(
          minutes: workMinutes,
          endsAt: scheduled,
          presetId: preset?.name,
          courseId: courseId,
          taskId: taskId,
          habitId: habitId,
        );

    await ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            focusSessionEndsAt: scheduled,
            focusSessionStartedAt: now,
            focusSessionPhase: 'work',
            focusSessionIntervalMinutes: workMinutes,
            focusSessionBreakMinutes: effectiveBreakMinutes,
            lastUsedPresetId: preset?.name,
          ),
        );

    unawaited(NotificationService().showFocusTimerStatus(
      scheduled,
      phase: 'work',
      presetLabel: preset?.chipLabel ?? '$workMinutes min',
      linkedTitle: linkedTitle,
    ));

    unawaited(NotificationService().scheduleReminder(
      NotificationService.focusStatusNotificationId,
      'Focus timer complete',
      'Your $workMinutes-minute focus session is complete.',
      scheduled,
      feature: NotificationFeature.focus,
    ));

    final settings = ref.read(settingsProvider).value;
    if (settings?.floatingFocusBubbleEnabled ?? true) {
      unawaited(FloatingBubblePlatformService().showBubble(
        endsAt: scheduled,
        totalSeconds: workMinutes * 60,
        phase: 'work',
        label: preset?.chipLabel ?? '$workMinutes min',
      ));
    }
  }

  /// Extends the active session by [extraMinutes] without altering original start time.
  Future<void> extendSession(
    WidgetRef ref, {
    required int extraMinutes,
    BuildContext? context,
  }) async {
    final settings = ref.read(settingsProvider).value;
    final currentEnd = settings?.focusSessionEndsAt ?? DateTime.now();
    final newEnd = currentEnd.add(Duration(minutes: extraMinutes));
    final phase = settings?.focusSessionPhase ?? 'work';

    await ref.read(focusSessionRepositoryProvider).extendActive(endsAt: newEnd);

    await ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(focusSessionEndsAt: newEnd),
        );

    final activeSession = ref.read(activeFocusSessionProvider).value;
    final preset = focusPresetFromId(activeSession?.presetId);

    unawaited(NotificationService().showFocusTimerStatus(
      newEnd,
      phase: phase,
      presetLabel: preset?.chipLabel,
    ));

    if (settings?.floatingFocusBubbleEnabled ?? true) {
      unawaited(FloatingBubblePlatformService().updateBubble(
        endsAt: newEnd,
        totalSeconds: (settings?.focusSessionIntervalMinutes ?? 25) * 60 + extraMinutes * 60,
        phase: phase,
        label: preset?.chipLabel ?? 'Focus',
      ));
    }

    if (context != null && context.mounted) {
      UiToast.show(
        context,
        title: 'Extended by +$extraMinutes min',
        message: 'Timer now ends at ${newEnd.hour.toString().padLeft(2, '0')}:${newEnd.minute.toString().padLeft(2, '0')}.',
        intent: UiIntent.primary,
        icon: Icons.more_time_rounded,
      );
    }
  }

  /// Handles when a timer interval reaches 0:00.
  /// Automatically transitions between work <-> break phases, increments Pomodoro cycles,
  /// triggers audio alarms, updates notifications, and completes sessions properly.
  Future<void> handleTimerExpiry(
    WidgetRef ref, {
    BuildContext? context,
  }) async {
    if (_isHandlingExpiry) return;
    _isHandlingExpiry = true;

    try {
      final settings = ref.read(settingsProvider).value ?? const AppSettings();
      if (settings.focusAlarmSound != 'none') {
        unawaited(AmbientAudioService().playAlarmSound(settings.focusAlarmSound));
      }

      final activeSession = ref.read(activeFocusSessionProvider).value;
      final preset = focusPresetFromId(activeSession?.presetId);
      final currentPhase = settings.focusSessionPhase;

      int breakMinutes = settings.focusSessionBreakMinutes;
      if (breakMinutes <= 0 && preset != null && preset.config != null) {
        breakMinutes = preset.config!.brk;
      }

      final now = DateTime.now();

      if (currentPhase == 'work' && breakMinutes > 0) {
        // Transition from WORK -> BREAK
        final breakEnd = now.add(Duration(minutes: breakMinutes));

        await ref.read(focusSessionRepositoryProvider).extendActive(endsAt: breakEnd);

        await ref.read(settingsProvider.notifier).update(
              (s) => s.copyWith(
                focusSessionEndsAt: breakEnd,
                focusSessionStartedAt: now,
                focusSessionPhase: 'break',
                focusSessionIntervalMinutes: breakMinutes,
                focusSessionBreakMinutes: breakMinutes,
              ),
            );

        unawaited(NotificationService().showFocusTimerStatus(
          breakEnd,
          phase: 'break',
          presetLabel: preset?.chipLabel ?? 'Break',
        ));

        unawaited(NotificationService().scheduleReminder(
          NotificationService.focusStatusNotificationId,
          'Break complete',
          'Your $breakMinutes-minute break is complete. Ready for deep work?',
          breakEnd,
          feature: NotificationFeature.focus,
        ));

        if (settings.floatingFocusBubbleEnabled) {
          unawaited(FloatingBubblePlatformService().updateBubble(
            endsAt: breakEnd,
            totalSeconds: breakMinutes * 60,
            phase: 'break',
            label: 'Break',
          ));
        }

        if (context != null && context.mounted) {
          UiToast.show(
            context,
            title: 'Break time ($breakMinutes min)',
            message: 'Time to rest, stretch and re-energize!',
            intent: UiIntent.warning,
            icon: Icons.local_cafe_outlined,
          );
        }
      } else if (currentPhase == 'break') {
        // BREAK -> WORK transition
        await ref.read(focusSessionRepositoryProvider).incrementCycle();

        final workMinutes = (preset != null && preset.config != null)
            ? preset.config!.work
            : (settings.focusSessionIntervalMinutes > 0
                ? settings.focusSessionIntervalMinutes
                : 25);
        final nextWorkEnd = now.add(Duration(minutes: workMinutes));

        await ref.read(focusSessionRepositoryProvider).extendActive(endsAt: nextWorkEnd);

        await ref.read(settingsProvider.notifier).update(
              (s) => s.copyWith(
                focusSessionEndsAt: nextWorkEnd,
                focusSessionStartedAt: now,
                focusSessionPhase: 'work',
                focusSessionIntervalMinutes: workMinutes,
                focusSessionBreakMinutes: breakMinutes,
              ),
            );

        unawaited(NotificationService().showFocusTimerStatus(
          nextWorkEnd,
          phase: 'work',
          presetLabel: preset?.chipLabel ?? '$workMinutes min',
        ));

        unawaited(NotificationService().scheduleReminder(
          NotificationService.focusStatusNotificationId,
          'Focus timer complete',
          'Your $workMinutes-minute focus session is complete.',
          nextWorkEnd,
          feature: NotificationFeature.focus,
        ));

        if (settings.floatingFocusBubbleEnabled) {
          unawaited(FloatingBubblePlatformService().updateBubble(
            endsAt: nextWorkEnd,
            totalSeconds: workMinutes * 60,
            phase: 'work',
            label: preset?.chipLabel ?? '$workMinutes min',
          ));
        }

        if (context != null && context.mounted) {
          UiToast.show(
            context,
            title: 'Focus cycle started ($workMinutes min)',
            message: 'Break complete. Let\'s get back to deep work!',
            intent: UiIntent.primary,
            icon: Icons.auto_awesome,
          );
        }
      } else {
        // No break configured or user finished session
        await finishSession(ref, cancelled: false);
        if (context != null && context.mounted) {
          UiToast.show(
            context,
            title: 'Focus session complete!',
            message: 'Great job completing your deep work session.',
            intent: UiIntent.success,
            icon: Icons.check_circle_rounded,
          );
        }
      }
    } finally {
      _isHandlingExpiry = false;
    }
  }

  /// Ends break early and starts the next work cycle immediately.
  Future<void> skipBreakAndStartWork(
    WidgetRef ref, {
    BuildContext? context,
  }) async {
    await AmbientAudioService().stopAlarm();
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final activeSession = ref.read(activeFocusSessionProvider).value;
    final preset = focusPresetFromId(activeSession?.presetId);
    final now = DateTime.now();

    await ref.read(focusSessionRepositoryProvider).incrementCycle();

    final workMinutes = (preset != null && preset.config != null)
        ? preset.config!.work
        : (settings.focusSessionIntervalMinutes > 0
            ? settings.focusSessionIntervalMinutes
            : 25);
    final nextWorkEnd = now.add(Duration(minutes: workMinutes));

    await ref.read(focusSessionRepositoryProvider).extendActive(endsAt: nextWorkEnd);

    await ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            focusSessionEndsAt: nextWorkEnd,
            focusSessionStartedAt: now,
            focusSessionPhase: 'work',
            focusSessionIntervalMinutes: workMinutes,
          ),
        );

    unawaited(NotificationService().showFocusTimerStatus(
      nextWorkEnd,
      phase: 'work',
      presetLabel: preset?.chipLabel ?? '$workMinutes min',
    ));

    if (settings.floatingFocusBubbleEnabled) {
      unawaited(FloatingBubblePlatformService().updateBubble(
        endsAt: nextWorkEnd,
        totalSeconds: workMinutes * 60,
        phase: 'work',
        label: preset?.chipLabel ?? '$workMinutes min',
      ));
    }

    if (context != null && context.mounted) {
      UiToast.show(
        context,
        title: 'Focus cycle started ($workMinutes min)',
        message: 'Break ended. Ready for deep concentration!',
        intent: UiIntent.primary,
        icon: Icons.timer_outlined,
      );
    }
  }

  /// Ends the active session, updating DB history and clearing runtime triggers.
  Future<void> finishSession(
    WidgetRef ref, {
    bool? cancelled,
    String? reflection,
  }) async {
    await AmbientAudioService().stopAlarm();
    await NotificationService().clearFocusTimerStatus();
    unawaited(FloatingBubblePlatformService().hideBubble());

    await ref.read(focusSessionRepositoryProvider).finishActive(
          cancelled: cancelled,
          reflection: reflection,
        );

    await ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(clearFocusSession: true),
        );
  }
}
