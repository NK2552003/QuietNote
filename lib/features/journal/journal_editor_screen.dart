import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:quietnote/core/widgets/markdown_mermaid.dart';
import 'package:quietnote/core/utils/tag_utils.dart';

const List<UiToggleOption<String>> _moodOptions = [
  UiToggleOption(value: 'Great', label: '😃 Great'),
  UiToggleOption(value: 'Neutral', label: '😐 Neutral'),
  UiToggleOption(value: 'Bad', label: '😔 Bad'),
];

class JournalEditorScreen extends ConsumerStatefulWidget {
  final String? entryId;
  const JournalEditorScreen({super.key, this.entryId});

  @override
  ConsumerState<JournalEditorScreen> createState() =>
      _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isPreview = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String _mood = 'Neutral';
  DateTime _entryDate = DateTime.now();
  List<String> _tags = [];
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  // Text already in the field when dictation started. `recognizedWords`
  // from the plugin is the *full* phrase spoken since `listen()` began, not
  // a delta, so every callback must be applied on top of this fixed base —
  // reusing the (already-updated) live text as the base caused each partial
  // result to be appended again, duplicating words on every callback.
  String _voiceBaseText = '';

  late String _currentEntryId;
  bool get _isEditing => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    _currentEntryId = widget.entryId ?? const Uuid().v4();
    if (_isEditing) {
      _loadEntry();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadEntry() async {
    setState(() => _isLoading = true);
    final entry = await ref
        .read(journalRepositoryProvider)
        .getEntry(_currentEntryId);
    if (entry != null && mounted) {
      _titleController.text = entry.title;
      _contentController.text = entry.entry;
      _mood = entry.mood ?? 'Neutral';
      _entryDate = entry.createdAt;
      _tags = parseTagsCsv(entry.tags);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/journal');
    }
  }

  /// Used by the system back gesture. A genuinely empty, never-edited entry
  /// has nothing worth keeping (or warning about) — just let the person
  /// leave. Anything with content goes through `_saveEntry` so it, and any
  /// picked photo, is actually persisted before the screen closes.
  Future<void> _handleBack() async {
    final bool hasContent =
        _titleController.text.trim().isNotEmpty ||
        _contentController.text.trim().isNotEmpty;
    if (!hasContent) {
      _leave();
      return;
    }
    await _saveEntry();
  }

  Future<void> _saveEntry() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) {
      UiToast.show(
        context,
        title: 'Nothing to save',
        message: 'Add a title or write a journal entry first.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (!_isSaving) {
      setState(() => _isSaving = true);
      final db = ref.read(databaseProvider);
      if (_isEditing) {
        await (db.update(
          db.journal,
        )..where((t) => t.id.equals(_currentEntryId))).write(
          JournalCompanion(
            title: drift.Value(title.isEmpty ? 'Untitled entry' : title),
            entry: drift.Value(content),
            mood: drift.Value(_mood),
            tags: drift.Value(tagsToCsv(_tags)),
          ),
        );
      } else {
        await db
            .into(db.journal)
            .insert(
              JournalCompanion.insert(
                id: _currentEntryId,
                title: drift.Value(title.isEmpty ? 'Untitled entry' : title),
                entry: content,
                mood: drift.Value(_mood),
                tags: drift.Value(tagsToCsv(_tags)),
              ),
            );
      }
    }
    if (!mounted) return;
    _leave();
  }

  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text(
          'This removes the entry and any attached photos. This can\'t be undone.',
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
      await ref.read(journalRepositoryProvider).deleteEntry(_currentEntryId);
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/journal');
        }
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
    final db = ref.read(databaseProvider);
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: attachmentId,
            parentId: _currentEntryId,
            parentType: 'journal',
            filePath: savedImage.path,
          ),
        );

    _insertMarkdown('![image](local-image://$attachmentId)', '');
    setState(() {});
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
              'Enable microphone and speech recognition access to dictate your journal.',
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
      // A photo picked into a not-yet-saved entry is only linked to a real
      // entry once `_saveEntry` runs. Without intercepting the pop, the
      // Android back gesture (unlike the header's back button) skipped
      // straight past `_saveEntry`, so the entry — and the attachment row
      // pointing at it — never got created and the picked photo was orphaned.
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
          onPressed: _saveEntry,
          tooltip: 'Save & close',
        ),
        title: DateFormat.yMMMd().format(_entryDate),
        subtitle: _isEditing ? '$wordCount words' : null,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteEntry,
              tooltip: 'Delete entry',
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
            onPressed: _isSaving ? null : _saveEntry,
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
                  textCapitalization: TextCapitalization.sentences,
                  style: context.uiText.heading,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Journal title',
                    hintStyle: context.uiText.heading.copyWith(
                      color: context.uiColors.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                UiToggleGroup<String>(
                  variant: UiToggleGroupVariant.segmented,
                  expand: true,
                  value: _mood,
                  onChanged: (v) => setState(() => _mood = v),
                  options: _moodOptions,
                ),
                const SizedBox(height: 12),
                UiTagInput(
                  tags: _tags,
                  onChanged: (v) => setState(() => _tags = v),
                  hintText: 'Add a subject tag',
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
                            hint: 'Add photo',
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
                      hintText: 'Dear journal...',
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
