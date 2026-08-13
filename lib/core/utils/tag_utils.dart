/// Small shared helpers for the comma-separated `tags` columns on [Notes]
/// and [Journal] (see `lib/core/database/database.dart`). Kept CSV rather
/// than a join table to match the existing convention used by `imagePaths`
/// and `daysOfWeek` elsewhere in this schema.
library;

/// Parses a stored CSV tag string into a clean, order-preserving list with
/// empty/whitespace-only entries dropped.
List<String> parseTagsCsv(String? csv) {
  if (csv == null || csv.trim().isEmpty) return const [];
  return csv
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

/// Serializes a tag list back to the stored CSV form. Returns `null` for an
/// empty list so the column can go back to unset rather than storing `''`.
String? tagsToCsv(List<String> tags) {
  final cleaned = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  return cleaned.isEmpty ? null : cleaned.join(',');
}

/// Collects the distinct set of tags in use across a list of items,
/// preserving first-seen order (used to build filter bars).
List<String> distinctTagsInUse(Iterable<String?> tagColumns) {
  final seen = <String>{};
  final ordered = <String>[];
  for (final csv in tagColumns) {
    for (final tag in parseTagsCsv(csv)) {
      if (seen.add(tag)) ordered.add(tag);
    }
  }
  return ordered;
}
