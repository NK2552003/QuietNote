import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/utils/tag_utils.dart';

/// Create or edit a flashcard deck.
class FlashcardDeckEditorScreen extends ConsumerStatefulWidget {
  const FlashcardDeckEditorScreen({super.key, this.deckId});

  final String? deckId;

  @override
  ConsumerState<FlashcardDeckEditorScreen> createState() =>
      _FlashcardDeckEditorScreenState();
}

class _FlashcardDeckEditorScreenState
    extends ConsumerState<FlashcardDeckEditorScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<String> _subjects = <String>[];
  String? _courseId;
  int? _color = 0xFF4F46E5;
  bool _loading = false;
  bool _saving = false;

  bool get _isEditing => widget.deckId != null;

  static const List<int> _colorPresets = [
    0xFF4F46E5,
    0xFF10B981,
    0xFF8B5CF6,
    0xFFF43F5E,
    0xFFF59E0B,
    0xFF06B6D4,
    0xFF64748B,
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final deck =
        await ref.read(flashcardRepositoryProvider).getDeck(widget.deckId!);
    if (deck != null && mounted) {
      _titleController.text = deck.title;
      _descriptionController.text = deck.description ?? '';
      _subjects = parseTagsCsv(deck.subject);
      _courseId = deck.courseId;
      _color = deck.color ?? 0xFF4F46E5;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goBack() {
    context.canPop() ? context.pop() : context.go('/flashcards');
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      UiToast.show(
        context,
        title: 'Name your deck',
        message: 'A title is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final description = _descriptionController.text.trim();
    final repo = ref.read(flashcardRepositoryProvider);
    if (_isEditing) {
      await repo.updateDeck(
        widget.deckId!,
        title: title,
        description: description.isEmpty ? null : description,
        subject: _subjects,
        courseId: _courseId,
        color: _color,
      );
      if (!mounted) return;
      _goBack();
    } else {
      final id = await repo.createDeck(
        title: title,
        description: description.isEmpty ? null : description,
        subject: _subjects,
        courseId: _courseId,
        color: _color,
      );
      if (!mounted) return;
      context.pushReplacement('/flashcards/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final courses =
        ref.watch(coursesStreamProvider).valueOrNull ?? const <Course>[];

    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          tooltip: 'Back',
          onPressed: _goBack,
        ),
        title: _isEditing ? 'Edit deck' : 'New deck',
        actions: [
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
      child: _loading
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
                    hintText: 'Deck title (e.g. Organic Chemistry)',
                    hintStyle: context.uiText.heading
                        .copyWith(color: c.foregroundMuted),
                  ),
                ),
                const SizedBox(height: 20),
                UiField(
                  label: 'Description',
                  child: UiTextarea(
                    controller: _descriptionController,
                    hintText: 'What does this deck cover?',
                    rows: 3,
                  ),
                ),
                const SizedBox(height: 16),
                UiField(
                  label: 'Subjects',
                  child: UiTagInput(
                    tags: _subjects,
                    hintText: 'Add a subject and press enter',
                    onChanged: (tags) => setState(() => _subjects = tags),
                  ),
                ),
                const SizedBox(height: 16),
                UiField(
                  label: 'Linked course',
                  child: UiSelect<String>(
                    value: _courseId ?? '',
                    hintText: 'No course',
                    onChanged: (v) =>
                        setState(() => _courseId = v.isEmpty ? null : v),
                    options: [
                      const UiOption(value: '', label: 'No course'),
                      for (final course in courses)
                        UiOption(value: course.id, label: course.name),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Colour', style: context.uiText.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final preset in _colorPresets)
                      GestureDetector(
                        onTap: () => setState(() => _color = preset),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(preset),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == preset
                                  ? c.foreground
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
