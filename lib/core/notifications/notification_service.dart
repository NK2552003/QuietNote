import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// 11 Feature Notification Taxonomy
// ---------------------------------------------------------------------------

enum NotificationFeature {
  task,
  habit,
  calendar,
  routine,
  journal,
  flashcard,
  course,
  goal,
  focus,
  note,
  clock,
}

extension NotificationFeatureX on NotificationFeature {
  String get label {
    switch (this) {
      case NotificationFeature.task:
        return 'To-dos & Tasks';
      case NotificationFeature.habit:
        return 'Habit Streaks';
      case NotificationFeature.calendar:
        return 'Calendar Events';
      case NotificationFeature.routine:
        return 'Daily Routines';
      case NotificationFeature.journal:
        return 'Evening Journal';
      case NotificationFeature.flashcard:
        return 'Spaced Repetition';
      case NotificationFeature.course:
        return 'Courses & Lectures';
      case NotificationFeature.goal:
        return 'Goal Milestones';
      case NotificationFeature.focus:
        return 'Focus & Pomodoro';
      case NotificationFeature.note:
        return 'Study Notes';
      case NotificationFeature.clock:
        return 'Clock & Alarms';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationFeature.task:
        return Icons.checklist_rtl_outlined;
      case NotificationFeature.habit:
        return Icons.repeat;
      case NotificationFeature.calendar:
        return Icons.calendar_month_outlined;
      case NotificationFeature.routine:
        return Icons.route_outlined;
      case NotificationFeature.journal:
        return Icons.menu_book_outlined;
      case NotificationFeature.flashcard:
        return Icons.style_outlined;
      case NotificationFeature.course:
        return Icons.school_outlined;
      case NotificationFeature.goal:
        return Icons.flag_outlined;
      case NotificationFeature.focus:
        return Icons.timer_outlined;
      case NotificationFeature.note:
        return Icons.description_outlined;
      case NotificationFeature.clock:
        return Icons.alarm;
    }
  }

  String get channelId {
    switch (this) {
      case NotificationFeature.task:
        return 'quietnote_tasks';
      case NotificationFeature.habit:
        return 'quietnote_habits';
      case NotificationFeature.calendar:
        return 'quietnote_calendar';
      case NotificationFeature.routine:
        return 'quietnote_routines';
      case NotificationFeature.journal:
        return 'quietnote_journal';
      case NotificationFeature.flashcard:
        return 'quietnote_flashcards';
      case NotificationFeature.course:
        return 'quietnote_courses';
      case NotificationFeature.goal:
        return 'quietnote_goals';
      case NotificationFeature.focus:
        return 'quietnote_focus';
      case NotificationFeature.note:
        return 'quietnote_notes';
      case NotificationFeature.clock:
        return 'quietnote_clock';
    }
  }

  String get channelName => label;

  String get sampleTitle {
    switch (this) {
      case NotificationFeature.task:
        return 'Task Due Soon';
      case NotificationFeature.habit:
        return 'Keep Your Streak Alive';
      case NotificationFeature.calendar:
        return 'Upcoming Calendar Event';
      case NotificationFeature.routine:
        return 'Routine Check-in';
      case NotificationFeature.journal:
        return 'Daily Reflection Time';
      case NotificationFeature.flashcard:
        return 'Flashcards Due for Review';
      case NotificationFeature.course:
        return 'Upcoming Lecture & Class';
      case NotificationFeature.goal:
        return 'Weekly Goal Check-in';
      case NotificationFeature.focus:
        return 'Focus Interval Complete';
      case NotificationFeature.note:
        return 'Study Note Refresh';
      case NotificationFeature.clock:
        return 'Clock Alarm';
    }
  }

  String get sampleBody {
    switch (this) {
      case NotificationFeature.task:
        return 'Submit Problem Set 3 · Due today at 4:00 PM';
      case NotificationFeature.habit:
        return 'Read 20 pages · Keep your 5-day reading momentum going!';
      case NotificationFeature.calendar:
        return 'Physics Midterm Exam · Starts in 15 mins at Room 204';
      case NotificationFeature.routine:
        return 'Morning Focus Routine · 4 steps ready to start your day strong';
      case NotificationFeature.journal:
        return 'How did your studies and work go today? Take 2 mins to reflect.';
      case NotificationFeature.flashcard:
        return '14 cards in Organic Chemistry deck are ready for review today.';
      case NotificationFeature.course:
        return 'CS101 Algorithm Design starts in 30 minutes.';
      case NotificationFeature.goal:
        return 'Q3 Project Goal is at 65% · 3 days remaining this sprint.';
      case NotificationFeature.focus:
        return 'Great work! 25-minute Pomodoro focus session completed.';
      case NotificationFeature.note:
        return 'Review your pinned note "Distributed Systems Architecture".';
      case NotificationFeature.clock:
        return 'Focus block alarm · Time to begin your morning deep work session.';
    }
  }
}

// ---------------------------------------------------------------------------
// Notification Service Implementation
// ---------------------------------------------------------------------------

class NotificationService {
  /// Shared ID lets the scheduled completion replace the ongoing timer card.
  static const int focusStatusNotificationId = 814207;
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    return _initFuture ??= _init();
  }

  Future<void> init() => ensureInitialized();

  Future<void> _init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_stat_quietnote');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(settings: initializationSettings);
  }

  Future<bool> _requestNotificationPermissions() async {
    bool granted = true;

    try {
      final status = await Permission.notification.request();
      granted = status.isGranted;
    } catch (_) {
      granted = false;
    }

    try {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
    } catch (_) {}

    try {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}

    return granted;
  }

  Future<bool> requestPermissions() async {
    await ensureInitialized();
    return _requestNotificationPermissions();
  }

  NotificationDetails _buildDetails(NotificationFeature feature) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        feature.channelId,
        feature.channelName,
        channelDescription: 'Notifications for ${feature.label}',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<bool> showInstantNotification(
    int id,
    String title,
    String body, {
    NotificationFeature feature = NotificationFeature.task,
  }) async {
    try {
      await ensureInitialized();
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final PermissionStatus requested = await Permission.notification
            .request();
        if (!requested.isGranted) {
          if (requested.isPermanentlyDenied) {
            await openAppSettings();
          }
          return false;
        }
      }

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _buildDetails(feature),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Schedules a reminder with feature channel mapping.
  Future<bool> scheduleReminder(
    int id,
    String title,
    String body,
    DateTime scheduledTime, {
    NotificationFeature feature = NotificationFeature.task,
    DateTimeComponents? repeatComponents,
  }) async {
    try {
      await ensureInitialized();
      final status = await Permission.notification.status;
      if (!status.isGranted) return false;

      final tz.TZDateTime scheduledAt = tz.TZDateTime.from(
        scheduledTime,
        tz.local,
      );
      final notificationDetails = _buildDetails(feature);

      if (await _trySchedule(
        id: id,
        title: title,
        body: body,
        scheduledAt: scheduledAt,
        notificationDetails: notificationDetails,
        scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        repeatComponents: repeatComponents,
      )) {
        return true;
      }

      return await _trySchedule(
        id: id,
        title: title,
        body: body,
        scheduledAt: scheduledAt,
        notificationDetails: notificationDetails,
        scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        repeatComponents: repeatComponents,
      );
    } catch (_) {
      return false;
    }
  }

  /// A persistent, ongoing focus timer card in the notification drawer that
  /// stays pinned even if the user switches apps or exits to the home screen.
  Future<bool> showFocusTimerStatus(
    DateTime endsAt, {
    String phase = 'work',
    String? presetLabel,
    String? linkedTitle,
  }) async {
    try {
      await ensureInitialized();
      if (!(await Permission.notification.status).isGranted) return false;

      final isBreak = phase == 'break';
      final title = isBreak
          ? 'Break in progress'
          : 'Focus session ${presetLabel != null ? '($presetLabel)' : 'active'}';
      final subtitle = linkedTitle != null && linkedTitle.isNotEmpty
          ? '$linkedTitle · Ends at ${_timeLabel(endsAt)}'
          : 'Ends at ${_timeLabel(endsAt)} · Stay focused';

      await _notificationsPlugin.show(
        id: focusStatusNotificationId,
        title: title,
        body: subtitle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'quietnote_focus',
            'Focus timer',
            channelDescription: 'Active countdown for QuietNote focus session',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: true,
            when: endsAt.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearFocusTimerStatus() async {
    await ensureInitialized();
    await _notificationsPlugin.cancel(id: focusStatusNotificationId);
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<bool> _trySchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledAt,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode scheduleMode,
    required DateTimeComponents? repeatComponents,
  }) async {
    try {
      if (scheduleMode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestExactAlarmsPermission();
      }

      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledAt,
        notificationDetails: notificationDetails,
        androidScheduleMode: scheduleMode,
        matchDateTimeComponents: repeatComponents,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelReminder(int id) async {
    await ensureInitialized();
    await _notificationsPlugin.cancel(id: id);
  }

  Future<void> openDeviceNotificationSettings() => openAppSettings();
}
