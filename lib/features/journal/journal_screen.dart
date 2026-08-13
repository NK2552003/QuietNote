import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/utils/tag_utils.dart';

const Map<String, String> _moodEmoji = {
  'Great': '😃',
  'Neutral': '😐',
  'Bad': '😔',
};

final _moodFilterProvider = StateProvider<String?>((ref) => null);
final _journalTagFilterProvider = StateProvider<String?>((ref) => null);

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

UiIntent _moodIntent(String mood) {
  switch (mood) {
    case 'Great':
      return UiIntent.success;
    case 'Bad':
      return UiIntent.danger;
    default:
      return UiIntent.neutral;
  }
}

/// Longest run of consecutive days (ending today or yesterday) that have
/// at least one journal entry — mirrors the "streak" language used
/// elsewhere in the app (habits, routines) for a consistent feel.
int _currentStreak(List<JournalData> entries) {
  if (entries.isEmpty) return 0;
  final days = entries.map((e) => _dateOnly(e.createdAt)).toSet();
  var cursor = _dateOnly(DateTime.now());
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(cursor)) return 0;
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    JournalData entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'This removes the entry from ${DateFormat.yMMMd().format(entry.createdAt)} and any attached photos. This can\'t be undone.',
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
      await ref.read(journalRepositoryProvider).deleteEntry(entry.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journalAsync = ref.watch(journalStreamProvider);
    final moodFilter = ref.watch(_moodFilterProvider);
    final tagFilter = ref.watch(_journalTagFilterProvider);

    return UiPage(
      header: UiHeader(
        title: 'Journal',
        subtitle: 'Reflect, review, and reset.',
        actions: [
          UiButton(
            label: 'Write',
            leadingIcon: Icons.edit_outlined,
            onPressed: () => context.push('/journal/new'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          journalAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return const UiEmptyState(
                  title: 'No journal entries',
                  message: 'Take a moment to reflect on your day.',
                  icon: Icons.book_outlined,
                );
              }

              final streak = _currentStreak(entries);
              final byMood = moodFilter == null
                  ? entries
                  : entries
                        .where((e) => (e.mood ?? 'Neutral') == moodFilter)
                        .toList();
              final allTags = distinctTagsInUse(entries.map((e) => e.tags));
              final filtered = tagFilter == null
                  ? byMood
                  : byMood
                        .where(
                          (e) => parseTagsCsv(e.tags).contains(tagFilter),
                        )
                        .toList();

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
                              Text('Entries', style: context.uiText.caption),
                              const SizedBox(height: 4),
                              Text(
                                '${entries.length}',
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
                              Text(
                                'Writing streak',
                                style: context.uiText.caption,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$streak',
                                    style: context.uiText.heading,
                                  ),
                                  const SizedBox(width: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      streak == 1 ? 'day' : 'days',
                                      style: context.uiText.caption,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (ctx) {
                      final moodOptions = <UiToggleOption<String?>>[
                        const UiToggleOption(value: null, label: 'All'),
                        for (final entry in _moodEmoji.entries)
                          UiToggleOption(
                            value: entry.key,
                            label: '${entry.value} ${entry.key}',
                          ),
                      ];
                      final shouldExpand = moodOptions.length <= 4;
                      final group = UiToggleGroup<String?>(
                        variant: UiToggleGroupVariant.segmented,
                        size: UiSize.sm,
                        expand: shouldExpand,
                        value: moodFilter,
                        onChanged: (v) =>
                            ref.read(_moodFilterProvider.notifier).state = v,
                        options: moodOptions,
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
                                        .read(
                                          _journalTagFilterProvider.notifier,
                                        )
                                        .state =
                                    tagFilter == tag ? null : tag,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (filtered.isEmpty)
                    UiEmptyState(
                      title: 'No entries here',
                      message: 'Nothing matches "$moodFilter" yet.',
                      icon: Icons.filter_alt_off_outlined,
                    )
                  else
                    UiCardGrid(
                      // Keep every entry preview the same height and let the
                      // grid choose a readable width at every screen size.
                      // Tall enough for title + preview + tags + footer so
                      // the tile never clips or overflows.
                      mainAxisExtent: 256,
                      maxCrossAxisExtent: 340,
                      children: filtered
                          .map(
                            (entry) => _JournalCard(
                              entry: entry,
                              onDelete: () =>
                                  _confirmDelete(context, ref, entry),
                            ),
                          )
                          .toList(),
                    ),
                ],
              );
            },
            loading: () => Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: UiCard(
                    loading: true,
                    loadingHeight: 72,
                    child: SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            error: (err, stack) => UiCard(
              accentColor: context.uiColors.destructive,
              child: Text(
                'Could not load journal: $err',
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

class _JournalCard extends StatelessWidget {
  const _JournalCard({required this.entry, required this.onDelete});

  final JournalData entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final mood = entry.mood ?? 'Neutral';
    final emoji = _moodEmoji[mood] ?? '📝';
    final hasPhotos = entry.entry.contains('local-image://');
    final tags = parseTagsCsv(entry.tags);
    final words = _wordCount(entry.entry);
    final preview = entry.entry
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
        .trim();

    return UiCard(
      semanticLabel: 'Preview journal entry: ${entry.title}',
      onTap: () => context.push('/journal/${entry.id}'),
      onLongPress: onDelete,
      padding: EdgeInsets.all(context.sp(context.uiSpace.lg)),
      // Every element below has a capped height (maxLines on text, a fixed
      // height on the tag row) chosen so the worst-case total always fits
      // inside the grid's mainAxisExtent. We deliberately avoid Expanded/
      // Flexible here: UiCard measures this child inside an
      // AnimatedCrossFade (for the collapsible feature), which lays it out
      // with an unbounded height to get its natural size — a flex child
      // would throw ("incoming height constraints are unbounded") under
      // that measurement pass and the tile would fail to render.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entry.title.isEmpty ? 'Untitled entry' : entry.title,
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
                tooltip: 'Delete entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview.isEmpty ? 'No content' : preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.uiText.body.copyWith(color: c.foregroundMuted),
          ),
          if (tags.isNotEmpty) ...[
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
                    UiBadge(
                      label: mood,
                      size: UiSize.sm,
                      variant: UiBadgeVariant.soft,
                      intent: _moodIntent(mood),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: c.foregroundMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _relativeDate(entry.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.uiText.caption,
                      ),
                    ),
                    if (hasPhotos) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.image_outlined,
                        size: 12,
                        color: c.foregroundMuted,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                words == 1 ? '1 word' : '$words words',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.uiText.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
