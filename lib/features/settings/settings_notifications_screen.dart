import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart' hide formatMinutes;
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Reminder switches, quiet hours and a live test notification.
class SettingsNotificationsScreen extends ConsumerStatefulWidget {
  const SettingsNotificationsScreen({super.key});

  @override
  ConsumerState<SettingsNotificationsScreen> createState() =>
      _SettingsNotificationsScreenState();
}

class _SettingsNotificationsScreenState
    extends ConsumerState<SettingsNotificationsScreen> {
  bool _sendingTest = false;

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

  Future<void> _sendTest() async {
    setState(() => _sendingTest = true);
    try {
      await NotificationService().init();
      final ok = await NotificationService().showInstantNotification(
        999001,
        'QuietNote test notification',
        'This should appear immediately.',
      );
      if (mounted) {
        if (ok) {
          UiToast.show(
            context,
            title: 'Test notification shown',
            message: 'It should be visible right now.',
            intent: UiIntent.success,
            icon: Icons.notifications_active_outlined,
          );
        } else {
          UiToast.show(
            context,
            title: 'Could not schedule test',
            message: 'Notifications permission not granted or display failed.',
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
      title: 'Notifications',
      subtitle: 'Nudges that respect your focus time.',
      children: <Widget>[
        UiCallout(
          title: on ? 'Reminders are on' : 'All reminders are paused',
          message: on
              ? '${settings.activeReminderCount} reminder type(s) active.'
              : 'Turn the master switch on to receive any reminder.',
          intent: on ? UiIntent.success : UiIntent.warning,
          icon: on
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'Master switch',
          children: <Widget>[
            SettingsSwitchTile(
              icon: Icons.notifications_none,
              title: 'Enable notifications',
              description: 'Controls every reminder below.',
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
        SettingsSection(
          title: 'Device permission',
          description:
              'If you previously declined the system prompt, enable it here.',
          children: <Widget>[
            SettingsTile(
              icon: Icons.settings_outlined,
              title: 'Open device notification settings',
              description: 'Allow QuietNote notifications and alarms.',
              onTap: () =>
                  NotificationService().openDeviceNotificationSettings(),
            ),
          ],
        ),
        SettingsSection(
          title: 'What to remind me about',
          children: <Widget>[
            SettingsSwitchTile(
              icon: Icons.repeat,
              title: 'Habit check-ins',
              description: 'A nudge when a habit is due.',
              enabled: on,
              value: settings.habitReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(habitReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.checklist,
              title: 'To-do due dates',
              description: 'Before a task is due.',
              enabled: on,
              value: settings.taskReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(taskReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar events',
              description: 'Classes, exams and study blocks.',
              enabled: on,
              value: settings.calendarReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(calendarReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.route_outlined,
              title: 'Routine start',
              description: 'When a morning or evening routine begins.',
              enabled: on,
              value: settings.routineReminders,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(routineReminders: v),
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.menu_book_outlined,
              title: 'Journal nudge',
              description: 'A gentle end-of-day reflection prompt.',
              enabled: on,
              value: settings.journalNudge,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(journalNudge: v),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Quiet hours',
          description: 'No reminders during class or sleep.',
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
        UiButton(
          label: 'Send a test reminder',
          leadingIcon: Icons.send_outlined,
          variant: UiVariant.secondary,
          loading: _sendingTest,
          onPressed: on && !_sendingTest ? _sendTest : null,
        ),
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}
