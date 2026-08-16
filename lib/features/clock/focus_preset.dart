import 'package:flutter/material.dart';

/// Productivity and study-session presets for students and workers.
enum FocusPreset {
  pomodoro,
  deepWork,
  examSprint,
  powerHour,
  quickReview,
  flowState,
  custom,
}

/// `brk == 0` marks a preset with no auto-chained break; such
/// a preset never triggers the start-break prompt.
typedef FocusPresetConfig = ({int work, int brk, String label, String subtitle});

const Map<FocusPreset, FocusPresetConfig> presetConfig = {
  FocusPreset.pomodoro: (
    work: 25,
    brk: 5,
    label: 'Pomodoro 25/5',
    subtitle: 'Classic balanced 25m work with 5m break',
  ),
  FocusPreset.deepWork: (
    work: 50,
    brk: 10,
    label: 'Deep Work 50/10',
    subtitle: 'For devs, writers & heavy problem solving',
  ),
  FocusPreset.examSprint: (
    work: 45,
    brk: 15,
    label: 'Exam Sprint 45/15',
    subtitle: 'High-yield study & test prep with relaxing break',
  ),
  FocusPreset.powerHour: (
    work: 60,
    brk: 10,
    label: 'Power Hour 60/10',
    subtitle: 'Uninterrupted 1-hour intense project sprint',
  ),
  FocusPreset.quickReview: (
    work: 15,
    brk: 0,
    label: 'Quick Review 15m',
    subtitle: 'Rapid flashcard, reading or notes refresh',
  ),
  FocusPreset.flowState: (
    work: 90,
    brk: 20,
    label: 'Flow State 90/20',
    subtitle: 'Deep immersion for research, writing & creative flow',
  ),
};

extension FocusPresetX on FocusPreset {
  /// Short label for the selector chip.
  String get chipLabel {
    switch (this) {
      case FocusPreset.pomodoro:
        return 'Pomodoro 25m';
      case FocusPreset.deepWork:
        return 'Deep Work 50m';
      case FocusPreset.examSprint:
        return 'Exam Sprint 45m';
      case FocusPreset.powerHour:
        return 'Power Hour 60m';
      case FocusPreset.quickReview:
        return 'Quick Review 15m';
      case FocusPreset.flowState:
        return 'Flow State 90m';
      case FocusPreset.custom:
        return 'Custom';
    }
  }

  IconData get icon {
    switch (this) {
      case FocusPreset.pomodoro:
        return Icons.timer_outlined;
      case FocusPreset.deepWork:
        return Icons.laptop_mac_outlined;
      case FocusPreset.examSprint:
        return Icons.school_outlined;
      case FocusPreset.powerHour:
        return Icons.bolt_outlined;
      case FocusPreset.quickReview:
        return Icons.flash_on_outlined;
      case FocusPreset.flowState:
        return Icons.waves_outlined;
      case FocusPreset.custom:
        return Icons.tune_outlined;
    }
  }

  /// `null` for [FocusPreset.custom], which has no fixed durations.
  FocusPresetConfig? get config => presetConfig[this];
}

/// Parses a persisted `AppSettings.lastUsedPresetId` /
/// `FocusSession.presetId` value back into a [FocusPreset], tolerating
/// unknown/empty values (returns `null`) so old or corrupt data never
/// crashes the Clock screen.
FocusPreset? focusPresetFromId(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final FocusPreset preset in FocusPreset.values) {
    if (preset.name == id) return preset;
  }
  return null;
}
