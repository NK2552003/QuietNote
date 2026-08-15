import 'package:flutter/material.dart';

/// Accent choices offered in Settings > Appearance.
enum UiAccent { graphite, indigo, emerald, amber, rose, cyan }

extension UiAccentX on UiAccent {
  String get label {
    switch (this) {
      case UiAccent.graphite:
        return 'Graphite';
      case UiAccent.indigo:
        return 'Indigo';
      case UiAccent.emerald:
        return 'Emerald';
      case UiAccent.amber:
        return 'Amber';
      case UiAccent.rose:
        return 'Rose';
      case UiAccent.cyan:
        return 'Cyan';
    }
  }

  /// `null` means "use the theme's own default primary".
  Color? get color {
    switch (this) {
      case UiAccent.graphite:
        return null;
      case UiAccent.indigo:
        return const Color(0xFF4F46E5);
      case UiAccent.emerald:
        return const Color(0xFF059669);
      case UiAccent.amber:
        return const Color(0xFFD97706);
      case UiAccent.rose:
        return const Color(0xFFE11D48);
      case UiAccent.cyan:
        return const Color(0xFF0891B2);
    }
  }

  Color get swatch => color ?? const Color(0xFF3F3B39);
}

enum UiTextSize { small, standard, large, xlarge }

extension UiTextSizeX on UiTextSize {
  String get label {
    switch (this) {
      case UiTextSize.small:
        return 'Small';
      case UiTextSize.standard:
        return 'Standard';
      case UiTextSize.large:
        return 'Large';
      case UiTextSize.xlarge:
        return 'Extra large';
    }
  }

  double get factor {
    switch (this) {
      case UiTextSize.small:
        return 0.92;
      case UiTextSize.standard:
        return 1.0;
      case UiTextSize.large:
        return 1.15;
      case UiTextSize.xlarge:
        return 1.3;
    }
  }
}

/// Every user-facing preference in the app. Persisted as key/value rows in
/// the existing SQLite database (table `app_settings`), so nothing else in
/// the schema changes and no generated Drift code needs regenerating.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.accent = UiAccent.graphite,
    this.textSize = UiTextSize.standard,
    this.notificationsEnabled = true,
    this.habitReminders = true,
    this.taskReminders = true,
    this.calendarReminders = true,
    this.routineReminders = false,
    this.journalNudge = false,
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 7 * 60,
    this.captureAutoSave = false,
    this.captureDefaultTarget = 'todo',
    this.lastBackupAt,
    this.displayName = 'Student',
    this.onboardingComplete = false,
    this.focusAreas = const <String>[],
    this.clockStyle = 'digital',
    this.profileEmail = '',
    this.profileImagePath = '',
    this.focusSessionEndsAt,
    this.lastUsedPresetId,
    this.aiProviderMode = 'auto',
    this.aiApiProviderId = 'nvidia',
    this.aiApiBaseUrl = '',
    this.aiApiModel = '',
    this.aiApiKey = '',
  });

  final ThemeMode themeMode;
  final UiAccent accent;
  final UiTextSize textSize;

  final bool notificationsEnabled;
  final bool habitReminders;
  final bool taskReminders;
  final bool calendarReminders;
  final bool routineReminders;
  final bool journalNudge;

  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;

  final bool captureAutoSave;
  final String captureDefaultTarget;

  final DateTime? lastBackupAt;
  final String displayName;

  /// False until the user finishes (or skips) the onboarding flow. Drives the
  /// splash screen's redirect target.
  final bool onboardingComplete;

  /// Study areas picked during onboarding, e.g. ['Exams', 'Reading'].
  final List<String> focusAreas;
  final String clockStyle;
  final String profileEmail;
  final String profileImagePath;
  final DateTime? focusSessionEndsAt;

  /// The [FocusPreset] name the student last selected on the Focus Clock,
  /// pre-selected on the next visit so it survives an app restart
  /// mid-decision. `null` means no preset has been chosen yet.
  final String? lastUsedPresetId;

  /// AI Capture / Ask AI can run against the on-device model ('local') or a
  /// user-supplied cloud API ('api'). All of the fields below live in this
  /// same locally-stored settings table (see the class doc) — the key is
  /// only ever sent from this device directly to whichever provider the
  /// person configured, using their own key.
  final String aiProviderMode;

  /// Which built-in preset (see `cloud_ai_providers.dart`) the API key/base
  /// URL apply to, e.g. 'nvidia', 'openrouter', 'groq', or 'custom'.
  final String aiApiProviderId;

  /// Only used for the 'custom' provider; presets fill this in themselves.
  final String aiApiBaseUrl;
  final String aiApiModel;
  final String aiApiKey;

  int get activeReminderCount => <bool>[
    habitReminders,
    taskReminders,
    calendarReminders,
    routineReminders,
    journalNudge,
  ].where((bool b) => b && notificationsEnabled).length;

  String get themeModeLabel {
    switch (themeMode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    UiAccent? accent,
    UiTextSize? textSize,
    bool? notificationsEnabled,
    bool? habitReminders,
    bool? taskReminders,
    bool? calendarReminders,
    bool? routineReminders,
    bool? journalNudge,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? captureAutoSave,
    String? captureDefaultTarget,
    DateTime? lastBackupAt,
    String? displayName,
    bool? onboardingComplete,
    List<String>? focusAreas,
    String? clockStyle,
    String? profileEmail,
    String? profileImagePath,
    DateTime? focusSessionEndsAt,
    bool clearFocusSession = false,
    String? lastUsedPresetId,
    String? aiProviderMode,
    String? aiApiProviderId,
    String? aiApiBaseUrl,
    String? aiApiModel,
    String? aiApiKey,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    textSize: textSize ?? this.textSize,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    habitReminders: habitReminders ?? this.habitReminders,
    taskReminders: taskReminders ?? this.taskReminders,
    calendarReminders: calendarReminders ?? this.calendarReminders,
    routineReminders: routineReminders ?? this.routineReminders,
    journalNudge: journalNudge ?? this.journalNudge,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
    quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    captureAutoSave: captureAutoSave ?? this.captureAutoSave,
    captureDefaultTarget: captureDefaultTarget ?? this.captureDefaultTarget,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    displayName: displayName ?? this.displayName,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    focusAreas: focusAreas ?? this.focusAreas,
    clockStyle: clockStyle ?? this.clockStyle,
    profileEmail: profileEmail ?? this.profileEmail,
    profileImagePath: profileImagePath ?? this.profileImagePath,
    focusSessionEndsAt: clearFocusSession
        ? null
        : (focusSessionEndsAt ?? this.focusSessionEndsAt),
    lastUsedPresetId: lastUsedPresetId ?? this.lastUsedPresetId,
    aiProviderMode: aiProviderMode ?? this.aiProviderMode,
    aiApiProviderId: aiApiProviderId ?? this.aiApiProviderId,
    aiApiBaseUrl: aiApiBaseUrl ?? this.aiApiBaseUrl,
    aiApiModel: aiApiModel ?? this.aiApiModel,
    aiApiKey: aiApiKey ?? this.aiApiKey,
  );

  Map<String, String> toMap() => <String, String>{
    'themeMode': themeMode.name,
    'accent': accent.name,
    'textSize': textSize.name,
    'notificationsEnabled': '$notificationsEnabled',
    'habitReminders': '$habitReminders',
    'taskReminders': '$taskReminders',
    'calendarReminders': '$calendarReminders',
    'routineReminders': '$routineReminders',
    'journalNudge': '$journalNudge',
    'quietHoursEnabled': '$quietHoursEnabled',
    'quietStartMinutes': '$quietStartMinutes',
    'quietEndMinutes': '$quietEndMinutes',
    'captureAutoSave': '$captureAutoSave',
    'captureDefaultTarget': captureDefaultTarget,
    'lastBackupAt': lastBackupAt?.toIso8601String() ?? '',
    'displayName': displayName,
    'onboardingComplete': '$onboardingComplete',
    'focusAreas': focusAreas.join('|'),
    'clockStyle': clockStyle,
    'profileEmail': profileEmail,
    'profileImagePath': profileImagePath,
    'focusSessionEndsAt': focusSessionEndsAt?.toIso8601String() ?? '',
    'lastUsedPresetId': lastUsedPresetId ?? '',
    'aiProviderMode': aiProviderMode,
    'aiApiProviderId': aiApiProviderId,
    'aiApiBaseUrl': aiApiBaseUrl,
    'aiApiModel': aiApiModel,
    'aiApiKey': aiApiKey,
  };

  static AppSettings fromMap(Map<String, String> map) {
    T pickEnum<T>(List<T> values, String? name, T fallback) {
      for (final T v in values) {
        if ((v as Enum).name == name) return v;
      }
      return fallback;
    }

    bool flag(String key, bool fallback) {
      final String? raw = map[key];
      if (raw == null || raw.isEmpty) return fallback;
      return raw == 'true';
    }

    int number(String key, int fallback) =>
        int.tryParse(map[key] ?? '') ?? fallback;

    final String backupRaw = map['lastBackupAt'] ?? '';

    return AppSettings(
      themeMode: pickEnum(ThemeMode.values, map['themeMode'], ThemeMode.system),
      accent: pickEnum(UiAccent.values, map['accent'], UiAccent.graphite),
      textSize: pickEnum(
        UiTextSize.values,
        map['textSize'],
        UiTextSize.standard,
      ),
      notificationsEnabled: flag('notificationsEnabled', true),
      habitReminders: flag('habitReminders', true),
      taskReminders: flag('taskReminders', true),
      calendarReminders: flag('calendarReminders', true),
      routineReminders: flag('routineReminders', false),
      journalNudge: flag('journalNudge', false),
      quietHoursEnabled: flag('quietHoursEnabled', false),
      quietStartMinutes: number('quietStartMinutes', 22 * 60),
      quietEndMinutes: number('quietEndMinutes', 7 * 60),
      captureAutoSave: flag('captureAutoSave', false),
      captureDefaultTarget: (map['captureDefaultTarget'] ?? '').isEmpty
          ? 'todo'
          : map['captureDefaultTarget']!,
      lastBackupAt: backupRaw.isEmpty ? null : DateTime.tryParse(backupRaw),
      displayName: (map['displayName'] ?? '').isEmpty
          ? 'Student'
          : map['displayName']!,
      onboardingComplete: flag('onboardingComplete', false),
      focusAreas: (map['focusAreas'] ?? '').isEmpty
          ? const <String>[]
          : map['focusAreas']!.split('|'),
      clockStyle: (map['clockStyle'] ?? '').isEmpty
          ? 'digital'
          : map['clockStyle']!,
      profileEmail: map['profileEmail'] ?? '',
      profileImagePath: map['profileImagePath'] ?? '',
      focusSessionEndsAt: (map['focusSessionEndsAt'] ?? '').isEmpty
          ? null
          : DateTime.tryParse(map['focusSessionEndsAt']!),
      lastUsedPresetId: (map['lastUsedPresetId'] ?? '').isEmpty
          ? null
          : map['lastUsedPresetId'],
      aiProviderMode: (map['aiProviderMode'] ?? '').isEmpty
          ? 'auto'
          : map['aiProviderMode']!,
      aiApiProviderId: (map['aiApiProviderId'] ?? '').isEmpty
          ? 'nvidia'
          : map['aiApiProviderId']!,
      aiApiBaseUrl: map['aiApiBaseUrl'] ?? '',
      aiApiModel: map['aiApiModel'] ?? '',
      aiApiKey: map['aiApiKey'] ?? '',
    );
  }
}

String formatMinutes(int minutes) {
  final int h = (minutes ~/ 60) % 24;
  final int m = minutes % 60;
  final String suffix = h >= 12 ? 'PM' : 'AM';
  final int display = h % 12 == 0 ? 12 : h % 12;
  return '$display:${m.toString().padLeft(2, '0')} $suffix';
}
