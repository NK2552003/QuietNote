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
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

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
    }
    if (mounted) setState(() => _isLoading = false);
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
              ),
            );
      }
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/journal');
    }
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
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final before = _contentController.text.trimRight();
        final text =
            '${before.isEmpty ? '' : '$before '} ${result.recognizedWords}'
                .trimLeft();
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
                const SizedBox(height: 16),
                if (_isPreview)
                  MarkdownBody(
                    data: _contentController.text.isEmpty
                        ? '*Nothing written yet.*'
                        : _contentController.text,
                    selectable: true,
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
                      h1: context.uiText.heading.copyWith(fontSize: 24),
                      h2: context.uiText.heading.copyWith(fontSize: 20),
                      h3: context.uiText.heading.copyWith(fontSize: 18),
                      code: context.uiText.numeric,
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
                            icon: Icons.format_bold,
                            onTap: () => _insertMarkdown('**', '**'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_italic,
                            onTap: () => _insertMarkdown('*', '*'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_strikethrough,
                            onTap: () => _insertMarkdown('~~', '~~'),
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: context.uiColors.border,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _ToolbarButton(
                            icon: Icons.image_outlined,
                            onTap: _pickImage,
                          ),
                          _ToolbarButton(
                            icon: _listening
                                ? Icons.stop_circle_outlined
                                : Icons.mic_none_rounded,
                            onTap: _toggleVoiceInput,
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: context.uiColors.border,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_list_bulleted,
                            onTap: () => _insertMarkdown('- ', ''),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_list_numbered,
                            onTap: () => _insertMarkdown('1. ', ''),
                          ),
                          _ToolbarButton(
                            icon: Icons.check_box_outlined,
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
  const _ToolbarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: context.uiColors.foregroundMuted),
      onPressed: onTap,
      splashRadius: 20,
    );
  }
}
