import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:quietnote/features/flashcards/sm2.dart';

/// Deck list + collection-wide study stats. Entry point for Feature 4.
class FlashcardDecksScreen extends ConsumerStatefulWidget {
  const FlashcardDecksScreen({super.key});

  @override
  ConsumerState<FlashcardDecksScreen> createState() =>
      _FlashcardDecksScreenState();
}

class _FlashcardDecksScreenState extends ConsumerState<FlashcardDecksScreen> {
  String _query = '';
  String? _subject; // null = all subjects
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final decksAsync = ref.watch(flashcardDecksStreamProvider);
    final allCards =
        ref.watch(allFlashcardsStreamProvider).valueOrNull ?? const <Flashcard>[];
    final stats = ref.watch(flashcardStatsProvider(''));

    return UiPage(
      header: UiHeader(
        title: 'Flashcards',
        leading: const QuietNoteMark(size: 38),
        subtitle: 'Spaced repetition that schedules what you review, and when.',
        actions: [
          UiIconButton(
            icon: _showArchived
                ? Icons.inventory_2
                : Icons.inventory_2_outlined,
            variant: UiVariant.ghost,
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          if (stats.due > 0)
            UiButton(
              label: 'Study ${stats.due} due',
              leadingIcon: Icons.bolt_outlined,
              onPressed: () => context.push('/flashcards/study'),
            ),
        ],
      ),
      floatingActionButton: UiFab(
        tooltip: 'New deck',
        onPressed: () => context.push('/flashcards/new'),
      ),
      child: decksAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 48),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (err, _) => UiCard(
          accentColor: c.destructive,
          child: Text(
            'Could not load decks: $err',
            style: context.uiText.caption.copyWith(color: c.destructive),
          ),
        ),
        data: (decks) {
          final subjects = distinctTagsInUse(decks.map((d) => d.subject));
          final visible = decks.where((deck) {
            if (deck.archived != _showArchived) return false;
            if (_subject != null &&
                !parseTagsCsv(deck.subject).contains(_subject)) {
              return false;
            }
            if (_query.trim().isEmpty) return true;
            final q = _query.toLowerCase();
            return deck.title.toLowerCase().contains(q) ||
                (deck.description ?? '').toLowerCase().contains(q) ||
                (deck.subject ?? '').toLowerCase().contains(q);
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (decks.isNotEmpty) ...[
                _CollectionStats(stats: stats),
                const SizedBox(height: 16),
                UiInput.search(
                  hintText: 'Search decks',
                  onChanged: (v) => setState(() => _query = v),
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  UiToggleGroup<String>(
                    value: _subject ?? '',
                    onChanged: (v) =>
                        setState(() => _subject = v.isEmpty ? null : v),
                    scrollableOnMobile: true,
                    size: UiSize.sm,
                    options: [
                      const UiToggleOption(value: '', label: 'All'),
                      for (final s in subjects)
                        UiToggleOption(value: s, label: s),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
              ],
              if (visible.isEmpty)
                UiEmptyState(
                  title: _showArchived
                      ? 'Nothing archived'
                      : decks.isEmpty
                          ? 'No decks yet'
                          : 'No decks match',
                  message: _showArchived
                      ? 'Archived decks stay out of your study queue until you restore them.'
                      : decks.isEmpty
                          ? 'Create a deck, or send a note straight to flashcards from the note editor.'
                          : 'Try a different search or subject filter.',
                  icon: Icons.style_outlined,
                  action: decks.isEmpty
                      ? UiButton(
                          label: 'Create your first deck',
                          leadingIcon: Icons.add,
                          onPressed: () => context.push('/flashcards/new'),
                        )
                      : null,
                )
              else
                for (final deck in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DeckCard(
                      deck: deck,
                      cards: allCards.where((c) => c.deckId == deck.id).toList(),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _CollectionStats extends StatelessWidget {
  const _CollectionStats({required this.stats});

  final FlashcardStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return UiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat(label: 'Due now', value: '${stats.due}'),
              _Stat(label: 'Cards', value: '${stats.total}'),
              _Stat(label: 'Learned', value: '${stats.learned}'),
              _Stat(
                label: 'Accuracy',
                value: stats.reviews == 0
                    ? '—'
                    : '${(stats.accuracy * 100).round()}%',
              ),
              _Stat(label: 'Streak', value: '${stats.streakDays}d'),
              _Stat(label: 'Today', value: '${stats.reviewedToday}'),
            ],
          ),
          if (stats.total > 0) ...[
            const SizedBox(height: 14),
            UiProgressBar(
              value: stats.learnedRatio,
              label: 'Learned',
              showValue: true,
              intent: UiIntent.success,
            ),
          ],
          if (stats.forecast.any((v) => v > 0)) ...[
            const SizedBox(height: 14),
            Text(
              'Next 14 days',
              style: context.uiText.caption.copyWith(color: c.foregroundMuted),
            ),
            const SizedBox(height: 6),
            UiSparkChart(
              values: stats.forecast.map((v) => v.toDouble()).toList(),
              height: 44,
              filled: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return SizedBox(
      width: 88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.uiText.heading),
          Text(
            label,
            style: context.uiText.caption.copyWith(color: c.foregroundMuted),
          ),
        ],
      ),
    );
  }
}

class _DeckCard extends ConsumerWidget {
  const _DeckCard({required this.deck, required this.cards});

  final FlashcardDeck deck;
  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.uiColors;
    final color = deck.color != null ? Color(deck.color!) : c.primary;
    final active = cards.where((card) => !card.suspended);
    final due = active.where((card) => isDue(card.dueDate)).length;
    final learned = cards
        .where((card) =>
            isLearned(reviewCount: card.reviewCount, intervalDays: card.intervalDays))
        .length;
    final subjects = parseTagsCsv(deck.subject);

    return UiCard(
      onTap: () => context.push('/flashcards/${deck.id}'),
      accentColor: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.title, style: context.uiText.subheading),
                    if ((deck.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        deck.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.uiText.caption
                            .copyWith(color: c.foregroundMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (due > 0)
                UiBadge(
                  label: '$due due',
                  intent: UiIntent.warning,
                  size: UiSize.xs,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              UiBadge(
                label: '${cards.length} cards',
                size: UiSize.xs,
                variant: UiBadgeVariant.outline,
              ),
              UiBadge(
                label: '$learned learned',
                size: UiSize.xs,
                intent: UiIntent.success,
              ),
              for (final s in subjects)
                UiBadge(label: s, size: UiSize.xs, intent: UiIntent.info),
              if (deck.archived)
                const UiBadge(
                  label: 'Archived',
                  size: UiSize.xs,
                  intent: UiIntent.neutral,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              UiButton(
                label: due > 0 ? 'Study $due' : 'Study',
                size: UiSize.sm,
                leadingIcon: Icons.play_arrow_rounded,
                onPressed: cards.isEmpty
                    ? null
                    : () => context.push('/flashcards/${deck.id}/study'),
              ),
              const SizedBox(width: 8),
              UiButton(
                label: 'Cards',
                size: UiSize.sm,
                variant: UiVariant.ghost,
                leadingIcon: Icons.list_alt_outlined,
                onPressed: () => context.push('/flashcards/${deck.id}'),
              ),
              const Spacer(),
              UiIconButton(
                icon: deck.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                tooltip: deck.archived ? 'Restore deck' : 'Archive deck',
                onPressed: () => ref
                    .read(flashcardRepositoryProvider)
                    .setArchived(deck.id, !deck.archived),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
