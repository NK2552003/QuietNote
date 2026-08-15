import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

enum _NoteSort { recent, title }

/// Controls how much of each note is shown on the grid tile.
enum _CardViewMode { titleOnly, titleAndPreview, full }

extension on _CardViewMode {
  String get label => switch (this) {
    _CardViewMode.titleOnly => 'T',
    _CardViewMode.titleAndPreview => 'T + D',
    _CardViewMode.full => 'Def',
  };

  IconData get icon => switch (this) {
    _CardViewMode.titleOnly => Icons.short_text_rounded,
    _CardViewMode.titleAndPreview => Icons.notes_rounded,
    _CardViewMode.full => Icons.view_agenda_outlined,
  };
}

final _noteQueryProvider = StateProvider<String>((ref) => '');
final _noteSortProvider = StateProvider<_NoteSort>((ref) => _NoteSort.recent);
final _noteTagFilterProvider = StateProvider<String?>((ref) => null);
final _noteViewModeProvider = StateProvider<_CardViewMode>(
  (ref) => _CardViewMode.full,
);
// Single column, one card per row, by default — every card is free to be
// exactly as tall as its own content (see UiCardGrid's dynamicHeight mode)
// instead of being squeezed or padded to match a fixed row height.
final _noteColumnsProvider = StateProvider<int>((ref) => 1);

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
    final tagFilter = ref.watch(_noteTagFilterProvider);
    final viewMode = ref.watch(_noteViewModeProvider);
    final columns = ref.watch(_noteColumnsProvider);

    return UiPage(
      header: const UiHeader(
        title: 'Notes',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Capture ideas, organize thoughts & build your personal knowledge base.',
      ),
      floatingActionButton: UiFab(
        tooltip: 'New note',
        onPressed: () => context.push('/notes/new'),
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
              final byQuery =
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

              final allTags = distinctTagsInUse(notes.map((n) => n.tags));
              final filtered = tagFilter == null
                  ? byQuery
                  : byQuery
                        .where(
                          (n) => parseTagsCsv(n.tags).contains(tagFilter),
                        )
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
                  if (allTags.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final tag in allTags)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: UiBadge(
                                label: tag,
                                icon: Icons.sell_outlined,
                                variant: tagFilter == tag
                                    ? UiBadgeVariant.solid
                                    : UiBadgeVariant.soft,
                                intent: tagFilter == tag
                                    ? UiIntent.primary
                                    : UiIntent.neutral,
                                onTap: () => ref
                                        .read(_noteTagFilterProvider.notifier)
                                        .state =
                                    tagFilter == tag ? null : tag,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: UiToggleGroup<_CardViewMode>(
                          variant: UiToggleGroupVariant.segmented,
                          size: UiSize.sm,
                          expand: true,
                          value: viewMode,
                          onChanged: (v) =>
                              ref.read(_noteViewModeProvider.notifier).state =
                                  v,
                          options: [
                            for (final mode in _CardViewMode.values)
                              UiToggleOption(
                                value: mode,
                                label: mode.label,
                                icon: mode.icon,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      UiToggleGroup<int>(
                        variant: UiToggleGroupVariant.segmented,
                        size: UiSize.sm,
                        value: columns,
                        onChanged: (v) =>
                            ref.read(_noteColumnsProvider.notifier).state = v,
                        options: const [
                          UiToggleOption(
                            value: 1,
                            label: '1',
                            icon: Icons.view_agenda_outlined,
                            tooltip: '1 column',
                          ),
                          UiToggleOption(
                            value: 2,
                            label: '2',
                            icon: Icons.grid_view_rounded,
                            tooltip: '2 columns',
                          ),
                        ],
                      ),
                    ],
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
                      // Every card is exactly as tall as its own content —
                      // no fixed row height — via UiCardGrid's masonry mode.
                      // The column count comes straight from the toggle
                      // above rather than the available width, so the
                      // user's choice always wins; default is 1 column, so
                      // by default this is simply one card per row.
                      key: ValueKey('$viewMode-$columns'),
                      dynamicHeight: true,
                      mobileColumns: columns,
                      tabletColumns: columns,
                      desktopColumns: columns,
                      largeColumns: columns,
                      children: filtered
                          .map(
                            (note) => _NoteCard(
                              note: note,
                              viewMode: viewMode,
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
  const _NoteCard({
    required this.note,
    required this.viewMode,
    required this.onDelete,
  });

  final Note note;
  final _CardViewMode viewMode;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final checklist = _checklistStats(note.content);
    final preview = _plainPreview(note.content);
    final words = _wordCount(note.content);
    final tags = parseTagsCsv(note.tags);
    final showPreview = viewMode != _CardViewMode.titleOnly;
    final showTags = viewMode == _CardViewMode.full && tags.isNotEmpty;
    final showWordCount = viewMode != _CardViewMode.titleOnly;

    return UiCard(
      semanticLabel:
          'Preview note: ${note.title.isEmpty ? 'Untitled' : note.title}',
      onTap: () => context.push('/notes/${note.id}'),
      onLongPress: onDelete,
      padding: EdgeInsets.all(context.sp(context.uiSpace.lg)),
      // Every element below has a capped height (maxLines on text, a fixed
      // height on the tag row) — the card grid gives each tile exactly the
      // height its own content needs (see dynamicHeight on UiCardGrid), so
      // these caps just keep any one card from growing unreasonably tall
      // rather than fitting inside a shared row height. We deliberately
      // avoid Expanded/Flexible here: UiCard measures this
      // child inside an AnimatedCrossFade (for the collapsible feature),
      // which lays it out with an unbounded height to get its natural size
      // — a flex child would throw ("incoming height constraints are
      // unbounded") under that measurement pass and the tile would fail to
      // render.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.uiText.bodyStrong,
                  ),
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
          if (showPreview) ...[
            const SizedBox(height: 8),
            Text(
              preview.isEmpty ? 'No content' : preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.uiText.body.copyWith(color: c.foregroundMuted),
            ),
          ],
          if (showTags) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: tags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => UiBadge(
                  label: tags[i],
                  size: UiSize.sm,
                  variant: UiBadgeVariant.soft,
                  intent: UiIntent.neutral,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: c.foregroundMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _relativeDate(note.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.uiText.caption,
                      ),
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
                  ],
                ),
              ),
              if (showWordCount) ...[
                const SizedBox(width: 8),
                Text(
                  words == 1 ? '1 word' : '$words words',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiText.caption,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}