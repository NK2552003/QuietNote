import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:quietnote/features/flashcards/sm2.dart';
import 'package:uuid/uuid.dart';

final flashcardRepositoryProvider = Provider<FlashcardRepository>((ref) {
  return FlashcardRepository(ref.watch(databaseProvider));
});

/// Every deck, newest first. Archived decks are included — the list screen
/// filters them so the archive view can still show them.
final flashcardDecksStreamProvider =
    StreamProvider<List<FlashcardDeck>>((ref) {
  return ref.watch(flashcardRepositoryProvider).watchDecks();
});

final flashcardDeckProvider =
    StreamProvider.family<FlashcardDeck?, String>((ref, deckId) {
  return ref.watch(flashcardRepositoryProvider).watchDeck(deckId);
});

/// All cards in one deck (including suspended ones).
final deckCardsStreamProvider =
    StreamProvider.family<List<Flashcard>, String>((ref, deckId) {
  return ref.watch(flashcardRepositoryProvider).watchCards(deckId);
});

/// Every card across every non-archived deck — powers global stats, the
/// "study everything due" queue and global search.
final allFlashcardsStreamProvider = StreamProvider<List<Flashcard>>((ref) {
  return ref.watch(flashcardRepositoryProvider).watchAllCards();
});

final flashcardReviewsStreamProvider =
    StreamProvider<List<FlashcardReview>>((ref) {
  return ref.watch(flashcardRepositoryProvider).watchReviews();
});

/// Cards due right now, either for one deck (`deckId`) or across all decks
/// when `deckId` is null/empty.
final dueFlashcardsProvider =
    StreamProvider.family<List<Flashcard>, String>((ref, deckId) {
  return ref
      .watch(flashcardRepositoryProvider)
      .watchDueCards(deckId.isEmpty ? null : deckId);
});

/// Decks linked to a specific course, used by the course detail screen.
final courseFlashcardDecksProvider =
    StreamProvider.family<List<FlashcardDeck>, String>((ref, courseId) {
  return ref.watch(flashcardRepositoryProvider).watchDecksForCourse(courseId);
});

/// Aggregate numbers for one deck (or the whole collection when `deckId` is
/// empty), recomputed whenever cards or reviews change.
class FlashcardStats {
  const FlashcardStats({
    required this.total,
    required this.due,
    required this.learned,
    required this.suspended,
    required this.newCards,
    required this.reviews,
    required this.accuracy,
    required this.streakDays,
    required this.reviewedToday,
    required this.forecast,
  });

  static const empty = FlashcardStats(
    total: 0,
    due: 0,
    learned: 0,
    suspended: 0,
    newCards: 0,
    reviews: 0,
    accuracy: 0,
    streakDays: 0,
    reviewedToday: 0,
    forecast: <int>[],
  );

  final int total;
  final int due;
  final int learned;
  final int suspended;
  final int newCards;
  final int reviews;

  /// Share of reviews rated Hard/Good/Easy (i.e. not "Again"), 0..1.
  final double accuracy;
  final int streakDays;
  final int reviewedToday;
  final List<int> forecast;

  double get learnedRatio => total == 0 ? 0 : learned / total;
}

FlashcardStats buildFlashcardStats({
  required List<Flashcard> cards,
  required List<FlashcardReview> reviews,
}) {
  if (cards.isEmpty && reviews.isEmpty) return FlashcardStats.empty;
  final now = DateTime.now();
  final active = cards.where((c) => !c.suspended).toList();
  final good = reviews.where((r) => r.rating > 0).length;

  final reviewDays = reviews
      .map((r) => DateTime(r.reviewedAt.year, r.reviewedAt.month, r.reviewedAt.day))
      .toSet();
  var streak = 0;
  var cursor = DateTime(now.year, now.month, now.day);
  if (!reviewDays.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  while (reviewDays.contains(cursor)) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final today = DateTime(now.year, now.month, now.day);

  return FlashcardStats(
    total: cards.length,
    due: active.where((c) => isDue(c.dueDate, now: now)).length,
    learned: cards
        .where((c) => isLearned(reviewCount: c.reviewCount, intervalDays: c.intervalDays))
        .length,
    suspended: cards.where((c) => c.suspended).length,
    newCards: cards.where((c) => c.reviewCount == 0).length,
    reviews: reviews.length,
    accuracy: reviews.isEmpty ? 0 : good / reviews.length,
    streakDays: streak,
    reviewedToday: reviews
        .where((r) => !DateTime(r.reviewedAt.year, r.reviewedAt.month, r.reviewedAt.day)
            .isBefore(today))
        .length,
    forecast: dueBuckets(active.map((c) => c.dueDate), now: now),
  );
}

/// Stats for a single deck (`deckId`), or for everything when empty.
final flashcardStatsProvider =
    Provider.family<FlashcardStats, String>((ref, deckId) {
  final cards = deckId.isEmpty
      ? (ref.watch(allFlashcardsStreamProvider).valueOrNull ?? const <Flashcard>[])
      : (ref.watch(deckCardsStreamProvider(deckId)).valueOrNull ??
          const <Flashcard>[]);
  final reviews =
      ref.watch(flashcardReviewsStreamProvider).valueOrNull ?? const <FlashcardReview>[];
  return buildFlashcardStats(
    cards: cards,
    reviews: deckId.isEmpty
        ? reviews
        : reviews.where((r) => r.deckId == deckId).toList(),
  );
});

class FlashcardRepository {
  FlashcardRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------- decks

  Stream<List<FlashcardDeck>> watchDecks() {
    return (_db.select(_db.flashcardDecks)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<FlashcardDeck?> watchDeck(String id) {
    return (_db.select(_db.flashcardDecks)..where((d) => d.id.equals(id)))
        .watchSingleOrNull();
  }

  Stream<List<FlashcardDeck>> watchDecksForCourse(String courseId) {
    return (_db.select(_db.flashcardDecks)
          ..where((d) => d.courseId.equals(courseId))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<FlashcardDeck?> getDeck(String id) {
    return (_db.select(_db.flashcardDecks)..where((d) => d.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<FlashcardDeck>> getDecks() => _db.select(_db.flashcardDecks).get();

  Future<String> createDeck({
    required String title,
    String? description,
    List<String> subject = const <String>[],
    String? courseId,
    int? color,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.flashcardDecks).insert(
          FlashcardDecksCompanion.insert(
            id: id,
            title: title,
            description: drift.Value(description),
            subject: drift.Value(tagsToCsv(subject)),
            courseId: drift.Value(courseId),
            color: drift.Value(color),
          ),
        );
    return id;
  }

  Future<void> updateDeck(
    String id, {
    required String title,
    String? description,
    List<String>? subject,
    String? courseId,
    int? color,
    bool? archived,
  }) async {
    await (_db.update(_db.flashcardDecks)..where((d) => d.id.equals(id))).write(
      FlashcardDecksCompanion(
        title: drift.Value(title),
        description: drift.Value(description),
        subject: subject != null
            ? drift.Value(tagsToCsv(subject))
            : const drift.Value.absent(),
        courseId: drift.Value(courseId),
        color: drift.Value(color),
        archived:
            archived != null ? drift.Value(archived) : const drift.Value.absent(),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    await (_db.update(_db.flashcardDecks)..where((d) => d.id.equals(id))).write(
      FlashcardDecksCompanion(
        archived: drift.Value(archived),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
  }

  /// Deletes the deck plus every card and review logged under it.
  Future<void> deleteDeck(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.flashcardReviews)..where((r) => r.deckId.equals(id))).go();
      await (_db.delete(_db.flashcards)..where((c) => c.deckId.equals(id))).go();
      await (_db.delete(_db.flashcardDecks)..where((d) => d.id.equals(id))).go();
    });
  }

  /// Distinct subject tags across all decks, for the filter bar.
  Stream<List<String>> watchSubjectsInUse() {
    return watchDecks().map((decks) => distinctTagsInUse(decks.map((d) => d.subject)));
  }

  // ---------------------------------------------------------------- cards

  Stream<List<Flashcard>> watchCards(String deckId) {
    return (_db.select(_db.flashcards)
          ..where((c) => c.deckId.equals(deckId))
          ..orderBy([(t) => drift.OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Stream<List<Flashcard>> watchAllCards() {
    return (_db.select(_db.flashcards)
          ..orderBy([(t) => drift.OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  Stream<List<Flashcard>> watchDueCards(String? deckId) {
    final query = _db.select(_db.flashcards)
      ..where((c) => c.suspended.equals(false))
      ..orderBy([(t) => drift.OrderingTerm.asc(t.dueDate)]);
    if (deckId != null) query.where((c) => c.deckId.equals(deckId));
    return query.watch().map(
          (cards) => cards.where((c) => isDue(c.dueDate)).toList(),
        );
  }

  Future<Flashcard?> getCard(String id) {
    return (_db.select(_db.flashcards)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addCard({
    required String deckId,
    required String front,
    required String back,
    String? hint,
    List<String> tags = const <String>[],
    String? sourceNoteId,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.flashcards).insert(
          FlashcardsCompanion.insert(
            id: id,
            deckId: deckId,
            front: front,
            back: back,
            hint: drift.Value(hint),
            tags: drift.Value(tagsToCsv(tags)),
            sourceNoteId: drift.Value(sourceNoteId),
          ),
        );
    return id;
  }

  /// Inserts many cards in one transaction (bulk add / send-to-flashcards).
  Future<int> bulkAddCards({
    required String deckId,
    required List<({String front, String back})> pairs,
    String? sourceNoteId,
  }) async {
    if (pairs.isEmpty) return 0;
    await _db.batch((batch) {
      batch.insertAll(
        _db.flashcards,
        pairs.map(
          (p) => FlashcardsCompanion.insert(
            id: const Uuid().v4(),
            deckId: deckId,
            front: p.front,
            back: p.back,
            sourceNoteId: drift.Value(sourceNoteId),
          ),
        ),
      );
    });
    return pairs.length;
  }

  Future<void> updateCard(
    String id, {
    required String front,
    required String back,
    String? hint,
    List<String>? tags,
    String? deckId,
  }) async {
    await (_db.update(_db.flashcards)..where((c) => c.id.equals(id))).write(
      FlashcardsCompanion(
        front: drift.Value(front),
        back: drift.Value(back),
        hint: drift.Value(hint),
        tags:
            tags != null ? drift.Value(tagsToCsv(tags)) : const drift.Value.absent(),
        deckId: deckId != null ? drift.Value(deckId) : const drift.Value.absent(),
      ),
    );
  }

  Future<void> setSuspended(String id, bool suspended) async {
    await (_db.update(_db.flashcards)..where((c) => c.id.equals(id)))
        .write(FlashcardsCompanion(suspended: drift.Value(suspended)));
  }

  Future<void> deleteCard(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.flashcardReviews)..where((r) => r.cardId.equals(id))).go();
      await (_db.delete(_db.flashcards)..where((c) => c.id.equals(id))).go();
    });
  }

  Future<int> countCardsFromNote(String noteId) async {
    final rows = await (_db.select(_db.flashcards)
          ..where((c) => c.sourceNoteId.equals(noteId)))
        .get();
    return rows.length;
  }

  // ----------------------------------------------------------- scheduling

  /// Applies [sm2Next] to [card] for the given [rating], persists the new
  /// schedule and logs a review row for the stats screens.
  Future<Flashcard> gradeCard(Flashcard card, int rating) async {
    final next = sm2Next(
      ease: card.easeFactor,
      intervalDays: card.intervalDays,
      reviewCount: card.reviewCount,
      rating: rating,
    );
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.flashcards)..where((c) => c.id.equals(card.id))).write(
        FlashcardsCompanion(
          easeFactor: drift.Value(next.ease),
          intervalDays: drift.Value(next.intervalDays),
          dueDate: drift.Value(next.due),
          reviewCount: drift.Value(card.reviewCount + 1),
          lapses: drift.Value(card.lapses + (rating == 0 ? 1 : 0)),
          lastReviewedAt: drift.Value(now),
        ),
      );
      await _db.into(_db.flashcardReviews).insert(
            FlashcardReviewsCompanion.insert(
              id: const Uuid().v4(),
              cardId: card.id,
              deckId: card.deckId,
              rating: rating,
              intervalDays: drift.Value(next.intervalDays),
              easeFactor: drift.Value(next.ease),
              reviewedAt: drift.Value(now),
            ),
          );
    });
    return (await getCard(card.id)) ?? card;
  }

  /// Restores a card to its pre-review state and drops the logged review —
  /// backs the "Undo" action on the study screen.
  Future<void> undoReview(Flashcard before, String? reviewId) async {
    await _db.transaction(() async {
      await (_db.update(_db.flashcards)..where((c) => c.id.equals(before.id))).write(
        FlashcardsCompanion(
          easeFactor: drift.Value(before.easeFactor),
          intervalDays: drift.Value(before.intervalDays),
          dueDate: drift.Value(before.dueDate),
          reviewCount: drift.Value(before.reviewCount),
          lapses: drift.Value(before.lapses),
          lastReviewedAt: drift.Value(before.lastReviewedAt),
        ),
      );
      if (reviewId != null) {
        await (_db.delete(_db.flashcardReviews)..where((r) => r.id.equals(reviewId)))
            .go();
      } else {
        // No id captured (older session): drop the most recent review row
        // for this card instead.
        final latest = await (_db.select(_db.flashcardReviews)
              ..where((r) => r.cardId.equals(before.id))
              ..orderBy([(r) => drift.OrderingTerm.desc(r.reviewedAt)])
              ..limit(1))
            .getSingleOrNull();
        if (latest != null) {
          await (_db.delete(_db.flashcardReviews)
                ..where((r) => r.id.equals(latest.id)))
              .go();
        }
      }
    });
  }

  /// Sends every card in the deck back to "new" and clears its review log.
  Future<void> resetDeckProgress(String deckId) async {
    await _db.transaction(() async {
      await (_db.update(_db.flashcards)..where((c) => c.deckId.equals(deckId))).write(
        FlashcardsCompanion(
          easeFactor: const drift.Value(2.5),
          intervalDays: const drift.Value(0),
          dueDate: drift.Value(DateTime.now()),
          reviewCount: const drift.Value(0),
          lapses: const drift.Value(0),
          lastReviewedAt: const drift.Value(null),
        ),
      );
      await (_db.delete(_db.flashcardReviews)..where((r) => r.deckId.equals(deckId)))
          .go();
    });
  }

  Stream<List<FlashcardReview>> watchReviews() {
    return (_db.select(_db.flashcardReviews)
          ..orderBy([(r) => drift.OrderingTerm.desc(r.reviewedAt)]))
        .watch();
  }
}
