import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/flashcards/sm2.dart';

/// A study session. Pass a [deckId] to study one deck, or omit it to study
/// everything due across the collection.
class FlashcardStudyScreen extends ConsumerStatefulWidget {
  const FlashcardStudyScreen({super.key, this.deckId});

  final String? deckId;

  @override
  ConsumerState<FlashcardStudyScreen> createState() =>
      _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends ConsumerState<FlashcardStudyScreen> {
  /// The queue is snapshotted once so grading a card doesn't reshuffle the
  /// list mid-session.
  List<Flashcard>? _queue;
  int _index = 0;
  bool _revealed = false;
  bool _showHint = false;
  bool _busy = false;
  int _again = 0;
  int _correct = 0;
  Flashcard? _lastCardBefore;

  Future<void> _load() async {
    final repo = ref.read(flashcardRepositoryProvider);
    final cards = await repo.watchDueCards(widget.deckId).first;
    if (!mounted) return;
    setState(() {
      _queue = cards;
      _index = 0;
      _revealed = false;
      _showHint = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _grade(int rating) async {
    final queue = _queue;
    if (queue == null || _index >= queue.length || _busy) return;
    setState(() => _busy = true);
    final card = queue[_index];
    _lastCardBefore = card;
    await ref.read(flashcardRepositoryProvider).gradeCard(card, rating);
    if (!mounted) return;
    setState(() {
      if (rating == 0) {
        _again += 1;
        // "Again" cards come back at the end of this session too.
        queue.add(card);
      } else {
        _correct += 1;
      }
      _index += 1;
      _revealed = false;
      _showHint = false;
      _busy = false;
    });
  }

  Future<void> _undo() async {
    final before = _lastCardBefore;
    if (before == null || _index == 0) return;
    await ref.read(flashcardRepositoryProvider).undoReview(before, null);
    if (!mounted) return;
    setState(() {
      _index -= 1;
      _revealed = false;
      _showHint = false;
      _lastCardBefore = null;
    });
  }

  void _exit() {
    context.canPop() ? context.pop() : context.go('/flashcards');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final queue = _queue;
    final deck = widget.deckId == null
        ? null
        : ref.watch(flashcardDeckProvider(widget.deckId!)).valueOrNull;

    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.close,
          variant: UiVariant.ghost,
          tooltip: 'End session',
          onPressed: _exit,
        ),
        title: deck?.title ?? 'Study',
        subtitle: queue == null
            ? null
            : '${_index.clamp(0, queue.length)} of ${queue.length} reviewed',
        actions: [
          if (_index > 0)
            UiIconButton(
              icon: Icons.undo,
              variant: UiVariant.ghost,
              tooltip: 'Undo last rating',
              onPressed: _undo,
            ),
        ],
      ),
      child: queue == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 64),
                child: CircularProgressIndicator(),
              ),
            )
          : queue.isEmpty
              ? UiEmptyState(
                  title: 'Nothing due',
                  message:
                      'You are all caught up. Come back when cards are scheduled again.',
                  icon: Icons.check_circle_outline,
                  action: UiButton(label: 'Back to decks', onPressed: _exit),
                )
              : _index >= queue.length
                  ? _SessionSummary(
                      reviewed: _correct + _again,
                      correct: _correct,
                      again: _again,
                      onDone: _exit,
                      onAgain: _load,
                    )
                  : _buildCard(context, queue[_index], queue.length, c),
    );
  }

  Widget _buildCard(
    BuildContext context,
    Flashcard card,
    int total,
    dynamic c,
  ) {
    final intervals = previewIntervals(
      ease: card.easeFactor,
      intervalDays: card.intervalDays,
      reviewCount: card.reviewCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiProgressBar(
          value: total == 0 ? 0 : _index / total,
          label: 'Session progress',
          showValue: true,
        ),
        const SizedBox(height: 16),
        UiCard(
          padding: const EdgeInsets.all(24),
          minHeight: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                card.reviewCount == 0 ? 'NEW CARD' : 'REVIEW',
                style: context.uiText.caption
                    .copyWith(color: context.uiColors.foregroundMuted),
              ),
              const SizedBox(height: 12),
              Text(card.front, style: context.uiText.heading),
              if (_showHint && (card.hint ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Hint: ${card.hint}',
                  style: context.uiText.caption
                      .copyWith(color: context.uiColors.info),
                ),
              ],
              if (_revealed) ...[
                const SizedBox(height: 20),
                const UiDivider(),
                const SizedBox(height: 20),
                Text(card.back, style: context.uiText.body),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!_revealed)
          Row(
            children: [
              if ((card.hint ?? '').isNotEmpty && !_showHint) ...[
                UiButton(
                  label: 'Hint',
                  variant: UiVariant.ghost,
                  leadingIcon: Icons.lightbulb_outline,
                  onPressed: () => setState(() => _showHint = true),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: UiButton(
                  label: 'Show answer',
                  expand: true,
                  onPressed: () => setState(() => _revealed = true),
                ),
              ),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var rating = 0; rating < 4; rating++)
                UiButton(
                  label:
                      '${kRatingLabels[rating]} · ${formatIntervalDays(intervals[rating])}',
                  size: UiSize.sm,
                  variant:
                      rating == 0 ? UiVariant.secondary : UiVariant.primary,
                  intent: switch (rating) {
                    0 => UiIntent.danger,
                    1 => UiIntent.warning,
                    2 => UiIntent.primary,
                    _ => UiIntent.success,
                  },
                  onPressed: _busy ? null : () => _grade(rating),
                ),
            ],
          ),
      ],
    );
  }
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({
    required this.reviewed,
    required this.correct,
    required this.again,
    required this.onDone,
    required this.onAgain,
  });

  final int reviewed;
  final int correct;
  final int again;
  final VoidCallback onDone;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final accuracy = reviewed == 0 ? 0 : (correct / reviewed * 100).round();
    return UiCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Session complete', style: context.uiText.heading),
          const SizedBox(height: 12),
          Text(
            '$reviewed reviews · $correct remembered · $again to relearn · $accuracy% accuracy',
            style: context.uiText.body,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              UiButton(
                label: 'Study more',
                variant: UiVariant.secondary,
                onPressed: onAgain,
              ),
              const SizedBox(width: 8),
              UiButton(label: 'Done', onPressed: onDone),
            ],
          ),
        ],
      ),
    );
  }
}
