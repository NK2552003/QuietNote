import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:quietnote/features/flashcards/note_to_cards.dart';
import 'package:quietnote/features/flashcards/sm2.dart';

/// One deck: its stats, its cards, and the tools to add/edit them.
class FlashcardDeckDetailScreen extends ConsumerStatefulWidget {
  const FlashcardDeckDetailScreen({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<FlashcardDeckDetailScreen> createState() =>
      _FlashcardDeckDetailScreenState();
}

class _FlashcardDeckDetailScreenState
    extends ConsumerState<FlashcardDeckDetailScreen> {
  String _query = '';
  _CardFilter _filter = _CardFilter.all;

  Future<void> _addOrEditCard({Flashcard? card}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CardEditorDialog(deckId: widget.deckId, card: card),
    );
    if (saved == true && mounted) {
      UiToast.show(
        context,
        title: card == null ? 'Card added' : 'Card updated',
        intent: UiIntent.success,
      );
    }
  }

  Future<void> _bulkAdd() async {
    final added = await showDialog<int>(
      context: context,
      builder: (ctx) => _BulkAddDialog(deckId: widget.deckId),
    );
    if (added != null && added > 0 && mounted) {
      UiToast.show(
        context,
        title: 'Added $added cards',
        intent: UiIntent.success,
      );
    }
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Confirm',
              style: TextStyle(color: context.uiColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  Future<void> _deleteDeck(FlashcardRepository repo) async {
    await _confirm(
      title: 'Delete deck?',
      message:
          'This removes the deck, its cards and its review history. This can\'t be undone.',
      onConfirm: () async {
        await repo.deleteDeck(widget.deckId);
        if (mounted) context.go('/flashcards');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final deck = ref.watch(flashcardDeckProvider(widget.deckId)).valueOrNull;
    final cards = ref.watch(deckCardsStreamProvider(widget.deckId)).valueOrNull ??
        const <Flashcard>[];
    final stats = ref.watch(flashcardStatsProvider(widget.deckId));
    final repo = ref.read(flashcardRepositoryProvider);

    final visible = cards.where((card) {
      switch (_filter) {
        case _CardFilter.all:
          break;
        case _CardFilter.due:
          if (card.suspended || !isDue(card.dueDate)) return false;
        case _CardFilter.newCards:
          if (card.reviewCount != 0) return false;
        case _CardFilter.learned:
          if (!isLearned(
            reviewCount: card.reviewCount,
            intervalDays: card.intervalDays,
          )) {
            return false;
          }
        case _CardFilter.suspended:
          if (!card.suspended) return false;
      }
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return card.front.toLowerCase().contains(q) ||
          card.back.toLowerCase().contains(q) ||
          (card.tags ?? '').toLowerCase().contains(q);
    }).toList();

    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/flashcards'),
        ),
        title: deck?.title ?? 'Deck',
        subtitle: deck?.description,
        actions: [
          UiIconButton(
            icon: Icons.edit_outlined,
            variant: UiVariant.ghost,
            tooltip: 'Edit deck',
            onPressed: () => context.push('/flashcards/edit/${widget.deckId}'),
          ),
          UiIconButton(
            icon: Icons.restart_alt,
            variant: UiVariant.ghost,
            tooltip: 'Reset progress',
            onPressed: () => _confirm(
              title: 'Reset progress?',
              message:
                  'Every card returns to "new" and the review history for this deck is cleared.',
              onConfirm: () => repo.resetDeckProgress(widget.deckId),
            ),
          ),
          UiIconButton(
            icon: Icons.delete_outline,
            variant: UiVariant.ghost,
            tooltip: 'Delete deck',
            onPressed: () => _deleteDeck(repo),
          ),
        ],
      ),

      floatingActionButton: UiFab(
        tooltip: 'Add card',
        onPressed: _addOrEditCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            UiButton(
            label: stats.due > 0 ? 'Study ${stats.due}' : 'Study',
            leadingIcon: Icons.play_arrow_rounded,
            onPressed: cards.isEmpty
                ? null
                : () => context.push('/flashcards/${widget.deckId}/study'),
          ),
          const SizedBox(height: 16),
          UiCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MiniStat(label: 'Cards', value: '${stats.total}'),
                    _MiniStat(label: 'Due', value: '${stats.due}'),
                    _MiniStat(label: 'New', value: '${stats.newCards}'),
                    _MiniStat(label: 'Learned', value: '${stats.learned}'),
                    _MiniStat(
                      label: 'Accuracy',
                      value: stats.reviews == 0
                          ? '—'
                          : '${(stats.accuracy * 100).round()}%',
                    ),
                    _MiniStat(label: 'Reviews', value: '${stats.reviews}'),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: UiInput.search(
                  hintText: 'Search cards',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              UiButton(
                label: 'Bulk add',
                size: UiSize.sm,
                variant: UiVariant.secondary,
                leadingIcon: Icons.playlist_add,
                onPressed: _bulkAdd,
              ),
            ],
          ),
          const SizedBox(height: 12),
          UiToggleGroup<_CardFilter>(
            value: _filter,
            size: UiSize.sm,
            scrollableOnMobile: true,
            onChanged: (v) => setState(() => _filter = v),
            options: const [
              UiToggleOption(value: _CardFilter.all, label: 'All'),
              UiToggleOption(value: _CardFilter.due, label: 'Due'),
              UiToggleOption(value: _CardFilter.newCards, label: 'New'),
              UiToggleOption(value: _CardFilter.learned, label: 'Learned'),
              UiToggleOption(value: _CardFilter.suspended, label: 'Suspended'),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            UiEmptyState(
              title: cards.isEmpty ? 'No cards yet' : 'No cards match',
              message: cards.isEmpty
                  ? 'Add cards one at a time, paste a batch, or send a note to this deck.'
                  : 'Try another search or filter.',
              icon: Icons.style_outlined,
              action: cards.isEmpty
                  ? UiButton(
                      label: 'Add a card',
                      leadingIcon: Icons.add,
                      onPressed: _addOrEditCard,
                    )
                  : null,
            )
          else
            for (final card in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: UiCard(
                  onTap: () => _addOrEditCard(card: card),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              card.front,
                              style: context.uiText.bodyStrong,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          UiIconButton(
                            icon: card.suspended
                                ? Icons.play_circle_outline
                                : Icons.pause_circle_outline,
                            size: UiSize.sm,
                            variant: UiVariant.ghost,
                            tooltip: card.suspended ? 'Unsuspend' : 'Suspend',
                            onPressed: () =>
                                repo.setSuspended(card.id, !card.suspended),
                          ),
                          UiIconButton(
                            icon: Icons.delete_outline,
                            size: UiSize.sm,
                            variant: UiVariant.ghost,
                            tooltip: 'Delete card',
                            onPressed: () => _confirm(
                              title: 'Delete card?',
                              message: 'This card and its review history go away.',
                              onConfirm: () => repo.deleteCard(card.id),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.back,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.uiText.caption
                            .copyWith(color: c.foregroundMuted),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          UiBadge(
                            label: card.reviewCount == 0
                                ? 'New'
                                : 'Due ${_dueLabel(card.dueDate)}',
                            size: UiSize.xs,
                            intent: card.reviewCount == 0
                                ? UiIntent.info
                                : isDue(card.dueDate)
                                    ? UiIntent.warning
                                    : UiIntent.neutral,
                          ),
                          UiBadge(
                            label: 'ease ${card.easeFactor.toStringAsFixed(2)}',
                            size: UiSize.xs,
                            variant: UiBadgeVariant.outline,
                          ),
                          if (card.lapses > 0)
                            UiBadge(
                              label: '${card.lapses} lapses',
                              size: UiSize.xs,
                              intent: UiIntent.danger,
                            ),
                          if (card.suspended)
                            const UiBadge(label: 'Suspended', size: UiSize.xs),
                          for (final tag in parseTagsCsv(card.tags))
                            UiBadge(
                              label: tag,
                              size: UiSize.xs,
                              variant: UiBadgeVariant.soft,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

enum _CardFilter { all, due, newCards, learned, suspended }

String _dueLabel(DateTime due) {
  final now = DateTime.now();
  final days = DateTime(due.year, due.month, due.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days <= 0) return 'now';
  return 'in ${formatIntervalDays(days)}';
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.uiText.subheading),
          Text(
            label,
            style: context.uiText.caption
                .copyWith(color: context.uiColors.foregroundMuted),
          ),
        ],
      ),
    );
  }
}

/// Add/edit a single card.
class _CardEditorDialog extends ConsumerStatefulWidget {
  const _CardEditorDialog({required this.deckId, this.card});

  final String deckId;
  final Flashcard? card;

  @override
  ConsumerState<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends ConsumerState<_CardEditorDialog> {
  late final TextEditingController _front =
      TextEditingController(text: widget.card?.front ?? '');
  late final TextEditingController _back =
      TextEditingController(text: widget.card?.back ?? '');
  late final TextEditingController _hint =
      TextEditingController(text: widget.card?.hint ?? '');
  late List<String> _tags = parseTagsCsv(widget.card?.tags);
  bool _saving = false;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final front = _front.text.trim();
    final back = _back.text.trim();
    if (front.isEmpty || back.isEmpty) {
      UiToast.show(
        context,
        title: 'Both sides are required',
        intent: UiIntent.warning,
      );
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(flashcardRepositoryProvider);
    final hint = _hint.text.trim();
    if (widget.card == null) {
      await repo.addCard(
        deckId: widget.deckId,
        front: front,
        back: back,
        hint: hint.isEmpty ? null : hint,
        tags: _tags,
      );
    } else {
      await repo.updateCard(
        widget.card!.id,
        front: front,
        back: back,
        hint: hint.isEmpty ? null : hint,
        tags: _tags,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.card == null ? 'New card' : 'Edit card'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiField(
                label: 'Front',
                child: UiTextarea(
                  controller: _front,
                  hintText: 'Question or prompt',
                  rows: 3,
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 12),
              UiField(
                label: 'Back',
                child: UiTextarea(
                  controller: _back,
                  hintText: 'Answer',
                  rows: 3,
                ),
              ),
              const SizedBox(height: 12),
              UiField(
                label: 'Hint (optional)',
                child: UiInput(
                  controller: _hint,
                  hintText: 'A nudge shown on request',
                ),
              ),
              const SizedBox(height: 12),
              UiField(
                label: 'Tags',
                child: UiTagInput(
                  tags: _tags,
                  hintText: 'Add tag',
                  onChanged: (t) => setState(() => _tags = t),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        UiButton(label: 'Save', loading: _saving, onPressed: _save),
      ],
    );
  }
}

/// Paste many cards at once, one `front | back` per line.
class _BulkAddDialog extends ConsumerStatefulWidget {
  const _BulkAddDialog({required this.deckId});

  final String deckId;

  @override
  ConsumerState<_BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends ConsumerState<_BulkAddDialog> {
  final _controller = TextEditingController();
  int _parsed = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final drafts = parseBulkCards(_controller.text);
    if (drafts.isEmpty) {
      UiToast.show(
        context,
        title: 'Nothing to add',
        message: 'Use one card per line: front | back',
        intent: UiIntent.warning,
      );
      return;
    }
    setState(() => _saving = true);
    final count = await ref.read(flashcardRepositoryProvider).bulkAddCards(
          deckId: widget.deckId,
          pairs: drafts.map((d) => (front: d.front, back: d.back)).toList(),
        );
    if (mounted) Navigator.pop(context, count);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bulk add cards'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'One card per line. Separate the two sides with " | ", " - " or ": ".',
              style: context.uiText.caption
                  .copyWith(color: context.uiColors.foregroundMuted),
            ),
            const SizedBox(height: 12),
            UiTextarea(
              controller: _controller,
              hintText: 'Mitochondria | Powerhouse of the cell',
              rows: 8,
              autofocus: true,
              onChanged: (v) =>
                  setState(() => _parsed = parseBulkCards(v).length),
            ),
            const SizedBox(height: 8),
            Text('$_parsed cards detected', style: context.uiText.caption),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        UiButton(
          label: 'Add $_parsed',
          loading: _saving,
          onPressed: _parsed == 0 ? null : _save,
        ),
      ],
    );
  }
}
