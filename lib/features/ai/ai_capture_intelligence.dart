import 'dart:convert';

import 'ai_local_prompts.dart';
import 'capture_parser.dart';

/// Turns free text into a structured capture using whichever AI backend is
/// active, and merges the model's answer into the heuristic draft.
///
/// The heuristic parser ([CaptureParser]) always runs first, so a missing,
/// slow or nonsensical model reply can never stop a capture from being saved
/// — the model only ever *improves* fields it answered sensibly.
class AiCaptureIntelligence {
  const AiCaptureIntelligence._();

  /// System prompt for the structured extraction call. Uses the extended
  /// prompt from [AiLocalPrompts] which covers all 10 capture types.
  static String systemPrompt(DateTime now) =>
      AiLocalPrompts.captureSystemPrompt(now);

  /// Prompt for a plain conversational answer.
  static const String answerSystemPrompt =
      '''You are QuietNote, a private productivity assistant living inside the
user's notes app. Answer in at most five short sentences, or a tight list when
steps are genuinely needed. Be specific, practical and honest about
uncertainty. Preserve dates, times, names and numbers exactly as given. For
planning questions, lead with the single best next action. Never claim you
performed a real-world action, sent anything, or read data that is not in this
conversation. Plain text only — no markdown headings.''';

  // -------------------------------------------------------------------------
  // Draft enrichment
  // -------------------------------------------------------------------------

  /// Merges a raw model reply into [draft]. Returns true when at least one
  /// field was applied, so callers can tell whether AI actually contributed.
  static bool applyToDraft(CaptureDraft draft, String rawReply) {
    final Map<String, dynamic>? json = extractJson(rawReply);
    if (json == null) {
      // Not JSON: treat the whole reply as a cleaned-up title when short enough.
      final String text = rawReply.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isNotEmpty && text.length <= 120 && !text.contains('\n')) {
        draft.title = text;
        return true;
      }
      return false;
    }

    bool applied = false;
    final double modelConfidence = _asDouble(json['confidence']) ?? 0.0;

    final String? title = _asString(json['title']);
    if (title != null && title.length >= 2) {
      draft.title = title.length > 140 ? title.substring(0, 140) : title;
      applied = true;
    }

    final String? details = _asString(json['details']);
    if (details != null && details.isNotEmpty && draft.details.trim().isEmpty) {
      draft.details = details;
      applied = true;
    }

    // Type classification
    final CaptureType? type = parseType(_asString(json['type']));
    if (type != null && (draft.confidence < 0.9 || modelConfidence >= 0.9)) {
      if (type != draft.type) {
        final List<CaptureSuggestion> alternates = <CaptureSuggestion>[
          CaptureSuggestion(draft.type, draft.confidence),
          ...draft.alternates.where((CaptureSuggestion s) => s.type != type),
        ];
        draft.alternates = alternates.take(3).toList();
      }
      draft.type = type;
      applied = true;
    }

    // Date / time
    final DateTime? when = parseDateTime(
      _asString(json['date']),
      _asString(json['time']),
    );
    if (when != null) {
      if (draft.type == CaptureType.event) {
        draft.startTime ??= when;
        final DateTime? end = parseDateTime(
          _asString(json['date']),
          _asString(json['end_time']),
        );
        draft.endTime ??= end ?? when.add(const Duration(hours: 1));
      } else {
        draft.dueDate ??= when;
      }
      applied = true;
    }

    // Priority
    final double? priority = _asDouble(json['priority']);
    if (priority != null && draft.priority == 0) {
      draft.priority = priority.round().clamp(0, 3);
      applied = true;
    }

    // Mood
    final String? mood = _asString(json['mood']);
    if (mood != null && draft.mood == 'Neutral') {
      draft.mood = _titleCase(mood);
      applied = true;
    }

    // Category
    final String? category = _asString(json['category']);
    if (category != null && draft.category == 'Other') {
      draft.category = _titleCase(category);
      applied = true;
    }

    // Frequency
    final String? frequency = _asString(json['frequency'])?.toLowerCase();
    if (frequency != null &&
        <String>['daily', 'weekly', 'monthly'].contains(frequency)) {
      draft.frequencyType = frequency;
      applied = true;
    }

    // Goal target
    final double? target = _asDouble(json['target']);
    if (target != null && target > 0 && draft.goalTarget <= 0) {
      draft.goalTarget = target;
      applied = true;
    }

    // Goal unit
    final String? unit = _asString(json['unit']);
    if (unit != null && draft.goalUnit.isEmpty) {
      draft.goalUnit = unit;
      applied = true;
    }

    // Course fields
    final String? courseCode = _asString(json['course_code']);
    if (courseCode != null && draft.courseCode.isEmpty) {
      draft.courseCode = courseCode;
      applied = true;
    }
    final String? instructor = _asString(json['instructor']);
    if (instructor != null && draft.courseInstructor.isEmpty) {
      draft.courseInstructor = instructor;
      applied = true;
    }
    final String? room = _asString(json['room']);
    if (room != null && draft.courseRoom.isEmpty) {
      draft.courseRoom = room;
      applied = true;
    }
    final String? term = _asString(json['term']);
    if (term != null && draft.courseTerm.isEmpty) {
      draft.courseTerm = term;
      applied = true;
    }
    final double? targetGrade = _asDouble(json['target_grade']);
    if (targetGrade != null && targetGrade > 0 && draft.courseTargetGrade == null) {
      draft.courseTargetGrade = targetGrade;
      applied = true;
    }

    // Focus preset
    final String? focusPreset = _asString(json['focus_preset']);
    if (focusPreset != null && draft.focusPresetId == null) {
      draft.focusPresetId = focusPreset;
      applied = true;
    }

    // Confidence blending
    if (modelConfidence > 0) {
      draft.confidence =
          ((draft.confidence + modelConfidence) / 2).clamp(0.0, 1.0);
    }

    return applied;
  }

  // -------------------------------------------------------------------------
  // Flashcard generation
  // -------------------------------------------------------------------------

  /// Parses a raw AI reply that should contain a JSON array of
  /// {front, back} objects. Returns an empty list on parse failure.
  static List<({String front, String back})> parseFlashcardPairs(
      String rawReply) {
    try {
      var text = rawReply.trim();
      // Strip markdown code fences if present
      text = text
          .replaceAll(RegExp(r'^```(?:json)?', caseSensitive: false), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start < 0 || end < start) return const [];
      final jsonStr = text.substring(start, end + 1);
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! List) return const [];
      final result = <({String front, String back})>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final front = _asString(item['front']) ?? _asString(item['q']) ?? '';
          final back = _asString(item['back']) ?? _asString(item['a']) ?? '';
          if (front.isNotEmpty && back.isNotEmpty) {
            result.add((front: front, back: back));
          }
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // Milestone parsing
  // -------------------------------------------------------------------------

  /// Parses a raw AI reply that should contain a JSON array of strings.
  static List<String> parseMilestones(String rawReply) {
    try {
      var text = rawReply.trim();
      text = text
          .replaceAll(RegExp(r'^```(?:json)?', caseSensitive: false), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start < 0 || end < start) return const [];
      final dynamic decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // JSON extraction helpers
  // -------------------------------------------------------------------------

  /// Pulls the first JSON object out of a model reply, tolerating code fences,
  /// leading prose and trailing text.
  static Map<String, dynamic>? extractJson(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text
        .replaceAll(RegExp(r'^```(?:json)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'```$'), '')
        .trim();

    final int start = text.indexOf('{');
    if (start < 0) return null;

    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < text.length; i++) {
      final String ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final String candidate = text.substring(start, i + 1);
          try {
            final dynamic decoded = jsonDecode(candidate);
            if (decoded is Map<String, dynamic>) return decoded;
          } catch (_) {
            return null;
          }
          return null;
        }
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Type parsing
  // -------------------------------------------------------------------------

  static CaptureType? parseType(String? raw) {
    final String value = (raw ?? '').toLowerCase().trim();
    if (value.isEmpty) return null;
    if (value.contains('todo') ||
        value.contains('task') ||
        value.contains('to-do')) {
      return CaptureType.todo;
    }
    if (value.contains('event') ||
        value.contains('calendar') ||
        value.contains('meeting') ||
        value.contains('appointment')) {
      return CaptureType.event;
    }
    if (value.contains('habit')) return CaptureType.habit;
    if (value.contains('routine')) return CaptureType.routine;
    if (value.contains('goal') || value.contains('target')) {
      return CaptureType.goal;
    }
    if (value.contains('journal') || value.contains('diary')) {
      return CaptureType.journal;
    }
    if (value.contains('flashcard') || value.contains('flash_card') || value.contains('deck')) {
      return CaptureType.flashcard;
    }
    if (value.contains('course') || value.contains('class')) {
      return CaptureType.course;
    }
    if (value.contains('focus') || value.contains('pomodoro') || value.contains('session')) {
      return CaptureType.focusSession;
    }
    if (value.contains('note') || value.contains('idea')) {
      return CaptureType.note;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Date / time parsing
  // -------------------------------------------------------------------------

  static DateTime? parseDateTime(String? date, String? time) {
    final String d = (date ?? '').trim();
    final String t = (time ?? '').trim();
    if (d.isEmpty && t.isEmpty) return null;

    DateTime base;
    if (d.isEmpty) {
      final DateTime now = DateTime.now();
      base = DateTime(now.year, now.month, now.day);
    } else {
      final DateTime? parsed = DateTime.tryParse(d.length <= 10 ? d : d);
      if (parsed == null) return null;
      base = DateTime(parsed.year, parsed.month, parsed.day);
      if (d.length > 10 && t.isEmpty) {
        return parsed;
      }
    }

    if (t.isEmpty) return base;
    final RegExpMatch? match =
        RegExp(r'^(\d{1,2})[:.:](\d{2})').firstMatch(t);
    if (match == null) return base;
    final int hour = int.parse(match.group(1)!).clamp(0, 23);
    final int minute = int.parse(match.group(2)!).clamp(0, 59);
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  // -------------------------------------------------------------------------
  // Shared utilities
  // -------------------------------------------------------------------------

  static String _titleCase(String value) {
    final String v = value.trim();
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1).toLowerCase();
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final String text = value.toString().trim();
    if (text.isEmpty ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'none') {
      return null;
    }
    return text;
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }
}
