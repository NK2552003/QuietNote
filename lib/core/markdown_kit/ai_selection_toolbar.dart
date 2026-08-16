import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/ai/capture_parser.dart';

/// Floating accessory bar shown above the keyboard formatting toolbar when
/// text is selected in the note or journal editor.
class AiRefactorBar extends StatelessWidget {
  const AiRefactorBar({
    super.key,
    required this.refactoring,
    required this.selectedCharCount,
    required this.onQuickRefactor,
    required this.onCustomPrompt,
    required this.onDismiss,
  });

  final bool refactoring;
  final int selectedCharCount;
  final VoidCallback onQuickRefactor;
  final VoidCallback onCustomPrompt;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.primary.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: c.primary),
            const SizedBox(width: 8),
            Text(
              selectedCharCount > 0 ? '$selectedCharCount chars' : 'Selected',
              style: context.uiText.caption.copyWith(
                color: c.foregroundMuted,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            if (refactoring) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AI Writing…',
                style: context.uiText.caption.copyWith(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ] else ...[
              // Custom Prompt button
              GestureDetector(
                onTap: onCustomPrompt,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: c.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded,
                          size: 15, color: c.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Prompt AI',
                        style: context.uiText.caption.copyWith(
                          color: c.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Quick enhance button
              GestureDetector(
                onTap: onQuickRefactor,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 13, color: c.onPrimary),
                      const SizedBox(width: 4),
                      Text(
                        'Enhance',
                        style: context.uiText.caption.copyWith(
                          color: c.onPrimary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close_rounded,
                    size: 18, color: c.foregroundMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Interactive modal bottom sheet where users can type custom instructions to
/// rewrite, expand, or format the selected text with AI.
class AiCustomPromptSheet extends StatefulWidget {
  const AiCustomPromptSheet({
    super.key,
    required this.selectedText,
    required this.type,
    required this.onApply,
  });

  final String selectedText;
  final CaptureType type;
  final Future<void> Function(String prompt) onApply;

  @override
  State<AiCustomPromptSheet> createState() => _AiCustomPromptSheetState();
}

class _AiCustomPromptSheetState extends State<AiCustomPromptSheet> {
  final TextEditingController _promptController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  static const List<String> _noteSuggestions = <String>[
    'Write comprehensive detailed markdown study notes on this',
    'Explain in simple terms with real-world analogies',
    'Summarize key points into structured bullet points',
    'Fix grammar, polish tone, and enhance vocabulary',
    'Create 5 study questions and answers based on this',
    'Expand into a 1000-word comprehensive guide in Markdown',
  ];

  static const List<String> _journalSuggestions = <String>[
    'Expand this into a reflective, mindful journal entry',
    'Deepen the emotional insight and self-reflection',
    'Fix flow and polish prose while keeping personal voice',
    'Add thought-provoking reflection prompts for tomorrow',
  ];

  Future<void> _submit(String prompt) async {
    final String text = prompt.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onApply(text);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> suggestions = widget.type == CaptureType.journal
        ? _journalSuggestions
        : _noteSuggestions;

    final String preview = widget.selectedText.length > 100
        ? '${widget.selectedText.substring(0, 100)}…'
        : widget.selectedText;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: c.primary.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.auto_awesome_rounded,
                      size: 18, color: c.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transform with AI',
                        style: context.uiText.subheading.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Type your prompt or tap a preset below',
                        style: context.uiText.caption.copyWith(
                          color: c.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Selected text preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.format_quote_rounded,
                      size: 16, color: c.foregroundMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preview,
                      style: context.uiText.caption.copyWith(
                        fontStyle: FontStyle.italic,
                        color: c.foregroundMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Prompt input
            TextField(
              controller: _promptController,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              style: context.uiText.body,
              decoration: InputDecoration(
                hintText:
                    'e.g. Help me write 1000 words on this in markdown, summarize into bullet points, or explain simply…',
                hintStyle: context.uiText.caption.copyWith(
                  color: c.foregroundMuted,
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.02),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Suggestions header & chips
            Text(
              'Quick Prompts',
              style: context.uiText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: c.foregroundMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final String s in suggestions)
                  InkWell(
                    onTap: () {
                      _promptController.text = s;
                      _promptController.selection = TextSelection.collapsed(
                        offset: s.length,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(
                        s,
                        style: context.uiText.caption.copyWith(
                          fontSize: 11,
                          color: c.foreground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            // Submit button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _submitting
                    ? null
                    : () => _submit(_promptController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _submitting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(c.onPrimary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('Generating with AI…'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Transform Selection',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
