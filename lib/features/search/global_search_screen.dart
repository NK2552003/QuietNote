import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

final globalSearchQueryProvider = StateProvider<String>((ref) => '');

class GlobalSearchResults {
  const GlobalSearchResults({
    required this.notes,
    required this.journal,
    required this.tasks,
  });

  static const empty = GlobalSearchResults(
    notes: <Note>[],
    journal: <JournalData>[],
    tasks: <Task>[],
  );

  final List<Note> notes;
  final List<JournalData> journal;
  final List<Task> tasks;

  int get totalCount => notes.length + journal.length + tasks.length;
  bool get isEmpty => totalCount == 0;
}

final globalSearchResultsProvider = Provider<GlobalSearchResults>((ref) {
  final q = ref.watch(globalSearchQueryProvider).trim().toLowerCase();
  if (q.isEmpty) return GlobalSearchResults.empty;

  final notes = ref.watch(notesStreamProvider).valueOrNull ?? const <Note>[];
  final journal =
      ref.watch(journalStreamProvider).valueOrNull ?? const <JournalData>[];
  final tasks = ref.watch(tasksStreamProvider).valueOrNull ?? const <Task>[];

  return GlobalSearchResults(
    notes: notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q),
        )
        .toList(),
    journal: journal
        .where(
          (j) =>
              j.title.toLowerCase().contains(q) ||
              j.entry.toLowerCase().contains(q),
        )
        .toList(),
    tasks: tasks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.subtitle.toLowerCase().contains(q) ||
              (t.details ?? '').toLowerCase().contains(q),
        )
        .toList(),
  );
});

/// Strips the most common Markdown punctuation so result rows show a clean
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

class GlobalSearchScreen extends ConsumerWidget {
  const GlobalSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(globalSearchQueryProvider);
    final results = ref.watch(globalSearchResultsProvider);
    final hasQuery = query.trim().isNotEmpty;

    return UiPage(
      header: const UiHeader(
        title: 'Search',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Find anything across Notes, Journal, and Tasks.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiSearchField(
            hintText: 'Search everything...',
            value: query,
            autofocus: true,
            onChanged: (v) =>
                ref.read(globalSearchQueryProvider.notifier).state = v,
          ),
          const SizedBox(height: 16),
          if (!hasQuery)
            const UiEmptyState(
              title: 'Search across everything',
              message: 'Start typing to look through your notes, journal '
                  'entries, and tasks at once.',
              icon: Icons.travel_explore_outlined,
            )
          else if (results.isEmpty)
            UiEmptyState(
              title: 'No matches',
              message: 'Nothing found for "$query".',
              icon: Icons.search_off_rounded,
            )
          else
            UiAccordion(
              variant: UiAccordionVariant.separated,
              allowMultiple: true,
              initiallyOpen: const {0, 1, 2},
              items: [
                UiAccordionItem(
                  title: 'Notes',
                  leadingIcon: Icons.notes_rounded,
                  badge: '${results.notes.length}',
                  content: _ResultSection(
                    empty: 'No notes match.',
                    children: results.notes
                        .map(
                          (n) => _ResultRow(
                            icon: Icons.notes_rounded,
                            title: n.title.isEmpty ? 'Untitled' : n.title,
                            subtitle: _plainPreview(n.content),
                            onTap: () => context.push('/notes/${n.id}'),
                          ),
                        )
                        .toList(),
                  ),
                ),
                UiAccordionItem(
                  title: 'Journal',
                  leadingIcon: Icons.menu_book_outlined,
                  badge: '${results.journal.length}',
                  content: _ResultSection(
                    empty: 'No journal entries match.',
                    children: results.journal
                        .map(
                          (j) => _ResultRow(
                            icon: Icons.menu_book_outlined,
                            title: j.title.isEmpty
                                ? 'Untitled entry'
                                : j.title,
                            subtitle: _plainPreview(j.entry),
                            onTap: () => context.push('/journal/${j.id}'),
                          ),
                        )
                        .toList(),
                  ),
                ),
                UiAccordionItem(
                  title: 'Tasks',
                  leadingIcon: Icons.checklist_rounded,
                  badge: '${results.tasks.length}',
                  content: _ResultSection(
                    empty: 'No tasks match.',
                    children: results.tasks
                        .map(
                          (t) => _ResultRow(
                            icon: Icons.checklist_rounded,
                            title: t.title,
                            subtitle: t.subtitle.isNotEmpty
                                ? t.subtitle
                                : (t.details ?? ''),
                            onTap: () => context.push('/todos/edit/${t.id}'),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.children, required this.empty});

  final List<Widget> children;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          empty,
          style: context.uiText.caption.copyWith(
            color: context.uiColors.foregroundMuted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return UiCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.foregroundMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiText.bodyStrong,
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.uiText.caption.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: c.foregroundMuted),
        ],
      ),
    );
  }
}
