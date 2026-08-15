import 'dart:convert';

import 'capture_parser.dart';

/// Turns free text into a structured capture using whichever AI backend is
/// active, and merges the model's answer into the heuristic draft.
///
/// The heuristic parser ([CaptureParser]) always runs first, so a missing,
/// slow or nonsensical model reply can never stop a capture from being saved
/// — the model only ever *improves* fields it answered sensibly.
class AiCaptureIntelligence {
  const AiCaptureIntelligence._();

  /// System prompt for the structured extraction call. The model is asked for
  /// strict JSON so the reply can be merged field by field.
  static String systemPrompt(DateTime now) {
    final String today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final String weekday = _weekdayName(now.weekday);
    return '''You extract structured entries for QuietNote, a personal planner.
Today is $weekday, $today (local time). The current time is ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}.

Reply with ONE JSON object and nothing else. No markdown, no code fences, no
commentary. Use exactly this shape:

{
  "type": "todo|event|habit|routine|goal|journal|note",
  "title": "short imperative title, max 80 chars",
  "details": "extra context, or empty string",
  "date": "YYYY-MM-DD or empty string",
  "time": "HH:MM (24h) or empty string",
  "end_time": "HH:MM (24h) or empty string",
  "priority": 0,
  "mood": "Happy|Calm|Neutral|Sad|Anxious|Tired|Grateful",
  "category": "Health|Work|Personal|Learning|Finance|Other",
  "frequency": "daily|weekly|monthly",
  "target": 0,
  "confidence": 0.0
}

Rules:
- Choose "todo" for actions, "event" for anything with a specific date/time,
  "habit" for repeated behaviour, "routine" for a sequence tied to a part of
  the day, "goal" for a measurable target, "journal" for reflections on what
  already happened, "note" for reference information.
- Resolve relative dates ("tomorrow", "next Monday", "in 3 days") against
  today's date above and output absolute values.
- priority: 0 normal, 1 high, 2 urgent.
- target: numeric goal amount when the text states one, else 0.
- confidence: how sure you are about "type", between 0 and 1.
- Never invent facts, names, amounts or dates that are not implied by the text.
- Keep the user's own wording in the title wherever possible.''';
  }

  /// Prompt for a plain conversational answer.
  static const String answerSystemPrompt =
      '''You are QuietNote, a private productivity assistant living inside the
user's notes app. Answer in at most five short sentences, or a tight list when
steps are genuinely needed. Be specific, practical and honest about
uncertainty. Preserve dates, times, names and numbers exactly as given. For
planning questions, lead with the single best next action. Never claim you
performed a real-world action, sent anything, or read data that is not in this
conversation. Plain text only — no markdown headings.''';

  /// Merges a raw model reply into [draft]. Returns true when at least one
  /// field was applied, so callers can tell whether AI actually contributed.
  static bool applyToDraft(CaptureDraft draft, String rawReply) {
    final Map<String, dynamic>? json = extractJson(rawReply);
    if (json == null) {
      // Not JSON: treat the whole reply as a cleaned-up title when it is short
      // enough to plausibly be one.
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

    final CaptureType? type = parseType(_asString(json['type']));
    // The heuristic parser wins when it was highly confident (an explicit
    // date, "every day", and so on); otherwise the model's classification is
    // usually the better read of intent.
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

    final double? priority = _asDouble(json['priority']);
    if (priority != null && draft.priority == 0) {
      draft.priority = priority.round().clamp(0, 2);
      applied = true;
    }

    final String? mood = _asString(json['mood']);
    if (mood != null && draft.mood == 'Neutral') {
      draft.mood = _titleCase(mood);
      applied = true;
    }

    final String? category = _asString(json['category']);
    if (category != null && draft.category == 'Other') {
      draft.category = _titleCase(category);
      applied = true;
    }

    final String? frequency = _asString(json['frequency'])?.toLowerCase();
    if (frequency != null &&
        <String>['daily', 'weekly', 'monthly'].contains(frequency)) {
      draft.frequencyType = frequency;
      applied = true;
    }

    final double? target = _asDouble(json['target']);
    if (target != null && target > 0 && draft.goalTarget <= 0) {
      draft.goalTarget = target;
      applied = true;
    }

    if (modelConfidence > 0) {
      draft.confidence =
          ((draft.confidence + modelConfidence) / 2).clamp(0.0, 1.0);
    }

    return applied;
  }

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

    // Walk forward to the matching closing brace so trailing prose is ignored.
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
    if (value.contains('note') || value.contains('idea')) {
      return CaptureType.note;
    }
    return null;
  }

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
        RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(t);
    if (match == null) return base;
    final int hour = int.parse(match.group(1)!).clamp(0, 23);
    final int minute = int.parse(match.group(2)!).clamp(0, 59);
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

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

  static String _weekdayName(int weekday) => const <String>[
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][(weekday - 1).clamp(0, 6)];
}
