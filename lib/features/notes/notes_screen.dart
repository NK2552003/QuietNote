import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';

enum _NoteSort { recent, title }

final _noteQueryProvider = StateProvider<String>((ref) => '');
final _noteSortProvider = StateProvider<_NoteSort>((ref) => _NoteSort.recent);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _relativeDate(DateTime date) {
  final today = _dateOnly(DateTime.now());
  final day = _dateOnly(date);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(date);
  return DateFormat.yMMMd().format(date);
}

int _wordCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

class _ChecklistStats {
  const _ChecklistStats(this.total, this.done);
  final int total;
  final int done;
}

_ChecklistStats _checklistStats(String content) {
  final matches = RegExp(
    r'^\s*[-*]\s\[([ xX])\]',
    multiLine: true,
  ).allMatches(content);
  var done = 0;
  for (final m in matches) {
    if (m.group(1)?.toLowerCase() == 'x') done++;
  }
  return _ChecklistStats(matches.length, done);
}

/// Strips the most common Markdown punctuation so grid cards show a clean
/// text preview instead of raw `**`, `#`, backticks, etc.
String _plainPreview(String content) {
  final text = content
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
      .replaceAll(RegExp(r'^\s*[-*]\s\[[ xX]\]\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*|__|~~|`'), '')
      .replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^>\s?', multiLine: true), '');
  return text.trim();
}

IconData _noteIcon(String content) {
  if (content.contains('local-image://')) return Icons.image_outlined;
  if (RegExp(r'^\s*[-*]\s\[[ xX]\]', multiLine: true).hasMatch(content)) {
    return Icons.checklist_rounded;
  }
  if (content.contains('```')) return Icons.code_rounded;
  return Icons.notes_rounded;
}

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          'This removes "${note.title.isEmpty ? 'Untitled' : note.title}". This can\'t be undone.',
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
      await ref.read(noteRepositoryProvider).deleteNote(note.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesStreamProvider);
    final query = ref.watch(_noteQueryProvider);
    final sort = ref.watch(_noteSortProvider);

    return UiPage(
      header: UiHeader(
        title: 'Notes',
        subtitle: 'Capture your thoughts.',
        actions: [
          UiButton(
            label: 'New Note',
            leadingIcon: Icons.add,
            onPressed: () => context.push('/notes/new'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          notesAsync.when(
            data: (notes) {
              if (notes.isEmpty) {
                return const UiEmptyState(
                  title: 'No notes written',
                  message: 'Start capturing your ideas.',
                  icon: Icons.note_alt_outlined,
                );
              }

              final thisWeek = notes
                  .where(
                    (n) => DateTime.now().difference(n.createdAt).inDays < 7,
                  )
                  .length;

              final q = query.trim().toLowerCase();
              final filtered =
                  (q.isEmpty
                          ? notes
                          : notes
                                .where(
                                  (n) =>
                                      n.title.toLowerCase().contains(q) ||
                                      n.content.toLowerCase().contains(q),
                                )
                                .toList())
                      .toList();

              if (sort == _NoteSort.title) {
                filtered.sort(
                  (a, b) => (a.title.isEmpty ? 'Untitled' : a.title)
                      .toLowerCase()
                      .compareTo(
                        (b.title.isEmpty ? 'Untitled' : b.title).toLowerCase(),
                      ),
                );
              } else {
                filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: UiCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Notes', style: context.uiText.caption),
                              const SizedBox(height: 4),
                              Text(
                                '${notes.length}',
                                style: context.uiText.heading,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: UiCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('This week', style: context.uiText.caption),
                              const SizedBox(height: 4),
                              Text('$thisWeek', style: context.uiText.heading),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  UiSearchField(
                    hintText: 'Search notes...',
                    value: query,
                    onChanged: (v) =>
                        ref.read(_noteQueryProvider.notifier).state = v,
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (ctx) {
                      final sortOptions = <UiToggleOption<_NoteSort>>[
                        const UiToggleOption(
                          value: _NoteSort.recent,
                          label: 'Recent',
                        ),
                        const UiToggleOption(
                          value: _NoteSort.title,
                          label: 'A\u2013Z',
                        ),
                      ];
                      final shouldExpand = sortOptions.length <= 4;
                      final group = UiToggleGroup<_NoteSort>(
                        variant: UiToggleGroupVariant.segmented,
                        size: UiSize.sm,
                        expand: true,
                        value: sort,
                        onChanged: (v) =>
                            ref.read(_noteSortProvider.notifier).state = v,
                        options: sortOptions,
                      );
                      if (!shouldExpand) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: group,
                        );
                      }
                      return group;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    UiEmptyState(
                      title: 'No matches',
                      message: 'Nothing found for "$query".',
                      icon: Icons.search_off_rounded,
                    )
                  else
                    UiCardGrid(
                      // Preview cards keep a stable rhythm while the grid
                      // adds columns only when there is room to read them.
                      mainAxisExtent: 196,
                      maxCrossAxisExtent: 380,
                      children: filtered
                          .map(
                            (note) => _NoteCard(
                              note: note,
                              onDelete: () =>
                                  _confirmDelete(context, ref, note),
                            ),
                          )
                          .toList(),
                    ),
                ],
              );
            },
            loading: () => Column(
              children: List.generate(
                4,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: UiCard(
                    loading: true,
                    loadingHeight: 96,
                    child: SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            error: (err, stack) => UiCard(
              accentColor: context.uiColors.destructive,
              child: Text(
                'Could not load notes: $err',
                style: context.uiText.caption.copyWith(
                  color: context.uiColors.destructive,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onDelete});

  final Note note;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final checklist = _checklistStats(note.content);
    final preview = _plainPreview(note.content);
    final words = _wordCount(note.content);

    return UiCard(
      semanticLabel:
          'Preview note: ${note.title.isEmpty ? 'Untitled' : note.title}',
      onTap: () => context.push('/notes/${note.id}'),
      onLongPress: onDelete,
      padding: EdgeInsets.all(context.sp(context.uiSpace.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _noteIcon(note.content),
                  size: 16,
                  color: c.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  note.title.isEmpty ? 'Untitled' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiText.bodyStrong,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: c.foregroundMuted,
                onPressed: onDelete,
                tooltip: 'Delete note',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview.isEmpty ? 'No content' : preview,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: context.uiText.body.copyWith(color: c.foregroundMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 12, color: c.foregroundMuted),
              const SizedBox(width: 4),
              Text(
                _relativeDate(note.createdAt),
                style: context.uiText.caption,
              ),
              if (checklist.total > 0) ...[
                const SizedBox(width: 10),
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 12,
                  color: c.foregroundMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  '${checklist.done}/${checklist.total}',
                  style: context.uiText.caption,
                ),
              ],
              const Spacer(),
              Text(
                words == 1 ? '1 word' : '$words words',
                style: context.uiText.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
