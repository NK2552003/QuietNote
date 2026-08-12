import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
          // Keep iOS silent until onboarding/Settings has explained why alerts
          // are needed, matching Android's deliberate permission flow.
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

    // Initialization must be silent. Permission prompts are initiated from
    // onboarding or Settings after the person has seen an explanation.
  }

  Future<bool> _requestNotificationPermissions() async {
    bool granted = true;

    // Request runtime notification permission (Android 13+ / iOS).
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

    // iOS / macOS permission request (explicit) — initialization settings
    // already request permissions, but calling requestPermissions is safe.
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

  Future<bool> showInstantNotification(
    int id,
    String title,
    String body,
  ) async {
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
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'quietnote_reminders',
            'Reminders',
            channelDescription: 'Notifications for upcoming habits and tasks',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Schedules a reminder. Returns true when scheduling succeeded (permission
  /// granted and scheduling API returned without error), false otherwise.
  Future<bool> scheduleReminder(
    int id,
    String title,
    String body,
    DateTime scheduledTime, {
    DateTimeComponents? repeatComponents,
  }) async {
    try {
      await ensureInitialized();
      final status = await Permission.notification.status;
      // Permission is requested during onboarding or Settings, never as a
      // surprise after a person has completed a form.
      if (!status.isGranted) return false;

      final tz.TZDateTime scheduledAt = tz.TZDateTime.from(
        scheduledTime,
        tz.local,
      );
      const NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'quietnote_reminders',
          'Reminders',
          channelDescription: 'Notifications for upcoming habits and tasks',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

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

  /// A visible, ongoing focus status survives closing the Flutter activity.
  /// Android owns this notification until it is explicitly cleared, while the
  /// independently scheduled completion alert still works after process exit.
  Future<bool> showFocusTimerStatus(DateTime endsAt) async {
    try {
      await ensureInitialized();
      if (!(await Permission.notification.status).isGranted) return false;
      await _notificationsPlugin.show(
        id: focusStatusNotificationId,
        title: 'Focus session in progress',
        body: 'Ends at ${_timeLabel(endsAt)}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'quietnote_focus',
            'Focus timer',
            channelDescription: 'Visible status for an active QuietNote focus timer',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: true,
            when: DateTime.now().millisecondsSinceEpoch,
            usesChronometer: true,
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
