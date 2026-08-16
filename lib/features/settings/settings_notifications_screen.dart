import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/audio/ambient_audio_service.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/focus/floating_bubble_service.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart' hide formatMinutes;
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Reminder switches for all 11 features, quiet hours, focus alarm chime picker,
/// and an interactive dynamic notification preview and testing hub.
class SettingsNotificationsScreen extends ConsumerStatefulWidget {
  const SettingsNotificationsScreen({super.key});

  @override
  ConsumerState<SettingsNotificationsScreen> createState() =>
      _SettingsNotificationsScreenState();
}

class _SettingsNotificationsScreenState
    extends ConsumerState<SettingsNotificationsScreen> {
  bool _sendingTest = false;
  NotificationFeature _selectedTestFeature = NotificationFeature.focus;
  bool _previewingAlarm = false;
  bool _overlayPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkOverlayPermission();
  }

  Future<void> _checkOverlayPermission() async {
    try {
      final granted = await FloatingBubblePlatformService().checkPermission();
      if (mounted) {
        setState(() => _overlayPermissionGranted = granted);
      }
    } catch (_) {}
  }

  Future<void> _requestOverlayPermission() async {
    HapticFeedback.selectionClick();
    try {
      await FloatingBubblePlatformService().requestPermission();
      final granted = await FloatingBubblePlatformService().checkPermission();
      if (mounted) {
        setState(() => _overlayPermissionGranted = granted);
        if (granted) {
          UiToast.show(
            context,
            title: 'Overlay permission granted',
            message: 'Floating focus timer bubble is now enabled.',
            intent: UiIntent.success,
            icon: Icons.check_circle_rounded,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _pickQuietTime(bool isStart, AppSettings settings) async {
    final int current = isStart
        ? settings.quietStartMinutes
        : settings.quietEndMinutes;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final int minutes = picked.hour * 60 + picked.minute;
    await ref
        .read(settingsProvider.notifier)
        .update(
          (AppSettings s) => isStart
              ? s.copyWith(quietStartMinutes: minutes)
              : s.copyWith(quietEndMinutes: minutes),
        );
  }

  Future<void> _previewAlarm(String alarmKey) async {
    HapticFeedback.selectionClick();
    if (_previewingAlarm) {
      await AmbientAudioService().stopAlarm();
      setState(() => _previewingAlarm = false);
      return;
    }
    setState(() => _previewingAlarm = true);
    await AmbientAudioService().previewAlarmSound(alarmKey);
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _previewingAlarm = false);
  }

  Future<void> _sendFeatureTest(NotificationFeature feature) async {
    setState(() => _sendingTest = true);
    HapticFeedback.lightImpact();
    try {
      await NotificationService().init();
      final ok = await NotificationService().showInstantNotification(
        999000 + feature.index,
        feature.sampleTitle,
        feature.sampleBody,
        feature: feature,
      );
      if (mounted) {
        if (ok) {
          UiToast.show(
            context,
            title: '${feature.label} notification sent',
            message: 'Check your notification bar to preview the icon and content.',
            intent: UiIntent.success,
            icon: feature.icon,
          );
        } else {
          UiToast.show(
            context,
            title: 'Could not send test notification',
            message: 'Notifications permission not granted in system settings.',
            intent: UiIntent.danger,
            icon: Icons.error_outline,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'Could not send test',
          message: '$e',
          intent: UiIntent.danger,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final bool on = settings.notificationsEnabled;

    return SettingsSubPage(
      title: 'Notifications & Alarms',
      subtitle: 'Dynamic alerts and smart nudges tailored to your routine.',
      children: <Widget>[
        UiCallout(
          title: on ? 'Smart Reminders Active' : 'All reminders are paused',
          message: on
              ? '${settings.activeReminderCount} of 10 notification channels enabled.'
              : 'Turn the master switch on to receive any reminder.',
          intent: on ? UiIntent.success : UiIntent.warning,
          icon: on
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),

        // Master Switch
        SettingsSection(
          title: 'Master switch',
          children: <Widget>[
            SettingsSwitchTile(
              icon: Icons.notifications_none,
              title: 'Enable notifications',
              description: 'Controls all feature notifications and background timers.',
              value: on,
              onChanged: (bool v) async {
                if (!v) {
                  await controller.update(
                    (AppSettings s) => s.copyWith(notificationsEnabled: false),
                  );
                  return;
                }

                final bool granted = await NotificationService()
                    .requestPermissions();
                if (!mounted) return;

                if (!granted) {
                  await controller.update(
                    (AppSettings s) => s.copyWith(notificationsEnabled: false),
                  );
                  if (!context.mounted) return;
                  UiToast.show(
                    context,
                    title: 'Notifications need permission',
                    message:
                        'Allow notifications in system settings to turn reminders on.',
                    intent: UiIntent.warning,
                    icon: Icons.notifications_off_outlined,
                  );
                  return;
                }

                await controller.update(
                  (AppSettings s) => s.copyWith(notificationsEnabled: true),
                );
              },
            ),
          ],
        ),

        // Focus Mode Alarm Sound
        SettingsSection(
          title: 'Focus timer alarm chime',
          description: 'Acoustic audio chime played when your focus or break interval completes.',
          children: <Widget>[
            UiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note_outlined, color: context.uiColors.primary),
                      const SizedBox(width: 8),
                      Text('Timer Expiry Sound', style: context.uiText.bodyStrong),
                      const Spacer(),
                      UiButton(
                        label: _previewingAlarm ? 'Stop' : 'Test Sound',
                        variant: _previewingAlarm ? UiVariant.destructive : UiVariant.secondary,
                        size: UiSize.xs,
                        leadingIcon: _previewingAlarm ? Icons.stop : Icons.volume_up,
                        onPressed: () => _previewAlarm(settings.focusAlarmSound),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AlarmOptionChip(
                        label: 'Zen Bell',
                        subtitle: 'Tibetan singing bowl harmonic',
                        value: 'zen_bell',
                        selected: settings.focusAlarmSound == 'zen_bell',
                        onSelected: () => controller.update(
                          (s) => s.copyWith(focusAlarmSound: 'zen_bell'),
                        ),
                      ),
                      _AlarmOptionChip(
                        label: 'Crystal Chime',
                        subtitle: 'Ascending 4-tone arpeggio',
                        value: 'crystal_chime',
                        selected: settings.focusAlarmSound == 'crystal_chime',
                        onSelected: () => controller.update(
                          (s) => s.copyWith(focusAlarmSound: 'crystal_chime'),
                        ),
                      ),
                      _AlarmOptionChip(
                        label: 'Digital Beep',
                        subtitle: '3 crisp modern pulses',
                        value: 'digital_beep',
                        selected: settings.focusAlarmSound == 'digital_beep',
                        onSelected: () => controller.update(
                          (s) => s.copyWith(focusAlarmSound: 'digital_beep'),
                        ),
                      ),
                      _AlarmOptionChip(
                        label: 'Temple Gong',
                        subtitle: 'Deep low resonance',
                        value: 'gong',
                        selected: settings.focusAlarmSound == 'gong',
                        onSelected: () => controller.update(
                          (s) => s.copyWith(focusAlarmSound: 'gong'),
                        ),
                      ),
                      _AlarmOptionChip(
                        label: 'Mute (Silent)',
                        subtitle: 'Vibration & notification only',
                        value: 'none',
                        selected: settings.focusAlarmSound == 'none',
                        onSelected: () => controller.update(
                          (s) => s.copyWith(focusAlarmSound: 'none'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Floating Focus Overlay Bubble
        SettingsSection(
          title: 'Floating focus timer bubble',
          description: 'A draggable floating widget showing live focus countdown and progress.',
          children: <Widget>[
            SettingsSwitchTile(
              icon: Icons.bubble_chart_outlined,
              title: 'Floating timer overlay bubble',
              description: 'Keep an interactive floating bubble visible while your focus session runs.',
              value: settings.floatingFocusBubbleEnabled,
              onChanged: (bool v) async {
                await controller.update(
                  (AppSettings s) => s.copyWith(floatingFocusBubbleEnabled: v),
                );
                if (v && !_overlayPermissionGranted) {
                  _requestOverlayPermission();
                }
              },
            ),
            UiCard(
              child: Row(
                children: [
                  Icon(
                    _overlayPermissionGranted
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    color: _overlayPermissionGranted
                        ? UiIntent.success.color(context)
                        : context.uiColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _overlayPermissionGranted
                              ? 'Display over other apps granted'
                              : 'System overlay permission',
                          style: context.uiText.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _overlayPermissionGranted
                              ? 'The timer bubble can float anywhere across your device screen.'
                              : 'Required on Android to display the draggable bubble above other applications.',
                          style: context.uiText.caption,
                        ),
                      ],
                    ),
                  ),
                  if (!_overlayPermissionGranted) ...[
                    const SizedBox(width: 8),
                    UiButton(
                      label: 'Grant',
                      variant: UiVariant.secondary,
                      size: UiSize.xs,
                      onPressed: _requestOverlayPermission,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Feature-specific Notification Preferences (All 11 features with dynamic icons)
        SettingsSection(
          title: 'Feature-specific notification channels',
          description: 'Individual toggles with dedicated notification channels and dynamic icons.',
          children: <Widget>[
            SettingsSwitchTile(
              icon: NotificationFeature.focus.icon,
              title: NotificationFeature.focus.label,
              description: 'Active chronometer in status bar & timer completion alerts.',
              enabled: on,
              value: settings.focusReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(focusReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.task.icon,
              title: NotificationFeature.task.label,
              description: 'Timely reminders before scheduled tasks and assignment deadlines.',
              enabled: on,
              value: settings.taskReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(taskReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.habit.icon,
              title: NotificationFeature.habit.label,
              description: 'Daily streak preservation alerts for habit check-ins.',
              enabled: on,
              value: settings.habitReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(habitReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.flashcard.icon,
              title: NotificationFeature.flashcard.label,
              description: 'Spaced repetition reviews when flashcard decks are due.',
              enabled: on,
              value: settings.flashcardReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(flashcardReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.course.icon,
              title: NotificationFeature.course.label,
              description: 'Upcoming class schedules, lecture start times & academic blocks.',
              enabled: on,
              value: settings.courseReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(courseReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.calendar.icon,
              title: NotificationFeature.calendar.label,
              description: 'Midterms, presentations, and calendar events.',
              enabled: on,
              value: settings.calendarReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(calendarReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.goal.icon,
              title: NotificationFeature.goal.label,
              description: 'Weekly goal milestone pacing and check-in nudges.',
              enabled: on,
              value: settings.goalReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(goalReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.routine.icon,
              title: NotificationFeature.routine.label,
              description: 'Morning and evening routine trigger nudges.',
              enabled: on,
              value: settings.routineReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(routineReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.journal.icon,
              title: NotificationFeature.journal.label,
              description: 'A gentle evening prompt to record reflections and gratitude.',
              enabled: on,
              value: settings.journalNudge,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(journalNudge: v),
              ),
            ),
            SettingsSwitchTile(
              icon: NotificationFeature.note.icon,
              title: NotificationFeature.note.label,
              description: 'Periodic resurfacing of pinned study notes for retention.',
              enabled: on,
              value: settings.noteReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(noteReminders: v),
              ),
            ),
          ],
        ),

        // Quiet Hours
        SettingsSection(
          title: 'Quiet hours',
          description: 'Automatically silence notifications during sleep or lectures.',
          children: <Widget>[
            SettingsSwitchTile(
              icon: Icons.bedtime_outlined,
              title: 'Enable quiet hours',
              enabled: on,
              value: settings.quietHoursEnabled,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(quietHoursEnabled: v),
              ),
            ),
            SettingsTile(
              icon: Icons.nightlight_outlined,
              title: 'Starts',
              value: formatMinutes(settings.quietStartMinutes),
              enabled: on && settings.quietHoursEnabled,
              onTap: () => _pickQuietTime(true, settings),
            ),
            SettingsTile(
              icon: Icons.wb_sunny_outlined,
              title: 'Ends',
              value: formatMinutes(settings.quietEndMinutes),
              enabled: on && settings.quietHoursEnabled,
              onTap: () => _pickQuietTime(false, settings),
            ),
          ],
        ),

        // Live Notification Test Hub (All 11 features)
        SettingsSection(
          title: 'Live notification test hub',
          description: 'Send dynamic test notifications to verify channel icon and system appearance.',
          children: <Widget>[
            UiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select a feature channel to test:', style: context.uiText.caption),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<NotificationFeature>(
                    initialValue: _selectedTestFeature,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final f in NotificationFeature.values)
                        DropdownMenuItem<NotificationFeature>(
                          value: f,
                          child: Row(
                            children: [
                              Icon(f.icon, size: 18, color: context.uiColors.primary),
                              const SizedBox(width: 8),
                              Text(f.label),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedTestFeature = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.uiColors.surfaceHover.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.uiColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(_selectedTestFeature.icon, color: context.uiColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_selectedTestFeature.sampleTitle, style: context.uiText.bodyStrong),
                              const SizedBox(height: 2),
                              Text(_selectedTestFeature.sampleBody, style: context.uiText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: UiButton(
                      label: 'Send "${_selectedTestFeature.label}" Test Notification',
                      leadingIcon: Icons.send_outlined,
                      variant: UiVariant.primary,
                      loading: _sendingTest,
                      onPressed: on && !_sendingTest ? () => _sendFeatureTest(_selectedTestFeature) : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.settings_outlined,
              title: 'Open device notification settings',
              description: 'Configure system banner style, lock screen visibility and sounds.',
              onTap: () => NotificationService().openDeviceNotificationSettings(),
            ),
          ],
        ),

        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}

class _AlarmOptionChip extends StatelessWidget {
  const _AlarmOptionChip({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String subtitle;
  final String value;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? context.uiColors.primary.withValues(alpha: 0.15)
              : context.uiColors.surfaceHover.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? context.uiColors.primary : context.uiColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: selected ? context.uiColors.primary : context.uiColors.foregroundMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: context.uiText.bodyStrong.copyWith(
                    color: selected ? context.uiColors.primary : context.uiColors.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: context.uiText.caption.copyWith(color: context.uiColors.foregroundMuted),
            ),
          ],
        ),
      ),
    );
  }
}
