import 'package:flutter/material.dart';

import 'ai_question_model.dart';

// ---------------------------------------------------------------------------
// Capture types — every destination a thought can become.
// ---------------------------------------------------------------------------

enum CaptureType {
  todo,
  event,
  habit,
  routine,
  goal,
  journal,
  note,
  flashcard,
  course,
  focusSession,
}

extension CaptureTypeX on CaptureType {
  String get label {
    switch (this) {
      case CaptureType.todo:
        return 'To-do';
      case CaptureType.event:
        return 'Calendar event';
      case CaptureType.habit:
        return 'Habit';
      case CaptureType.routine:
        return 'Routine';
      case CaptureType.goal:
        return 'Goal';
      case CaptureType.journal:
        return 'Journal entry';
      case CaptureType.note:
        return 'Note';
      case CaptureType.flashcard:
        return 'Flashcard deck';
      case CaptureType.course:
        return 'Course';
      case CaptureType.focusSession:
        return 'Focus session';
    }
  }

  String get shortLabel {
    switch (this) {
      case CaptureType.todo:
        return 'To-do';
      case CaptureType.event:
        return 'Event';
      case CaptureType.habit:
        return 'Habit';
      case CaptureType.routine:
        return 'Routine';
      case CaptureType.goal:
        return 'Goal';
      case CaptureType.journal:
        return 'Journal';
      case CaptureType.note:
        return 'Note';
      case CaptureType.flashcard:
        return 'Flashcards';
      case CaptureType.course:
        return 'Course';
      case CaptureType.focusSession:
        return 'Focus';
    }
  }

  String get emoji {
    switch (this) {
      case CaptureType.todo:
        return '✅';
      case CaptureType.event:
        return '📅';
      case CaptureType.habit:
        return '🔁';
      case CaptureType.routine:
        return '🌅';
      case CaptureType.goal:
        return '🎯';
      case CaptureType.journal:
        return '📖';
      case CaptureType.note:
        return '📝';
      case CaptureType.flashcard:
        return '🃏';
      case CaptureType.course:
        return '🎓';
      case CaptureType.focusSession:
        return '⏱';
    }
  }

  IconData get icon {
    switch (this) {
      case CaptureType.todo:
        return Icons.check_circle_outline;
      case CaptureType.event:
        return Icons.event_outlined;
      case CaptureType.habit:
        return Icons.repeat_rounded;
      case CaptureType.routine:
        return Icons.route_outlined;
      case CaptureType.goal:
        return Icons.flag_outlined;
      case CaptureType.journal:
        return Icons.menu_book_outlined;
      case CaptureType.note:
        return Icons.notes_outlined;
      case CaptureType.flashcard:
        return Icons.style_outlined;
      case CaptureType.course:
        return Icons.school_outlined;
      case CaptureType.focusSession:
        return Icons.timer_outlined;
    }
  }

  /// True for types that go through a custom conversation flow rather than the
  /// generic draft-preview → review sheet path.
  bool get hasConversationFlow => true;
}

// ---------------------------------------------------------------------------
// A destination the parser considered, with its confidence score.
// ---------------------------------------------------------------------------

class CaptureSuggestion {
  const CaptureSuggestion(this.type, this.confidence);
  final CaptureType type;
  final double confidence;
}

// ---------------------------------------------------------------------------
// Editable result of parsing — fully populated by the conversation engine
// before anything is written to a repository.
// ---------------------------------------------------------------------------

class CaptureDraft {
  CaptureDraft({
    required this.type,
    required this.title,
    // ── shared ──
    this.details = '',
    this.dueDate,
    this.startTime,
    this.endTime,
    this.mood = 'Neutral',
    this.priority = 0,
    this.frequencyType = 'daily',
    this.goalTarget = 100,
    this.goalUnit = '',
    this.category = 'Other',
    this.tags = const [],
    this.courseId,
    this.alternates = const [],
    this.confidence = 0.5,
    this.sourceText = '',
    // ── habit ──
    this.habitNotes = '',
    this.habitGoalTarget,
    this.habitGoalUnit,
    // ── goal ──
    this.milestones = const [],
    // ── todo ──
    this.subtasks = const [],
    // ── flashcard ──
    this.flashcardPairs = const [],
    this.flashcardSubjects = const [],
    // ── course ──
    this.courseCode = '',
    this.courseInstructor = '',
    this.courseRoom = '',
    this.courseTerm = '',
    this.courseTargetGrade,
    this.courseNotes = '',
    // ── focus session ──
    this.focusPresetId,
    this.focusDurationMinutes = 25,
    this.focusLinkedCourseId,
    this.focusLinkedTaskId,
  });

  // ── core ──
  CaptureType type;
  String title;
  String details;
  DateTime? dueDate;
  DateTime? startTime;
  DateTime? endTime;
  String mood;
  int priority;
  String frequencyType;
  double goalTarget;
  String goalUnit;
  String category;
  List<String> tags;
  String? courseId;
  List<CaptureSuggestion> alternates;
  double confidence;
  String sourceText;

  // ── habit specific ──
  String habitNotes;
  double? habitGoalTarget;
  String? habitGoalUnit;

  // ── goal specific ──
  List<String> milestones;

  // ── todo specific ──
  List<String> subtasks;

  // ── flashcard specific ──
  List<AiFlashcardPair> flashcardPairs;
  List<String> flashcardSubjects;

  // ── course specific ──
  String courseCode;
  String courseInstructor;
  String courseRoom;
  String courseTerm;
  double? courseTargetGrade;
  String courseNotes;

  // ── focus session specific ──
  String? focusPresetId;
  int focusDurationMinutes;
  String? focusLinkedCourseId;
  String? focusLinkedTaskId;

  CaptureDraft copy() => CaptureDraft(
        type: type,
        title: title,
        details: details,
        dueDate: dueDate,
        startTime: startTime,
        endTime: endTime,
        mood: mood,
        priority: priority,
        frequencyType: frequencyType,
        goalTarget: goalTarget,
        goalUnit: goalUnit,
        category: category,
        tags: List<String>.from(tags),
        courseId: courseId,
        alternates: alternates,
        confidence: confidence,
        sourceText: sourceText,
        habitNotes: habitNotes,
        habitGoalTarget: habitGoalTarget,
        habitGoalUnit: habitGoalUnit,
        milestones: List<String>.from(milestones),
        subtasks: List<String>.from(subtasks),
        flashcardPairs: flashcardPairs
            .map((p) => AiFlashcardPair(front: p.front, back: p.back))
            .toList(),
        flashcardSubjects: List<String>.from(flashcardSubjects),
        courseCode: courseCode,
        courseInstructor: courseInstructor,
        courseRoom: courseRoom,
        courseTerm: courseTerm,
        courseTargetGrade: courseTargetGrade,
        courseNotes: courseNotes,
        focusPresetId: focusPresetId,
        focusDurationMinutes: focusDurationMinutes,
        focusLinkedCourseId: focusLinkedCourseId,
        focusLinkedTaskId: focusLinkedTaskId,
      );
}

// ---------------------------------------------------------------------------
// Heuristic classifier — runs instantly, no model required.
// ---------------------------------------------------------------------------

class CaptureParser {
  CaptureParser._();

  static const Map<CaptureType, List<String>> _keywords = {
    CaptureType.event: [
      'meeting', 'appointment', 'call with', 'sync', 'lunch with',
      'dinner with', 'catch up with', 'interview', 'flight', 'conference', 'appt',
    ],
    CaptureType.todo: [
      'buy', 'call', 'email', 'send', 'pay', 'pick up', 'todo', 'to-do',
      'need to', 'remember to', 'finish', 'submit', 'book ', 'renew',
      'return the', 'drop off', 'schedule', 'fix', 'clean', 'order',
    ],
    CaptureType.habit: [
      'every day', 'each day', 'daily', 'every morning', 'every night',
      'every week', 'habit', 'stop drinking', 'quit smoking', 'start doing',
      'want to build a habit', 'each morning', 'each evening',
    ],
    CaptureType.routine: [
      'routine', 'morning routine', 'evening routine', 'before bed',
      'my workflow', 'daily plan', 'sequence', 'ritual',
    ],
    CaptureType.goal: [
      'goal', 'by the end of', 'target of', 'achieve', 'want to reach',
      'milestone', 'aim to', 'save up', 'lose ', 'gain ', r'reach $',
    ],
    CaptureType.journal: [
      'today i', 'i feel', 'feeling', 'grateful', 'dear diary', 'reflecting',
      "i'm feeling", 'i am feeling', 'today was', 'i felt',
    ],
    CaptureType.flashcard: [
      'flashcard', 'flash card', 'study cards', 'make cards', 'deck for',
      'quiz cards', 'flashcards for', 'cards about',
    ],
    CaptureType.course: [
      'course', 'class', 'subject', 'semester', 'module', 'lecture',
      'enroll', 'enrolment', 'add course', 'new class',
    ],
    CaptureType.focusSession: [
      'pomodoro', 'focus session', 'study session', 'deep work',
      'timer for', 'work session', 'focus for', 'study for',
    ],
  };

  static const List<String> _weekdays = [
    'monday', 'tuesday', 'wednesday', 'thursday',
    'friday', 'saturday', 'sunday',
  ];

  static CaptureDraft parse(String raw, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final text = raw.trim();
    final lower = text.toLowerCase();

    final scores = <CaptureType, double>{
      for (final t in CaptureType.values) t: 0,
    };

    for (final entry in _keywords.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) {
          scores[entry.key] = (scores[entry.key] ?? 0) + 1;
        }
      }
    }

    final extractedTime = _extractDateTime(lower, clock);
    if (extractedTime != null) {
      scores[CaptureType.event] = (scores[CaptureType.event] ?? 0) + 1.4;
    }

    // Todo wins ties over the default Note.
    scores[CaptureType.todo] = (scores[CaptureType.todo] ?? 0) + 0.15;

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topScore = sorted.first.value;
    final CaptureType bestType =
        topScore <= 0.15 ? CaptureType.note : sorted.first.key;

    final totalSignal = scores.values.fold<double>(0, (a, b) => a + b);
    final confidence = totalSignal <= 0
        ? 0.4
        : (0.45 + (topScore / (totalSignal + 1)) * 0.5).clamp(0.35, 0.97);

    final alternates = sorted
        .where((e) => e.key != bestType && e.value > 0)
        .take(2)
        .map(
          (e) => CaptureSuggestion(
            e.key,
            (0.3 + e.value / (totalSignal + 1) * 0.5).clamp(0.1, 0.9),
          ),
        )
        .toList();

    final title = _titleFrom(text);

    DateTime? dueDate;
    DateTime? startTime;
    DateTime? endTime;
    if (bestType == CaptureType.event) {
      startTime = extractedTime ?? clock.add(const Duration(hours: 1));
      endTime = startTime.add(const Duration(hours: 1));
    } else if (extractedTime != null) {
      dueDate = extractedTime;
    }

    String mood = 'Neutral';
    if (bestType == CaptureType.journal) {
      if (lower.contains('grateful') || lower.contains('great') ||
          lower.contains('happy') || lower.contains('excited')) {
        mood = 'Great';
      } else if (lower.contains('sad') || lower.contains('tired') ||
          lower.contains('stressed') || lower.contains('anxious') ||
          lower.contains('bad')) {
        mood = 'Bad';
      }
    }

    // Detect a focus preset keyword so the conversation can pre-fill it.
    String? focusPresetId;
    if (bestType == CaptureType.focusSession) {
      if (lower.contains('pomodoro')) {
        focusPresetId = 'pomodoro';
      } else if (lower.contains('deep work') || lower.contains('50')) {
        focusPresetId = 'deepWork';
      } else if (lower.contains('quick') || lower.contains('15')) {
        focusPresetId = 'quickReview';
      }
    }

    return CaptureDraft(
      type: bestType,
      title: title,
      details: text,
      dueDate: dueDate,
      startTime: startTime,
      endTime: endTime,
      mood: mood,
      priority: lower.contains('urgent') || lower.contains('asap')
          ? 3
          : (lower.contains('important') ? 2 : 0),
      alternates: alternates,
      confidence: confidence,
      sourceText: text,
      focusPresetId: focusPresetId,
    );
  }

  static String _titleFrom(String text) {
    if (text.isEmpty) return 'Untitled capture';
    final firstLine = text.split(RegExp(r'[\n.!?]')).first.trim();
    final base = firstLine.isEmpty ? text : firstLine;
    if (base.length <= 72) return base;
    return '${base.substring(0, 69)}…';
  }

  static DateTime? _extractDateTime(String lower, DateTime now) {
    DateTime day = DateTime(now.year, now.month, now.day);
    bool matchedDay = false;

    if (lower.contains('tomorrow')) {
      day = day.add(const Duration(days: 1));
      matchedDay = true;
    } else if (lower.contains('today') || lower.contains('tonight')) {
      matchedDay = true;
    } else {
      for (var i = 0; i < _weekdays.length; i++) {
        if (lower.contains(_weekdays[i])) {
          final target = i + 1;
          var delta = target - now.weekday;
          if (delta <= 0) delta += 7;
          day = day.add(Duration(days: delta));
          matchedDay = true;
          break;
        }
      }
    }

    final timeMatch = RegExp(
      r'\b(\d{1,2})(:\d{2})?\s?(am|pm)\b',
    ).firstMatch(lower);
    if (timeMatch != null) {
      var hour = int.parse(timeMatch.group(1)!);
      final minuteStr = timeMatch.group(2);
      final minute = minuteStr != null ? int.parse(minuteStr.substring(1)) : 0;
      final isPm = timeMatch.group(3) == 'pm';
      if (hour == 12) hour = 0;
      if (isPm) hour += 12;
      return DateTime(day.year, day.month, day.day, hour, minute);
    }

    if (matchedDay) {
      return DateTime(day.year, day.month, day.day, 9, 0);
    }
    return null;
  }
}
