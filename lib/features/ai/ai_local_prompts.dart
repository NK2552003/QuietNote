/// Compact, task-specific system prompts optimised for small local models
/// (Gemma 270M / Gemma 3N). Long prompts confuse small models — each method
/// here produces the shortest prompt that reliably elicits the target output.
///
/// All methods are pure functions; they only build strings and never call the
/// model themselves. The actual inference goes through [AiEngineNotifier] in
/// [local_ai_engine.dart].
class AiLocalPrompts {
  AiLocalPrompts._();

  // -------------------------------------------------------------------------
  // Type detection
  // -------------------------------------------------------------------------

  /// Returns a minimal prompt asking the model to classify [text] into one of
  /// the 10 QuietNote types. Expects a bare JSON object: {"type":"todo"}.
  static String detectType(String text, DateTime now) {
    final today = _date(now);
    return '''Classify this note into ONE type. Reply with ONLY {"type":"<value>"}.
Types: todo, event, habit, routine, goal, journal, note, flashcard, course, focus_session
Today: $today

Note: "$text"''';
  }

  // -------------------------------------------------------------------------
  // Flashcard generation
  // -------------------------------------------------------------------------

  /// Asks the model to generate [count] flashcard Q&A pairs for [topic].
  /// Expects a JSON array: [{"front":"Q","back":"A"}, ...]
  static String generateFlashcards(String topic, {int count = 5}) {
    return '''Create $count flashcard pairs about: "$topic"
Reply ONLY with a JSON array, nothing else:
[{"front":"question","back":"answer"}, ...]
Keep each front under 15 words and each back under 25 words.''';
  }

  // -------------------------------------------------------------------------
  // Goal milestones
  // -------------------------------------------------------------------------

  /// Asks the model to suggest 3 milestone steps for a goal.
  /// Expects a JSON array of strings: ["Milestone 1", "Milestone 2", ...]
  static String suggestMilestones(
      String title, double target, String? unit) {
    final unitStr = unit != null && unit.isNotEmpty ? ' $unit' : '';
    return '''Suggest 3 milestone steps to achieve this goal: "$title" (target: $target$unitStr)
Reply ONLY with a JSON array of short strings:
["Step 1", "Step 2", "Step 3"]
Each step under 10 words.''';
  }

  // -------------------------------------------------------------------------
  // Title polishing
  // -------------------------------------------------------------------------

  /// Asks the model to clean up a raw capture title for [type].
  /// Expects a plain string with no JSON or markdown.
  static String cleanTitle(String rawText, String type) {
    return '''Rewrite this as a clear, short $type title (max 70 chars, no punctuation at end):
"$rawText"
Reply with ONLY the improved title, nothing else.''';
  }

  // -------------------------------------------------------------------------
  // Subtask generation
  // -------------------------------------------------------------------------

  /// Asks the model to generate 3-5 actionable subtasks for a to-do.
  /// Expects a JSON array of strings: ["Subtask 1", "Subtask 2", ...]
  static String generateSubtasks(String taskTitle) {
    return '''Break down this task into 3-4 actionable subtasks: "$taskTitle"
Reply ONLY with a JSON array of short strings, nothing else:
["Subtask 1", "Subtask 2", "Subtask 3"]
Each subtask under 8 words.''';
  }

  // -------------------------------------------------------------------------
  // Structured Markdown Note Prompt
  // -------------------------------------------------------------------------

  /// Asks the model to write a well-formatted note in Markdown.
  static String formatNoteMarkdown(String topic) {
    return '''Write a concise, well-structured study note about: "$topic"
Format with Markdown:
- Use ## Headings for key concepts
- Use bullet points for main takeaways
- Bold important definitions and terms
- Keep it clear, informative, and student-ready.''';
  }

  // -------------------------------------------------------------------------
  // Field enrichment (for the full online system prompt path)
  // -------------------------------------------------------------------------

  /// Extended system prompt used by the API backend for structured capture
  /// extraction. Handles all 10 types in one call.
  static String captureSystemPrompt(DateTime now) {
    final today = _date(now);
    final weekday = _weekday(now.weekday);
    final time = '${_pad(now.hour)}:${_pad(now.minute)}';
    return '''You extract structured entries for QuietNote, a student productivity app.
Today: $weekday, $today. Time: $time.

Reply with ONE JSON object only. No markdown, no explanation.

Shape:
{
  "type": "todo|event|habit|routine|goal|journal|note|flashcard|course|focus_session",
  "title": "short title, max 70 chars",
  "details": "extra context or empty string",
  "date": "YYYY-MM-DD or empty",
  "time": "HH:MM or empty",
  "end_time": "HH:MM or empty",
  "priority": 0,
  "mood": "Great|Neutral|Bad",
  "category": "Health|Work|Personal|Learning|Finance|Other",
  "frequency": "daily|weekly|monthly",
  "target": 0,
  "unit": "",
  "course_code": "",
  "instructor": "",
  "room": "",
  "term": "",
  "target_grade": 0,
  "focus_preset": "pomodoro|deepWork|quickReview|custom",
  "confidence": 0.0,
  "flashcard_topic": ""
}

Rules:
- priority: 0=none, 1=low, 2=medium, 3=high
- target: numeric goal amount, else 0
- confidence: 0.0–1.0 for type certainty
- Resolve relative dates against today
- For flashcard: set flashcard_topic to the study subject
- For focus_session: set focus_preset
- Never invent facts not implied by the text''';
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String _date(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _weekday(int weekday) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ][(weekday - 1).clamp(0, 6)];
}
