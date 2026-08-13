import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:quietnote/core/widgets/markdown_mermaid.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  const NoteEditorScreen({super.key, this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isPreview = false;
  bool _isLoading = false;
  bool _isSaving = false;
  DateTime? _createdAt;
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  // Text already in the field when dictation started. `recognizedWords`
  // from the plugin is the *full* phrase spoken since `listen()` began, not
  // a delta, so every callback must be applied on top of this fixed base —
  // reusing the (already-updated) live text as the base caused each partial
  // result to be appended again, duplicating words on every callback.
  String _voiceBaseText = '';

  late String _currentNoteId;
  bool get _isEditing => widget.noteId != null;

  @override
  void initState() {
    super.initState();
    _currentNoteId = widget.noteId ?? const Uuid().v4();
    if (_isEditing) {
      _loadNote();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    setState(() => _isLoading = true);
    final note = await ref
        .read(noteRepositoryProvider)
        .getNoteById(_currentNoteId);
    if (note != null && mounted) {
      _titleController.text = note.title;
      _contentController.text = note.content;
      _createdAt = note.createdAt;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/notes');
    }
  }

  /// Used by the system back gesture. A genuinely empty, never-edited note
  /// has nothing worth keeping (or warning about) — just let the person
  /// leave. Anything with content goes through `_saveNote` so it, and any
  /// picked image, is actually persisted before the screen closes.
  Future<void> _handleBack() async {
    final bool hasContent =
        _titleController.text.trim().isNotEmpty ||
        _contentController.text.trim().isNotEmpty;
    if (!hasContent) {
      _leave();
      return;
    }
    await _saveNote();
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) {
      UiToast.show(
        context,
        title: 'Nothing to save',
        message: 'Add a title or some note content first.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (!_isSaving && (title.isNotEmpty || content.isNotEmpty)) {
      setState(() => _isSaving = true);
      if (_isEditing) {
        await ref
            .read(noteRepositoryProvider)
            .updateNote(_currentNoteId, title, content);
      } else {
        await ref
            .read(databaseProvider)
            .into(ref.read(databaseProvider).notes)
            .insert(
              NotesCompanion.insert(
                id: _currentNoteId,
                title: title.isEmpty ? 'Untitled' : title,
                content: content,
              ),
            );
      }
    }
    if (!mounted) return;
    _leave();
  }

  Future<void> _deleteNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text(
          'This removes the note and any attached images. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.uiColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteRepositoryProvider).deleteNote(_currentNoteId);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/notes');
      }
    }
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;

    if (!selection.isValid) {
      _contentController.text = '$text$prefix$suffix';
      _contentController.selection = TextSelection.collapsed(
        offset: _contentController.text.length - suffix.length,
      );
      return;
    }

    final selectedText = selection.textInside(text);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$prefix$selectedText$suffix',
    );

    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length,
      ),
    );
    setState(() {});
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory('${directory.path}/attachments');
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final fileExtension = pickedFile.path.split('.').last;
    final fileName = '${const Uuid().v4()}.$fileExtension';
    final savedImage = await File(
      pickedFile.path,
    ).copy('${attachmentsDir.path}/$fileName');

    final attachmentId = const Uuid().v4();
    await ref
        .read(databaseProvider)
        .into(ref.read(databaseProvider).attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: attachmentId,
            parentId: _currentNoteId,
            parentType: 'note',
            filePath: savedImage.path,
          ),
        );

    _insertMarkdown('![image](local-image://$attachmentId)', '');
  }

  Future<void> _toggleVoiceInput() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted && (status == 'done' || status == 'notListening')) {
          setState(() => _listening = false);
        }
      },
    );
    if (!available) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'Voice input unavailable',
          message:
              'Enable microphone and speech recognition access to dictate a note.',
          intent: UiIntent.warning,
        );
      }
      return;
    }
    _voiceBaseText = _contentController.text.trimRight();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final base = _voiceBaseText;
        final text = '${base.isEmpty ? '' : '$base '}${result.recognizedWords}';
        _contentController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        setState(() => _listening = _speech.isListening);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wordCount = _contentController.text.trim().isEmpty
        ? 0
        : _contentController.text.trim().split(RegExp(r'\s+')).length;

    return PopScope(
      // A note with a freshly-picked image is only linked to a real note
      // once `_saveNote` runs. Without intercepting the pop, the Android
      // back gesture (unlike the header's back button) skipped straight
      // past `_saveNote`, so the note — and the attachment row pointing at
      // it — never got created and the picked image was orphaned.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: _buildScaffold(context, wordCount),
    );
  }

  Widget _buildScaffold(BuildContext context, int wordCount) {
    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          onPressed: _saveNote,
          tooltip: 'Save & close',
        ),
        title: _isEditing ? 'Edit Note' : 'New Note',
        subtitle: _isEditing
            ? '${wordCount == 1 ? '1 word' : '$wordCount words'}'
                  '${_createdAt != null ? ' \u00b7 ${DateFormat.yMMMd().format(_createdAt!)}' : ''}'
            : null,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteNote,
              tooltip: 'Delete note',
            ),
          UiIconButton(
            icon: _isPreview ? Icons.edit : Icons.visibility,
            variant: UiVariant.ghost,
            onPressed: () => setState(() => _isPreview = !_isPreview),
            tooltip: _isPreview ? 'Edit' : 'Preview',
          ),
          UiIconButton(
            icon: Icons.check,
            variant: _isSaving ? UiVariant.secondary : UiVariant.primary,
            onPressed: _isSaving ? null : _saveNote,
            tooltip: 'Save',
          ),
        ],
      ),
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 48),
                child: CircularProgressIndicator(),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  style: context.uiText.heading,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Untitled note',
                    hintStyle: context.uiText.heading.copyWith(
                      color: context.uiColors.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isPreview)
                  MarkdownBody(
                    data: _contentController.text.isEmpty
                        ? '*Nothing written yet.*'
                        : _contentController.text,
                    selectable: true,
                    builders: <String, MarkdownElementBuilder>{
                      'pre': MermaidCodeBuilder(
                        dark: context.ui.brightness == Brightness.dark,
                      ),
                    },
                    sizedImageBuilder: (config) {
                      if (config.uri.scheme == 'local-image') {
                        final attachmentId = config.uri.host;
                        return FutureBuilder<Attachment?>(
                          future:
                              (ref
                                      .read(databaseProvider)
                                      .select(
                                        ref.read(databaseProvider).attachments,
                                      )
                                    ..where((a) => a.id.equals(attachmentId)))
                                  .getSingleOrNull(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                height: 100,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.hasData && snapshot.data != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(snapshot.data!.filePath),
                                ),
                              );
                            }
                            return const SizedBox(
                              height: 100,
                              child: Center(child: Icon(Icons.broken_image)),
                            );
                          },
                        );
                      }
                      return Image.network(config.uri.toString());
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: context.uiText.body,
                      h1: context.uiText.heading.copyWith(fontSize: 26),
                      h2: context.uiText.heading.copyWith(fontSize: 22),
                      h3: context.uiText.heading.copyWith(fontSize: 18),
                      blockquote: context.uiText.body.copyWith(
                        color: context.uiColors.foregroundMuted,
                        fontStyle: FontStyle.italic,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: context.uiColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(
                            color: context.uiColors.border,
                            width: 3,
                          ),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      code: context.uiText.numeric,
                      codeblockDecoration: BoxDecoration(
                        color: context.uiColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: context.uiColors.border),
                        ),
                      ),
                      listBullet: context.uiText.body,
                      tableBorder: TableBorder.all(
                        color: context.uiColors.border,
                      ),
                      a: context.uiText.body.copyWith(
                        color: context.uiColors.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                else ...[
                  Container(
                    padding: EdgeInsets.symmetric(vertical: context.sz(4)),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.uiColors.border),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolbarButton(
                            icon: Icons.title,
                            hint: 'Heading',
                            onTap: () => _insertMarkdown('## ', ''),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_bold,
                            hint: 'Bold',
                            onTap: () => _insertMarkdown('**', '**'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_italic,
                            hint: 'Italic',
                            onTap: () => _insertMarkdown('*', '*'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_strikethrough,
                            hint: 'Strikethrough',
                            onTap: () => _insertMarkdown('~~', '~~'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_quote,
                            hint: 'Quote',
                            onTap: () => _insertMarkdown('> ', ''),
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: context.uiColors.border,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _ToolbarButton(
                            icon: Icons.image_outlined,
                            hint: 'Add image',
                            onTap: _pickImage,
                          ),
                          _ToolbarButton(
                            icon: Icons.link,
                            hint: 'Link',
                            onTap: () => _insertMarkdown('[', '](url)'),
                          ),
                          _ToolbarButton(
                            icon: _listening
                                ? Icons.stop_circle_outlined
                                : Icons.mic_none_rounded,
                            hint: _listening
                                ? 'Stop dictation'
                                : 'Dictate with voice',
                            onTap: _toggleVoiceInput,
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: context.uiColors.border,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _ToolbarButton(
                            icon: Icons.code,
                            hint: 'Inline code',
                            onTap: () => _insertMarkdown('`', '`'),
                          ),
                          _ToolbarButton(
                            icon: Icons.data_object,
                            hint: 'Mermaid diagram',
                            onTap: () => _insertMarkdown(
                              '\n```mermaid\ngraph TD;\n    A-->B;\n```\n',
                              '',
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: context.uiColors.border,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_list_bulleted,
                            hint: 'Bulleted list',
                            onTap: () => _insertMarkdown('- ', ''),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_list_numbered,
                            hint: 'Numbered list',
                            onTap: () => _insertMarkdown('1. ', ''),
                          ),
                          _ToolbarButton(
                            icon: Icons.check_box_outlined,
                            hint: 'Checklist item',
                            onTap: () => _insertMarkdown('- [ ] ', ''),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _contentController,
                    maxLines: null,
                    style: context.uiText.body,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Start typing with Markdown...',
                      hintStyle: context.uiText.body.copyWith(
                        color: context.uiColors.foregroundMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? hint;
  const _ToolbarButton({required this.icon, required this.onTap, this.hint});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: context.uiColors.foregroundMuted),
      onPressed: onTap,
      splashRadius: 20,
      tooltip: hint,
    );
  }
}
