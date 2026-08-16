import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:quietnote/core/markdown_kit/markdown_kit.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:quietnote/features/ai/local_ai_engine.dart';
import 'package:quietnote/features/ai/capture_parser.dart';

const List<UiToggleOption<String>> _moodOptions = [
  UiToggleOption(
    value: 'Great',
    label: 'Great',
    icon: Icons.sentiment_very_satisfied_rounded,
  ),
  UiToggleOption(
    value: 'Neutral',
    label: 'Neutral',
    icon: Icons.sentiment_neutral_rounded,
  ),
  UiToggleOption(
    value: 'Bad',
    label: 'Bad',
    icon: Icons.sentiment_very_dissatisfied_rounded,
  ),
];

class JournalEditorScreen extends ConsumerStatefulWidget {
  final String? entryId;

  /// Pre-fills a tag when creating a brand-new entry (e.g. opened from a
  /// course's "Journal" tab, tagged with that course's code/name so it
  /// shows back up there). Ignored while editing an existing entry.
  final String? initialTag;
  const JournalEditorScreen({super.key, this.entryId, this.initialTag});

  @override
  ConsumerState<JournalEditorScreen> createState() =>
      _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final GlobalKey<RichMarkdownEditorFieldState> _editorKey =
      GlobalKey<RichMarkdownEditorFieldState>();
  bool _isPreview = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String _mood = 'Neutral';
  DateTime _entryDate = DateTime.now();
  List<String> _tags = [];
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  final MarkdownOutlineController _outlineController = MarkdownOutlineController();
  // Text already in the field when dictation started. `recognizedWords`
  // from the plugin is the *full* phrase spoken since `listen()` began, not
  // a delta, so every callback must be applied on top of this fixed base —
  // reusing the (already-updated) live text as the base caused each partial
  // result to be appended again, duplicating words on every callback.
  String _voiceBaseText = '';

  // ── AI Refactor state ───────────────────────────────────────────────────────
  bool _aiRefactoring = false;
  TextSelection? _selectedTextRange;

  late String _currentEntryId;
  bool get _isEditing => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    _currentEntryId = widget.entryId ?? const Uuid().v4();
    if (_isEditing) {
      _loadEntry();
    } else if (widget.initialTag != null && widget.initialTag!.trim().isNotEmpty) {
      _tags = [widget.initialTag!.trim()];
    }
    // Track selection changes for AI refactor button visibility
    _contentController.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    final sel = _contentController.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final newSel = hasSelection ? sel : null;
    if (newSel != _selectedTextRange) {
      setState(() => _selectedTextRange = newSel);
    }
  }

  @override
  void dispose() {
    _contentController.removeListener(_onSelectionChanged);
    _titleController.dispose();
    _contentController.dispose();
    _outlineController.dispose();
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

    _editorKey.currentState?.insertBlock('![image](local-image://$attachmentId)\n');
    setState(() {});
  }

  /// Imports a `.md`/`.txt`/`.pdf` file into the entry body at the cursor.
  /// Mirrors the notes editor's import (see note_editor_screen.dart) so the
  /// same file-handling behaviour is available from the journal too.
  Future<void> _pickDocument() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
    );
    final PlatformFile? picked = result?.files.single;
    final String? path = picked?.path;
    if (path == null) return;

    final file = File(path);
    final String filename = picked!.name;
    final String ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';

    if (ext == 'txt' || ext == 'md') {
      final String content = await file.readAsString();
      _editorKey.currentState?.insertBlock(content);
      setState(() {});
      return;
    }

    String extracted = '';
    try {
      final bytes = await file.readAsBytes();
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: bytes);
      extracted = sf.PdfTextExtractor(document).extractText().trim();
      document.dispose();
    } catch (_) {
      extracted = '';
    }

    if (extracted.isNotEmpty) {
      _editorKey.currentState?.insertBlock(
        '\n\n---\n*Imported from: $filename*\n\n$extracted',
      );
      setState(() {});
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory('${directory.path}/attachments');
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final savedFile = await file.copy(
      '${attachmentsDir.path}/${const Uuid().v4()}.pdf',
    );
    final attachmentId = const Uuid().v4();
    final db = ref.read(databaseProvider);
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: attachmentId,
            parentId: _currentEntryId,
            parentType: 'journal',
            filePath: savedFile.path,
          ),
        );
    _editorKey.currentState?.insertBlock('[📄 $filename](local-file://$attachmentId)\n');
    setState(() {});
    if (mounted) {
      UiToast.show(
        context,
        title: "Couldn't extract text",
        message:
            "$filename looks like a scanned or image-only PDF, so it was attached as a reference instead.",
        intent: UiIntent.warning,
      );
    }
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

  // ── AI Refactor ──────────────────────────────────────────────────────────

  Future<void> _aiRefactorSelected() async {
    final sel = _selectedTextRange;
    if (sel == null || _aiRefactoring) return;
    final fullText = _contentController.text;
    final selectedText = fullText.substring(sel.start, sel.end).trim();
    if (selectedText.isEmpty) return;

    final notifier = ref.read(aiEngineProvider.notifier);
    if (!notifier.canGenerate) {
      UiToast.show(
        context,
        title: 'Set up AI first',
        message: 'Import an on-device model or paste an API key in Settings › AI.',
        intent: UiIntent.info,
      );
      return;
    }

    setState(() => _aiRefactoring = true);
    try {
      final enhanced = await notifier.enhanceSelectedText(
        selectedText: selectedText,
        type: CaptureType.journal,
        contextTitle: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
      );
      if (!mounted || enhanced.isEmpty) return;

      // Replace selected text with enhanced version
      final newText = fullText.replaceRange(sel.start, sel.end, enhanced);
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + enhanced.length),
      );
      setState(() => _selectedTextRange = null);

      UiToast.show(
        context,
        title: 'AI Enhanced',
        message: 'Selected journal text has been improved.',
        intent: UiIntent.success,
      );
    } catch (e) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'AI Enhance failed',
          message: e.toString(),
          intent: UiIntent.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _aiRefactoring = false);
    }
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
      child: Stack(
        children: [
          _buildScaffold(context, wordCount),
          // Floating accessory bars above the keyboard: AI refactor bar (when text selected)
          // stacked cleanly above the markdown formatting toolbar.
          if (!_isPreview && !_isLoading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedTextRange != null)
                      AnimatedOpacity(
                        opacity: _selectedTextRange != null ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: _AiRefactorBar(
                          refactoring: _aiRefactoring,
                          onRefactor: _aiRefactorSelected,
                          onDismiss: () =>
                              setState(() => _selectedTextRange = null),
                        ),
                      ),
                    MarkdownEditorToolbar(
                      editorKey: _editorKey,
                      onPickImage: _pickImage,
                      onPickDocument: _pickDocument,
                      onToggleVoice: _toggleVoiceInput,
                      listening: _listening,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resolveImage(BuildContext context, Uri uri) {
    if (uri.scheme != 'local-image') return Image.network(uri.toString());
    final attachmentId = uri.host;
    return FutureBuilder<Attachment?>(
      future: (ref
              .read(databaseProvider)
              .select(ref.read(databaseProvider).attachments)
            ..where((a) => a.id.equals(attachmentId)))
          .getSingleOrNull(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(snapshot.data!.filePath)),
          );
        }
        return const SizedBox(
          height: 100,
          child: Center(child: Icon(Icons.broken_image)),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, int wordCount) {
    return UiPage(
      reserveDockSpace: false,
      floatingActionButton: _isPreview ? MarkdownOutlineFab(controller: _outlineController) : null,
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          onPressed: _handleBack,
          tooltip: 'Back',
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
                  RichMarkdownPreview(
                    data: _contentController.text,
                    imageResolver: _resolveImage,
                    outlineController: _outlineController,
                  )
                else ...[
                  RichMarkdownEditorField(
                    key: _editorKey,
                    controller: _contentController,
                    hintText: 'Dear journal…',
                    onChanged: () => setState(() {}),
                  ),
                  // Clearance so the last lines of text aren't hidden behind
                  // the floating formatting toolbar.
                  const SizedBox(height: 64),
                ],
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Refactor bar — floats above the formatting toolbar on text selection
// ---------------------------------------------------------------------------

class _AiRefactorBar extends StatelessWidget {
  const _AiRefactorBar({
    required this.refactoring,
    required this.onRefactor,
    required this.onDismiss,
  });

  final bool refactoring;
  final VoidCallback onRefactor;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.primary.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
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
              'Text selected',
              style: context.uiText.caption.copyWith(
                color: c.foregroundMuted,
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
                'Enhancing…',
                style: context.uiText.caption.copyWith(
                  color: c.primary,
                  decoration: TextDecoration.none,
                ),
              ),
            ] else ...[
              GestureDetector(
                onTap: onRefactor,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 14, color: c.onPrimary),
                      const SizedBox(width: 5),
                      Text(
                        'Enhance with AI',
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
              const SizedBox(width: 8),
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
