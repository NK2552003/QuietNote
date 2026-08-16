import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// The raw multi-line text input for a markdown editor. Deliberately split
/// from the formatting toolbar (see [MarkdownEditorToolbar]) so the toolbar
/// can float in its own [Positioned] layer, pinned just above the on-screen
/// keyboard, while this field lives inline in the scrolling page content —
/// exactly like the accessory bar in Notes-style apps.
///
/// The toolbar drives this field through [RichMarkdownEditorFieldState]'s
/// public methods (reach it via the [GlobalKey] passed as `key`).
class RichMarkdownEditorField extends StatefulWidget {
  const RichMarkdownEditorField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.style,
    this.minLines = 10,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onChanged;
  final TextStyle? style;
  final int minLines;

  @override
  State<RichMarkdownEditorField> createState() => RichMarkdownEditorFieldState();
}

class RichMarkdownEditorFieldState extends State<RichMarkdownEditorField> {
  final UndoHistoryController undoController = UndoHistoryController();

  @override
  void dispose() {
    undoController.dispose();
    super.dispose();
  }

  /// Wraps the current selection with [prefix]/[suffix] (e.g. `**`/`**` for
  /// bold). With nothing selected, inserts both and leaves the cursor
  /// between them so typing continues right inside the markers.
  void wrapSelection(String prefix, String suffix) {
    final controller = widget.controller;
    final String text = controller.text;
    final TextSelection selection = controller.selection;

    if (!selection.isValid) {
      final String newText = '$text$prefix$suffix';
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length - suffix.length),
      );
    } else {
      final String selected = selection.textInside(text);
      final String newText = text.replaceRange(
        selection.start,
        selection.end,
        '$prefix$selected$suffix',
      );
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + prefix.length + selected.length,
        ),
      );
    }
    widget.onChanged?.call();
  }

  /// Inserts [prefix] at the very start of the current line — for line-level
  /// markers like `## `, `- `, `1. `, `> `, `- [ ] `.
  void prefixCurrentLine(String prefix) {
    final controller = widget.controller;
    final String text = controller.text;
    final TextSelection selection = controller.selection;
    final int cursor = selection.isValid ? selection.start : text.length;

    int lineStart = cursor == 0 ? -1 : text.lastIndexOf('\n', cursor - 1);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;

    final String newText = text.replaceRange(lineStart, lineStart, prefix);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
    widget.onChanged?.call();
  }

  /// Inserts a standalone block (table, mermaid fence, math fence, `---`...)
  /// at the cursor, adding a leading newline first if the cursor isn't
  /// already at the start of a line so the block doesn't run into existing
  /// text.
  void insertBlock(String block) {
    final controller = widget.controller;
    final String text = controller.text;
    final TextSelection selection = controller.selection;
    final int insertAt = selection.isValid ? selection.start : text.length;
    final int removeEnd = selection.isValid ? selection.end : insertAt;
    final bool needsLeadingNewline = insertAt > 0 && text[insertAt - 1] != '\n';
    final String content = '${needsLeadingNewline ? '\n' : ''}$block';

    final String newText = text.replaceRange(insertAt, removeEnd, content);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + content.length),
    );
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = widget.style ?? context.uiText.body;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      undoController: undoController,
      autofocus: widget.autofocus,
      maxLines: null,
      minLines: widget.minLines,
      style: style,
      onChanged: (_) => widget.onChanged?.call(),
      decoration: InputDecoration.collapsed(
        hintText: widget.hintText,
        hintStyle: style.copyWith(color: context.uiColors.foregroundMuted),
      ),
    );
  }
}
