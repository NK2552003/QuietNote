import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/markdown_editor_field.dart';

const String _tableTemplate =
    '\n| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Cell | Cell | Cell |\n\n';
const String _mermaidTemplate =
    '\n```mermaid\nflowchart TD\n    A[Start] --> B{Decision}\n    B -->|Yes| C[Do the thing]\n    B -->|No| D[Skip it]\n```\n\n';
const String _chartTemplate =
    '\n```chart\n{\n  "type": "bar",\n  "title": "Chart title",\n  "labels": ["A", "B", "C"],\n  "series": [{"name": "Series", "data": [1, 2, 3]}]\n}\n```\n\n';
const String _mathBlockTemplate = '\n\$\$\nE = mc^2\n\$\$\n\n';
const String _codeTemplate = '\n```dart\n\n```\n\n';

/// Floating formatting bar for [RichMarkdownEditorField]. Meant to be
/// positioned with `Positioned(bottom: MediaQuery.of(context).viewInsets.bottom, ...)`
/// so it sits directly above the on-screen keyboard, like an input
/// accessory view.
class MarkdownEditorToolbar extends StatelessWidget {
  const MarkdownEditorToolbar({
    super.key,
    required this.editorKey,
    this.onPickImage,
    this.onPickDocument,
    this.onToggleVoice,
    this.listening = false,
  });

  final GlobalKey<RichMarkdownEditorFieldState> editorKey;
  final VoidCallback? onPickImage;
  final VoidCallback? onPickDocument;
  final VoidCallback? onToggleVoice;
  final bool listening;

  RichMarkdownEditorFieldState? get _editor => editorKey.currentState;

  void _showMore(BuildContext context) {
    final colors = context.uiColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Insert',
                style: sheetContext.uiText.subheading,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  _MoreTile(
                    icon: Icons.horizontal_rule,
                    label: 'Divider',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.insertBlock('\n---\n\n');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.table_chart_outlined,
                    label: 'Table',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.insertBlock(_tableTemplate);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.functions,
                    label: 'Math block',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.insertBlock(_mathBlockTemplate);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.superscript,
                    label: 'Inline math',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.wrapSelection(r'$', r'$');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.account_tree_outlined,
                    label: 'Flowchart',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.insertBlock(_mermaidTemplate);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.insert_chart_outlined,
                    label: 'Chart',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.insertBlock(_chartTemplate);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.code_outlined,
                    label: 'Code block',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.insertBlock(_codeTemplate);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.border_color_outlined,
                    label: 'Highlight',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editor?.wrapSelection('==', '==');
                    },
                  ),
                  if (onPickDocument != null)
                    _MoreTile(
                      icon: Icons.upload_file_outlined,
                      label: 'Import file',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onPickDocument?.call();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(color: colors.overlay, blurRadius: 14, offset: const Offset(0, -3)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            if (_editor != null)
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: _editor!.undoController,
                builder: (context, value, _) => Row(
                  children: [
                    _ToolbarButton(
                      icon: Icons.undo,
                      hint: 'Undo',
                      onTap: value.canUndo ? () => _editor?.undoController.undo() : null,
                    ),
                    _ToolbarButton(
                      icon: Icons.redo,
                      hint: 'Redo',
                      onTap: value.canRedo ? () => _editor?.undoController.redo() : null,
                    ),
                  ],
                ),
              ),
            _ToolbarDivider(),
            PopupMenuButton<String>(
              tooltip: 'Heading',
              icon: Icon(Icons.title, size: 20, color: colors.foregroundMuted),
              splashRadius: 20,
              onSelected: (value) => _editor?.prefixCurrentLine(value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: '# ', child: Text('Heading 1')),
                PopupMenuItem(value: '## ', child: Text('Heading 2')),
                PopupMenuItem(value: '### ', child: Text('Heading 3')),
              ],
            ),
            _ToolbarButton(
              icon: Icons.format_bold,
              hint: 'Bold',
              onTap: () => _editor?.wrapSelection('**', '**'),
            ),
            _ToolbarButton(
              icon: Icons.format_italic,
              hint: 'Italic',
              onTap: () => _editor?.wrapSelection('*', '*'),
            ),
            _ToolbarButton(
              icon: Icons.format_strikethrough,
              hint: 'Strikethrough',
              onTap: () => _editor?.wrapSelection('~~', '~~'),
            ),
            _ToolbarButton(
              icon: Icons.code,
              hint: 'Inline code',
              onTap: () => _editor?.wrapSelection('`', '`'),
            ),
            _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              hint: 'Bulleted list',
              onTap: () => _editor?.prefixCurrentLine('- '),
            ),
            _ToolbarButton(
              icon: Icons.format_list_numbered,
              hint: 'Numbered list',
              onTap: () => _editor?.prefixCurrentLine('1. '),
            ),
            _ToolbarButton(
              icon: Icons.checklist,
              hint: 'Checklist item',
              onTap: () => _editor?.prefixCurrentLine('- [ ] '),
            ),
            _ToolbarButton(
              icon: Icons.format_quote,
              hint: 'Quote',
              onTap: () => _editor?.prefixCurrentLine('> '),
            ),
            _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.link,
              hint: 'Link',
              onTap: () => _editor?.wrapSelection('[', '](url)'),
            ),
            if (onPickImage != null)
              _ToolbarButton(
                icon: Icons.image_outlined,
                hint: 'Add image',
                onTap: onPickImage,
              ),
            if (onToggleVoice != null)
              _ToolbarButton(
                icon: listening ? Icons.stop_circle_outlined : Icons.mic_none_rounded,
                hint: listening ? 'Stop dictation' : 'Dictate with voice',
                onTap: onToggleVoice,
                active: listening,
              ),
            _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.add_box_outlined,
              hint: 'Insert table, math, flowchart, chart…',
              onTap: () => _showMore(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    this.hint,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? hint;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    return IconButton(
      icon: Icon(icon, size: 20),
      color: active
          ? colors.destructive
          : (onTap == null ? colors.disabledForeground : colors.foregroundMuted),
      onPressed: onTap,
      splashRadius: 20,
      tooltip: hint,
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      color: context.uiColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: colors.foreground),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: colors.foregroundMuted),
            ),
          ],
        ),
      ),
    );
  }
}
