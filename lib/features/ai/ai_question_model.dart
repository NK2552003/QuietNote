import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Answer input types — drives which widget appears below the chat bubbles.
// ---------------------------------------------------------------------------

enum AiAnswerType {
  /// Single-line text field (title, tags, unit, instructor, etc.).
  text,

  /// Multi-line textarea (entry body, notes, details, description).
  multilineText,

  /// Row of tappable chips — tapping immediately advances to next step.
  radioChips,

  /// Full date + time picker (event start/end, task due date).
  dateTime,

  /// Date-only picker (goal deadline).
  dateOnly,

  /// Numeric UiInput (goal target, target grade, duration).
  number,

  /// Yes / No two-chip row for boolean answers.
  yesNo,

  /// Multi-select chip grid (days of week for habits).
  multiSelect,

  /// Static info step: shows AI-generated content (flashcard pairs preview)
  /// with an "Accept" / "Edit" pair of buttons.
  preview,
}

// ---------------------------------------------------------------------------
// A single selectable option in radioChips / multiSelect answers.
// ---------------------------------------------------------------------------

class AiRadioOption<T> {
  const AiRadioOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;

  String get displayLabel => label;
}

// ---------------------------------------------------------------------------
// One step in the conversation — maps to one AI question bubble + one answer.
// ---------------------------------------------------------------------------

class AiConversationStep {
  const AiConversationStep({
    required this.field,
    required this.question,
    required this.answerType,
    this.subtitle,
    this.options,
    this.optional = false,
    this.hintText,
    this.defaultValue,
    this.keyboardType,
  });

  /// Internal field key — used by [AiConversationEngine] to apply the answer
  /// to the right slot in [CaptureDraft].
  final String field;

  /// Text displayed as the AI's chat bubble question.
  final String question;

  /// Optional smaller context line below [question].
  final String? subtitle;

  final AiAnswerType answerType;

  /// Required when [answerType] is [AiAnswerType.radioChips] or
  /// [AiAnswerType.multiSelect].
  final List<AiRadioOption>? options;

  /// When true the conversation shows a "Skip →" button.
  final bool optional;

  /// Placeholder shown inside text / number inputs.
  final String? hintText;

  /// Pre-filled value shown in the answer widget.
  final dynamic defaultValue;

  /// Override keyboard type for [AiAnswerType.text] steps.
  final TextInputType? keyboardType;
}

// ---------------------------------------------------------------------------
// A completed answer — pairs the step that was answered with the value given.
// ---------------------------------------------------------------------------

class AiCompletedAnswer {
  const AiCompletedAnswer({required this.step, required this.value});

  final AiConversationStep step;

  /// The raw value: String, int, double, DateTime, bool, List<int>, etc.
  /// Null means the user tapped "Skip".
  final dynamic value;

  /// Human-readable label for the chat bubble recap.
  String get displayValue {
    if (value == null) return 'Skipped';
    if (value is DateTime) {
      final dt = value as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}'
          '${dt.hour != 0 || dt.minute != 0 ? ' ${_pad(dt.hour)}:${_pad(dt.minute)}' : ''}';
    }
    if (value is List) return (value as List).join(', ');
    if (value is bool) return (value as bool) ? 'Yes' : 'No';
    if (step.options != null) {
      final match = step.options!.cast<AiRadioOption>().where((o) => o.value == value).firstOrNull;
      if (match != null) return match.displayLabel;
    }
    return value.toString();
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

// ---------------------------------------------------------------------------
// A pair of flashcard question + answer — used during the preview step.
// ---------------------------------------------------------------------------

class AiFlashcardPair {
  AiFlashcardPair({required this.front, required this.back});

  String front;
  String back;
}
