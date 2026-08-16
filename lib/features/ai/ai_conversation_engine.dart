import 'package:flutter/material.dart';

import 'ai_question_model.dart';
import 'capture_parser.dart';

// ---------------------------------------------------------------------------
// Session state — immutable snapshot passed between steps.
// ---------------------------------------------------------------------------

class AiConversationSession {
  const AiConversationSession({
    required this.type,
    required this.draft,
    required this.steps,
    required this.completedAnswers,
    required this.currentStepIndex,
    this.isComplete = false,
  });

  final CaptureType type;
  final CaptureDraft draft;

  /// Full ordered list of steps for this type.
  final List<AiConversationStep> steps;

  /// One entry per step answered (or skipped) so far.
  final List<AiCompletedAnswer> completedAnswers;

  /// Index into [steps] for the step currently shown. -1 before start.
  final int currentStepIndex;

  final bool isComplete;

  int get totalSteps => steps.length;
  int get answeredCount => completedAnswers.length;

  AiConversationStep? get currentStep =>
      (currentStepIndex >= 0 && currentStepIndex < steps.length)
          ? steps[currentStepIndex]
          : null;

  double get progress =>
      totalSteps == 0 ? 1.0 : (answeredCount / totalSteps).clamp(0.0, 1.0);

  AiConversationSession copyWith({
    CaptureDraft? draft,
    List<AiConversationStep>? steps,
    List<AiCompletedAnswer>? completedAnswers,
    int? currentStepIndex,
    bool? isComplete,
  }) =>
      AiConversationSession(
        type: type,
        draft: draft ?? this.draft,
        steps: steps ?? this.steps,
        completedAnswers: completedAnswers ?? this.completedAnswers,
        currentStepIndex: currentStepIndex ?? this.currentStepIndex,
        isComplete: isComplete ?? this.isComplete,
      );
}

// ---------------------------------------------------------------------------
// The engine — pure Dart, no Flutter, no providers.
// ---------------------------------------------------------------------------

class AiConversationEngine {
  const AiConversationEngine._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Creates the initial session for [type] using [initial] as the seed draft.
  static AiConversationSession start(
    CaptureType type,
    CaptureDraft initial,
  ) {
    final steps = _buildSteps(type, initial);
    return AiConversationSession(
      type: type,
      draft: initial.copy(),
      steps: steps,
      completedAnswers: const [],
      currentStepIndex: steps.isEmpty ? -1 : 0,
      isComplete: steps.isEmpty,
    );
  }

  /// Records [value] for the current step and advances to the next.
  static AiConversationSession answer(
    AiConversationSession session,
    dynamic value,
  ) {
    final step = session.currentStep;
    if (step == null) return session;

    final updated = _applyAnswer(session.draft.copy(), step.field, value);
    final newAnswers = [
      ...session.completedAnswers,
      AiCompletedAnswer(step: step, value: value),
    ];
    return _advance(session, updated, newAnswers);
  }

  /// Skips the current step (only works when step.optional is true).
  static AiConversationSession skip(AiConversationSession session) {
    final step = session.currentStep;
    if (step == null || !step.optional) return session;

    final newAnswers = [
      ...session.completedAnswers,
      AiCompletedAnswer(step: step, value: null),
    ];
    return _advance(session, session.draft, newAnswers);
  }

  /// Undoes the last answer and goes back one step.
  static AiConversationSession back(AiConversationSession session) {
    if (session.completedAnswers.isEmpty) return session;
    final newAnswers =
        session.completedAnswers.sublist(0, session.completedAnswers.length - 1);
    return session.copyWith(
      currentStepIndex: session.currentStepIndex - 1,
      completedAnswers: newAnswers,
      isComplete: false,
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static AiConversationSession _advance(
    AiConversationSession session,
    CaptureDraft draft,
    List<AiCompletedAnswer> answers,
  ) {
    final currentSteps = List<AiConversationStep>.from(session.steps);

    // Adaptive branching: If user chooses 'Study' for habit, offer course linking
    if (draft.type == CaptureType.habit && draft.category == 'Study') {
      final hasCourseStep = currentSteps.any((s) => s.field == 'courseId');
      if (!hasCourseStep) {
        final insertIndex = (session.currentStepIndex + 1).clamp(0, currentSteps.length);
        currentSteps.insert(
          insertIndex,
          const AiConversationStep(
            field: 'courseId',
            question: 'Link this study habit to a course?',
            subtitle: 'Optionally associate it with your course tracker.',
            answerType: AiAnswerType.radioChips,
            optional: true,
            options: [],
          ),
        );
      }
    }

    final nextIndex = session.currentStepIndex + 1;
    final done = nextIndex >= currentSteps.length;
    return session.copyWith(
      draft: draft,
      steps: currentSteps,
      completedAnswers: answers,
      currentStepIndex: nextIndex,
      isComplete: done,
    );
  }

  /// Applies a single [field] answer [value] to [draft] in place, then returns [draft].
  static CaptureDraft _applyAnswer(
    CaptureDraft draft,
    String field,
    dynamic value,
  ) {
    if (value == null) return draft;
    switch (field) {
      // ── shared ──
      case 'title':
        draft.title = value.toString();
      case 'details':
        draft.details = value.toString();
      case 'priority':
        draft.priority = (value as int?) ?? 0;
      case 'category':
        draft.category = value.toString();
      case 'mood':
        draft.mood = value.toString();
      case 'dueDate':
        draft.dueDate = value as DateTime?;
      case 'startTime':
        draft.startTime = value as DateTime?;
      case 'endTime':
        draft.endTime = value as DateTime?;
      case 'courseId':
        draft.courseId = value?.toString();
      case 'tags':
        if (value is List) {
          draft.tags = value.cast<String>();
        } else if (value is String && value.isNotEmpty) {
          draft.tags = value.split(',').map((t) => t.trim()).toList();
        }
      // ── habit ──
      case 'frequencyType':
        draft.frequencyType = value.toString();
      case 'habitNotes':
        draft.habitNotes = value.toString();
      case 'habitGoalTarget':
        draft.habitGoalTarget = double.tryParse(value.toString());
      case 'habitGoalUnit':
        draft.habitGoalUnit = value.toString();
      // ── goal ──
      case 'goalTarget':
        draft.goalTarget = double.tryParse(value.toString()) ?? draft.goalTarget;
      case 'goalUnit':
        draft.goalUnit = value.toString();
      case 'milestones':
        if (value is List) {
          draft.milestones = value.cast<String>();
        }
      // ── todo ──
      case 'subtasks':
        if (value is List) {
          draft.subtasks = value.cast<String>();
        } else if (value is String && value.isNotEmpty) {
          draft.subtasks = value.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      // ── flashcard ──
      case 'flashcardTitle':
        draft.title = value.toString();
      case 'flashcardSubjects':
        if (value is List) {
          draft.flashcardSubjects = value.cast<String>();
        } else if (value is String && value.isNotEmpty) {
          draft.flashcardSubjects = value.split(',').map((t) => t.trim()).toList();
        }
      case 'flashcardPairs':
        if (value is List) {
          draft.flashcardPairs = value.cast<AiFlashcardPair>();
        }
      // ── course ──
      case 'courseName':
        draft.title = value.toString();
      case 'courseCode':
        draft.courseCode = value.toString();
      case 'courseInstructor':
        draft.courseInstructor = value.toString();
      case 'courseRoom':
        draft.courseRoom = value.toString();
      case 'courseTerm':
        draft.courseTerm = value.toString();
      case 'courseTargetGrade':
        draft.courseTargetGrade = double.tryParse(value.toString());
      case 'courseNotes':
        draft.courseNotes = value.toString();
      // ── focus session ──
      case 'focusPresetId':
        draft.focusPresetId = value.toString();
      case 'focusDurationMinutes':
        draft.focusDurationMinutes = int.tryParse(value.toString()) ?? 25;
      case 'focusLinkedCourseId':
        draft.focusLinkedCourseId = value?.toString();
    }
    return draft;
  }

  // ── Question tree builders ────────────────────────────────────────────────

  static List<AiConversationStep> _buildSteps(
      CaptureType type, CaptureDraft initial) {
    switch (type) {
      case CaptureType.todo:
        return _todoSteps(initial);
      case CaptureType.note:
        return _noteSteps(initial);
      case CaptureType.journal:
        return _journalSteps(initial);
      case CaptureType.habit:
        return _habitSteps(initial);
      case CaptureType.routine:
        return _routineSteps(initial);
      case CaptureType.goal:
        return _goalSteps(initial);
      case CaptureType.event:
        return _eventSteps(initial);
      case CaptureType.flashcard:
        return _flashcardSteps(initial);
      case CaptureType.course:
        return _courseSteps(initial);
      case CaptureType.focusSession:
        return _focusSteps(initial);
    }
  }

  // ── Todo ──────────────────────────────────────────────────────────────────

  static List<AiConversationStep> _todoSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'What do you need to do?',
          subtitle: 'Give it a clear, actionable title.',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Submit assignment, Call doctor…',
          defaultValue: d.title,
        ),
        AiConversationStep(
          field: 'details',
          question: 'Any extra details?',
          answerType: AiAnswerType.multilineText,
          hintText: 'Steps, links, notes… (optional)',
          optional: true,
          defaultValue: d.details == d.sourceText ? '' : d.details,
        ),
        AiConversationStep(
          field: 'priority',
          question: 'How important is this?',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.priority,
          options: const [
            AiRadioOption(value: 0, label: 'None', icon: Icons.remove),
            AiRadioOption(value: 1, label: 'Low', icon: Icons.arrow_downward),
            AiRadioOption(value: 2, label: 'Medium', icon: Icons.arrow_upward),
            AiRadioOption(value: 3, label: 'High', icon: Icons.priority_high),
          ],
        ),
        AiConversationStep(
          field: 'dueDate',
          question: 'When is it due?',
          answerType: AiAnswerType.dateTime,
          optional: true,
          defaultValue: d.dueDate,
        ),
        const AiConversationStep(
          field: 'subtasks',
          question: 'Any subtasks to track?',
          subtitle: 'Enter each subtask on a new line.',
          answerType: AiAnswerType.multilineText,
          optional: true,
          hintText: 'Research topic\nWrite outline\nFirst draft…',
        ),
      ];

  // ── Note ──────────────────────────────────────────────────────────────────

  static List<AiConversationStep> _noteSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'What\'s this note about?',
          answerType: AiAnswerType.text,
          hintText: 'Give it a clear title',
          defaultValue: d.title,
        ),
        AiConversationStep(
          field: 'details',
          question: 'Write your note content.',
          answerType: AiAnswerType.multilineText,
          hintText: 'Full note, ideas, reference…',
          defaultValue: d.details == d.sourceText ? '' : d.details,
          optional: true,
        ),
        const AiConversationStep(
          field: 'tags',
          question: 'Add any tags or subjects?',
          subtitle: 'Separate with commas (e.g. Biology, Exam prep)',
          answerType: AiAnswerType.text,
          hintText: 'Biology, Chemistry, Exam…',
          optional: true,
        ),
      ];

  // ── Journal ───────────────────────────────────────────────────────────────

  static List<AiConversationStep> _journalSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'Give this entry a title.',
          subtitle: 'Or keep the default — it\'s just for scanning later.',
          answerType: AiAnswerType.text,
          hintText: 'e.g. A productive Wednesday',
          defaultValue: d.title,
          optional: true,
        ),
        AiConversationStep(
          field: 'details',
          question: 'What\'s on your mind?',
          subtitle: 'Write freely — this is private.',
          answerType: AiAnswerType.multilineText,
          hintText: 'Today I…',
          defaultValue: d.details == d.sourceText ? '' : d.details,
        ),
        AiConversationStep(
          field: 'mood',
          question: 'How are you feeling?',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.mood,
          options: const [
            AiRadioOption(value: 'Great', label: 'Great', icon: Icons.sentiment_very_satisfied_outlined),
            AiRadioOption(value: 'Neutral', label: 'Neutral', icon: Icons.sentiment_neutral_outlined),
            AiRadioOption(value: 'Bad', label: 'Bad', icon: Icons.sentiment_very_dissatisfied_outlined),
          ],
        ),
      ];

  // ── Habit ─────────────────────────────────────────────────────────────────

  static List<AiConversationStep> _habitSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'Name this habit.',
          subtitle: 'Keep it short and motivating.',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Read 20 pages, Exercise, Meditate',
          defaultValue: d.title,
        ),
        AiConversationStep(
          field: 'category',
          question: 'What category fits best?',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.category,
          options: const [
            AiRadioOption(value: 'Health', label: 'Health', icon: Icons.favorite_outline),
            AiRadioOption(value: 'Fitness', label: 'Fitness', icon: Icons.fitness_center_outlined),
            AiRadioOption(value: 'Study', label: 'Study', icon: Icons.school_outlined),
            AiRadioOption(value: 'Mindfulness', label: 'Mindful', icon: Icons.self_improvement_outlined),
            AiRadioOption(value: 'Productivity', label: 'Productiv.', icon: Icons.bolt_outlined),
            AiRadioOption(value: 'Sleep', label: 'Sleep', icon: Icons.bedtime_outlined),
            AiRadioOption(value: 'Social', label: 'Social', icon: Icons.people_outline),
            AiRadioOption(value: 'Other', label: 'Other', icon: Icons.category_outlined),
          ],
        ),
        AiConversationStep(
          field: 'frequencyType',
          question: 'How often will you do it?',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.frequencyType,
          options: const [
            AiRadioOption(value: 'daily', label: 'Every day', icon: Icons.today_outlined),
            AiRadioOption(value: 'specificDays', label: 'Specific days', icon: Icons.calendar_month_outlined),
            AiRadioOption(value: 'interval', label: 'Every few days', icon: Icons.repeat_outlined),
          ],
        ),
        const AiConversationStep(
          field: 'habitGoalTarget',
          question: 'Set a measurable target? (optional)',
          subtitle: 'e.g. 20 pages, 30 minutes, 8 glasses',
          answerType: AiAnswerType.number,
          hintText: 'Amount (e.g. 20)',
          optional: true,
        ),
        const AiConversationStep(
          field: 'habitGoalUnit',
          question: 'What\'s the unit?',
          subtitle: 'pages, minutes, glasses, km…',
          answerType: AiAnswerType.text,
          hintText: 'pages, minutes, glasses…',
          optional: true,
        ),
        const AiConversationStep(
          field: 'habitNotes',
          question: 'Any notes or motivation?',
          answerType: AiAnswerType.multilineText,
          hintText: 'Why this habit matters to you…',
          optional: true,
        ),
      ];

  // ── Routine ───────────────────────────────────────────────────────────────

  static List<AiConversationStep> _routineSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'Name your routine.',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Morning power-up, Wind-down',
          defaultValue: d.title,
        ),
        const AiConversationStep(
          field: 'category',
          question: 'When does this routine happen?',
          answerType: AiAnswerType.radioChips,
          defaultValue: 'Evening',
          options: [
            AiRadioOption(value: 'Morning', label: 'Morning', icon: Icons.wb_sunny_outlined),
            AiRadioOption(value: 'Afternoon', label: 'Afternoon', icon: Icons.light_mode_outlined),
            AiRadioOption(value: 'Evening', label: 'Evening', icon: Icons.wb_twilight_outlined),
            AiRadioOption(value: 'Night', label: 'Night', icon: Icons.bedtime_outlined),
          ],
        ),
        const AiConversationStep(
          field: 'details',
          question: 'Describe what this routine involves.',
          answerType: AiAnswerType.multilineText,
          hintText: 'Brush teeth, journal, read for 15 min…',
          optional: true,
        ),
      ];

  // ── Goal ──────────────────────────────────────────────────────────────────

  static List<AiConversationStep> _goalSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'What\'s your goal?',
          subtitle: 'State it clearly and positively.',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Run a 5K, Save for laptop…',
          defaultValue: d.title,
        ),
        AiConversationStep(
          field: 'category',
          question: 'Which area of life?',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.category,
          options: const [
            AiRadioOption(value: 'Career', label: 'Career', icon: Icons.work_outline),
            AiRadioOption(value: 'Health', label: 'Health', icon: Icons.favorite_outline),
            AiRadioOption(value: 'Finance', label: 'Finance', icon: Icons.account_balance_wallet_outlined),
            AiRadioOption(value: 'Learning', label: 'Learning', icon: Icons.school_outlined),
            AiRadioOption(value: 'Personal', label: 'Personal', icon: Icons.person_outline),
            AiRadioOption(value: 'Relationships', label: 'Relations', icon: Icons.people_outline),
            AiRadioOption(value: 'Travel', label: 'Travel', icon: Icons.flight_outlined),
            AiRadioOption(value: 'Other', label: 'Other', icon: Icons.category_outlined),
          ],
        ),
        AiConversationStep(
          field: 'goalTarget',
          question: 'What\'s the target number?',
          subtitle: 'e.g. 500 (dollars), 5 (km), 50 (books)',
          answerType: AiAnswerType.number,
          hintText: 'Target amount',
          defaultValue: d.goalTarget > 0 ? d.goalTarget.toStringAsFixed(0) : '',
        ),
        const AiConversationStep(
          field: 'goalUnit',
          question: 'What unit is that in?',
          subtitle: 'e.g. dollars, km, books, pages, kg',
          answerType: AiAnswerType.text,
          hintText: 'dollars, km, books…',
          optional: true,
        ),
        AiConversationStep(
          field: 'priority',
          question: 'How important is this goal to you?',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.priority,
          options: const [
            AiRadioOption(value: 0, label: 'Normal', icon: Icons.remove),
            AiRadioOption(value: 1, label: 'Low', icon: Icons.arrow_downward),
            AiRadioOption(value: 2, label: 'Medium', icon: Icons.arrow_upward),
            AiRadioOption(value: 3, label: 'High', icon: Icons.priority_high),
          ],
        ),
        AiConversationStep(
          field: 'dueDate',
          question: 'When do you want to achieve this by?',
          answerType: AiAnswerType.dateOnly,
          optional: true,
          defaultValue: d.dueDate,
        ),
      ];

  // ── Event ─────────────────────────────────────────────────────────────────

  static List<AiConversationStep> _eventSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'title',
          question: 'What\'s the event?',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Team sync, Doctor appointment…',
          defaultValue: d.title,
        ),
        AiConversationStep(
          field: 'startTime',
          question: 'When does it start?',
          answerType: AiAnswerType.dateTime,
          defaultValue: d.startTime ?? DateTime.now().add(const Duration(hours: 1)),
        ),
        AiConversationStep(
          field: 'endTime',
          question: 'When does it end?',
          answerType: AiAnswerType.dateTime,
          defaultValue: d.endTime ??
              (d.startTime ?? DateTime.now().add(const Duration(hours: 1)))
                  .add(const Duration(hours: 1)),
          optional: true,
        ),
        const AiConversationStep(
          field: 'details',
          question: 'Any description or location?',
          answerType: AiAnswerType.multilineText,
          hintText: 'Room 204, Zoom link, agenda…',
          optional: true,
        ),
        const AiConversationStep(
          field: 'category',
          question: 'What type of event?',
          answerType: AiAnswerType.radioChips,
          defaultValue: 'Other',
          optional: true,
          options: [
            AiRadioOption(value: 'Academic', label: 'Academic', icon: Icons.school_outlined),
            AiRadioOption(value: 'Personal', label: 'Personal', icon: Icons.person_outline),
            AiRadioOption(value: 'Work', label: 'Work', icon: Icons.work_outline),
            AiRadioOption(value: 'Health', label: 'Health', icon: Icons.favorite_outline),
            AiRadioOption(value: 'Social', label: 'Social', icon: Icons.people_outline),
            AiRadioOption(value: 'Other', label: 'Other', icon: Icons.event_outlined),
          ],
        ),
      ];

  // ── Flashcard ─────────────────────────────────────────────────────────────

  static List<AiConversationStep> _flashcardSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'flashcardTitle',
          question: 'Name this flashcard deck.',
          subtitle: 'Usually the topic or chapter you\'re studying.',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Organic Chemistry Ch.3, Spanish Verbs…',
          defaultValue: d.title,
        ),
        const AiConversationStep(
          field: 'flashcardSubjects',
          question: 'Any subject tags?',
          subtitle: 'Helps you filter decks later. Separate with commas.',
          answerType: AiAnswerType.text,
          hintText: 'Chemistry, Biology, Spanish…',
          optional: true,
        ),
        const AiConversationStep(
          field: 'courseId',
          question: 'Link to a course?',
          subtitle: 'Deck will appear in the course\'s Flashcards tab.',
          answerType: AiAnswerType.radioChips,
          optional: true,
          // Options are injected dynamically by the AI screen from the DB
          options: [],
        ),
        // Preview step — AI-generated card pairs shown for review/editing
        const AiConversationStep(
          field: 'flashcardPairs',
          question: 'Here are the cards I\'ve prepared. Review and edit them.',
          subtitle: 'Tap any card to edit. Add or remove pairs as needed.',
          answerType: AiAnswerType.preview,
        ),
      ];

  // ── Course ────────────────────────────────────────────────────────────────

  static List<AiConversationStep> _courseSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'courseName',
          question: 'What\'s the course called?',
          answerType: AiAnswerType.text,
          hintText: 'e.g. Introduction to Biology',
          defaultValue: d.title,
        ),
        const AiConversationStep(
          field: 'courseCode',
          question: 'Course code?',
          subtitle: 'e.g. BIO101, CS301',
          answerType: AiAnswerType.text,
          hintText: 'BIO101',
          optional: true,
        ),
        const AiConversationStep(
          field: 'courseInstructor',
          question: 'Who\'s teaching it?',
          answerType: AiAnswerType.text,
          hintText: 'Dr. Smith, Prof. Johnson…',
          optional: true,
        ),
        const AiConversationStep(
          field: 'courseRoom',
          question: 'Where does it meet?',
          answerType: AiAnswerType.text,
          hintText: 'Room 204, Online, Lab B…',
          optional: true,
        ),
        const AiConversationStep(
          field: 'courseTerm',
          question: 'Which term or semester?',
          answerType: AiAnswerType.text,
          hintText: 'Fall 2025, Spring 2026…',
          optional: true,
        ),
        const AiConversationStep(
          field: 'courseTargetGrade',
          question: 'Target grade? (optional)',
          subtitle: 'Enter a percentage e.g. 85 for 85%',
          answerType: AiAnswerType.number,
          hintText: '85',
          optional: true,
        ),
      ];

  // ── Focus Session ─────────────────────────────────────────────────────────

  static List<AiConversationStep> _focusSteps(CaptureDraft d) => [
        AiConversationStep(
          field: 'focusPresetId',
          question: 'Choose a focus session type.',
          answerType: AiAnswerType.radioChips,
          defaultValue: d.focusPresetId ?? 'pomodoro',
          options: const [
            AiRadioOption(value: 'pomodoro', label: 'Pomodoro 25/5', icon: Icons.timer_outlined),
            AiRadioOption(value: 'deepWork', label: 'Deep Work 50/10', icon: Icons.psychology_outlined),
            AiRadioOption(value: 'quickReview', label: 'Quick Review 15', icon: Icons.bolt_outlined),
            AiRadioOption(value: 'custom', label: 'Custom', icon: Icons.tune_outlined),
          ],
        ),
        const AiConversationStep(
          field: 'focusLinkedCourseId',
          question: 'Studying for a specific course?',
          subtitle: 'Helps track focus time per subject.',
          answerType: AiAnswerType.radioChips,
          optional: true,
          // Options injected dynamically by the AI screen
          options: [],
        ),
      ];
}
