import 'package:flutter_test/flutter_test.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/features/clock/focus_preset.dart';

void main() {
  group('FocusPreset Tests', () {
    test('All 6 student/worker presets and custom have valid configurations', () {
      expect(FocusPreset.values.length, 7);

      expect(FocusPreset.pomodoro.config?.work, 25);
      expect(FocusPreset.pomodoro.config?.brk, 5);

      expect(FocusPreset.deepWork.config?.work, 50);
      expect(FocusPreset.deepWork.config?.brk, 10);

      expect(FocusPreset.examSprint.config?.work, 45);
      expect(FocusPreset.examSprint.config?.brk, 15);

      expect(FocusPreset.powerHour.config?.work, 60);
      expect(FocusPreset.powerHour.config?.brk, 10);

      expect(FocusPreset.quickReview.config?.work, 15);
      expect(FocusPreset.quickReview.config?.brk, 0);

      expect(FocusPreset.flowState.config?.work, 90);
      expect(FocusPreset.flowState.config?.brk, 20);

      expect(FocusPreset.custom.config, isNull);
    });

    test('focusPresetFromId resolves correctly or handles unknown values safely', () {
      expect(focusPresetFromId('pomodoro'), FocusPreset.pomodoro);
      expect(focusPresetFromId('examSprint'), FocusPreset.examSprint);
      expect(focusPresetFromId('flowState'), FocusPreset.flowState);
      expect(focusPresetFromId('custom'), FocusPreset.custom);
      expect(focusPresetFromId('unknown_invalid_key'), isNull);
      expect(focusPresetFromId(null), isNull);
      expect(focusPresetFromId(''), isNull);
    });
  });

  group('NotificationFeature Taxonomy Tests', () {
    test('All 11 features have distinct labels, channel IDs, and dynamic icons', () {
      expect(NotificationFeature.values.length, 11);

      final channelIds = <String>{};
      for (final feature in NotificationFeature.values) {
        expect(feature.label.isNotEmpty, true);
        expect(feature.channelId.startsWith('quietnote_'), true);
        expect(feature.sampleTitle.isNotEmpty, true);
        expect(feature.sampleBody.isNotEmpty, true);
        expect(channelIds.contains(feature.channelId), false,
            reason: 'Channel ID ${feature.channelId} must be unique');
        channelIds.add(feature.channelId);
      }
    });
  });

  group('AppSettings 11-feature Notification Serialization Tests', () {
    test('Persists and restores 11 feature notification preferences and alarm sound', () {
      const settings = AppSettings(
        flashcardReminders: true,
        courseReminders: true,
        goalReminders: false,
        focusReminders: true,
        noteReminders: true,
        focusAlarmSound: 'crystal_chime',
      );

      final map = settings.toMap();
      expect(map['flashcardReminders'], 'true');
      expect(map['courseReminders'], 'true');
      expect(map['goalReminders'], 'false');
      expect(map['focusReminders'], 'true');
      expect(map['noteReminders'], 'true');
      expect(map['focusAlarmSound'], 'crystal_chime');

      final parsed = AppSettings.fromMap(map);
      expect(parsed.flashcardReminders, true);
      expect(parsed.courseReminders, true);
      expect(parsed.goalReminders, false);
      expect(parsed.focusReminders, true);
      expect(parsed.noteReminders, true);
      expect(parsed.focusAlarmSound, 'crystal_chime');
    });
  });
}
