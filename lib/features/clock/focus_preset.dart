/// Hardcoded study-session presets for the Focus Clock (Feature 3). Not
/// user-editable for v1 — see quietnote-remaining-features.md.
enum FocusPreset { pomodoro, deepWork, quickReview, custom }

/// `brk == 0` marks a preset with no auto-chained break (Quick review); such
/// a preset never triggers the start-break prompt.
typedef FocusPresetConfig = ({int work, int brk, String label});

const Map<FocusPreset, FocusPresetConfig> presetConfig = {
  FocusPreset.pomodoro: (work: 25, brk: 5, label: 'Pomodoro 25/5'),
  FocusPreset.deepWork: (work: 50, brk: 10, label: 'Deep work 50/10'),
  FocusPreset.quickReview: (work: 15, brk: 0, label: 'Quick review 15 min'),
};

extension FocusPresetX on FocusPreset {
  /// Short label for the selector chip (the full description already lives
  /// in [presetConfig] for presets that have one).
  String get chipLabel {
    switch (this) {
      case FocusPreset.pomodoro:
        return 'Pomodoro';
      case FocusPreset.deepWork:
        return 'Deep work';
      case FocusPreset.quickReview:
        return 'Quick review';
      case FocusPreset.custom:
        return 'Custom';
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
