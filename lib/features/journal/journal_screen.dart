import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';

const Map<String, String> _moodEmoji = {
  'Great': '😃',
  'Neutral': '😐',
  'Bad': '😔',
};

final _moodFilterProvider = StateProvider<String?>((ref) => null);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
              final filtered = moodFilter == null
                  ? entries
                  : entries
                        .where((e) => (e.mood ?? 'Neutral') == moodFilter)
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
                      mainAxisExtent: 196,
                      maxCrossAxisExtent: 380,
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
    final mood = entry.mood ?? 'Neutral';
    final emoji = _moodEmoji[mood] ?? '📝';
    final hasPhotos = entry.entry.contains('local-image://');
    final preview = entry.entry
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
        .trim();

    return UiCard(
      semanticLabel: 'Preview journal entry: ${entry.title}',
      onTap: () => context.push('/journal/${entry.id}'),
      onLongPress: onDelete,
      padding: EdgeInsets.all(context.sp(context.uiSpace.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.uiText.bodyStrong,
                    ),
                    Text(
                      DateFormat.yMMMd().format(entry.createdAt),
                      style: context.uiText.caption,
                    ),
                  ],
                ),
              ),
              if (hasPhotos)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: context.uiColors.foregroundMuted,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: context.uiColors.foregroundMuted,
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
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: context.uiText.body.copyWith(
              color: context.uiColors.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
