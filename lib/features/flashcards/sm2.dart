/// SM-2 style spaced-repetition scheduling used by the flashcards feature.
///
/// Ratings are the four buttons shown on the study screen:
/// `0 = Again`, `1 = Hard`, `2 = Good`, `3 = Easy`.
library;

/// Human labels for the four ratings, indexed by rating value.
const List<String> kRatingLabels = <String>['Again', 'Hard', 'Good', 'Easy'];

/// Computes the next scheduling state for a card after it was rated.
///
/// A rating of 0 (`Again`) is a lapse: the ease factor drops and the card
/// comes back tomorrow. Anything else moves the card along the standard
/// 1 day -> 6 days -> `interval * ease` progression.
({double ease, int intervalDays, DateTime due}) sm2Next({
  required double ease,
  required int intervalDays,
  required int reviewCount,
  required int rating,
}) {
  if (rating == 0) {
    return (
      ease: (ease - 0.2).clamp(1.3, 2.5),
      intervalDays: 1,
      due: DateTime.now().add(const Duration(days: 1)),
    );
  }
  final newEase =
      (ease + (0.1 - (3 - rating) * (0.08 + (3 - rating) * 0.02))).clamp(
    1.3,
    5.0,
  );
  final newInterval = reviewCount == 0
      ? 1
      : reviewCount == 1
          ? 6
          : (intervalDays * newEase).round();
  return (
    ease: newEase,
    intervalDays: newInterval,
    due: DateTime.now().add(Duration(days: newInterval)),
  );
}

/// Whether a card scheduled for [dueDate] should appear in the study queue.
bool isDue(DateTime dueDate, {DateTime? now}) =>
    !dueDate.isAfter(now ?? DateTime.now());

/// The interval each rating button would produce, so the study screen can
/// label them ("Good · 6d") before the student commits to an answer.
List<int> previewIntervals({
  required double ease,
  required int intervalDays,
  required int reviewCount,
}) {
  return List<int>.generate(
    4,
    (rating) => sm2Next(
      ease: ease,
      intervalDays: intervalDays,
      reviewCount: reviewCount,
      rating: rating,
    ).intervalDays,
  );
}

/// Short human form of a day count, used on the rating buttons.
String formatIntervalDays(int days) {
  if (days <= 0) return 'now';
  if (days == 1) return '1d';
  if (days < 30) return '${days}d';
  if (days < 365) return '${(days / 30).round()}mo';
  final years = days / 365;
  return '${years.toStringAsFixed(years >= 10 ? 0 : 1)}y';
}

/// Buckets upcoming due counts per day for the next [days] days, starting
/// today. Index 0 is "due today or overdue".
List<int> dueBuckets(Iterable<DateTime> dueDates, {int days = 14, DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final buckets = List<int>.filled(days, 0);
  for (final due in dueDates) {
    final dueDay = DateTime(due.year, due.month, due.day);
    final offset = dueDay.difference(today).inDays;
    if (offset <= 0) {
      buckets[0] += 1;
    } else if (offset < days) {
      buckets[offset] += 1;
    }
  }
  return buckets;
}

/// A card counts as "learned" once it has survived a couple of reviews and
/// is scheduled far enough out that it's no longer being drilled daily.
bool isLearned({required int reviewCount, required int intervalDays}) =>
    reviewCount >= 2 && intervalDays >= 7;
