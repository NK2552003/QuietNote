/// Naive note -> flashcard extraction used by "Send to flashcards" in the
/// note editor, plus the `front | back` bulk-add parser.
///
/// Deliberately simple: no NLP, no model calls. The student always reviews
/// and edits the suggested pairs before anything is written to the database.
library;

/// A candidate card produced by the extractors below.
class CardDraft {
  CardDraft({required this.front, required this.back, this.include = true});

  String front;
  String back;
  bool include;

  bool get isValid => front.trim().isNotEmpty && back.trim().isNotEmpty;
}

String _clean(String value) {
  return value
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
      .replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*|__|~~|`'), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .trim();
}

/// Splits raw note content into candidate front/back pairs.
///
/// Three shapes are recognised, in order of preference:
/// 1. `## Heading` sections — heading is the front, the body is the back.
/// 2. Explicit separators inside a paragraph: `Q: ... A: ...`, `term - def`,
///    `term: def` or `front | back`.
/// 3. Blank-line separated paragraphs — first line is the front, the rest
///    is the back.
List<CardDraft> extractCardsFromNote(String content) {
  final text = content.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return <CardDraft>[];

  final drafts = <CardDraft>[];
  final headingMatches =
      RegExp(r'^#{2,6}\s+(.+)$', multiLine: true).allMatches(text).toList();

  if (headingMatches.length >= 2) {
    for (var i = 0; i < headingMatches.length; i++) {
      final m = headingMatches[i];
      final front = _clean(m.group(1) ?? '');
      final bodyStart = m.end;
      final bodyEnd =
          i + 1 < headingMatches.length ? headingMatches[i + 1].start : text.length;
      final back = _clean(text.substring(bodyStart, bodyEnd));
      if (front.isNotEmpty && back.isNotEmpty) {
        drafts.add(CardDraft(front: front, back: back));
      }
    }
    if (drafts.isNotEmpty) return drafts;
  }

  for (final block in text.split(RegExp(r'\n\s*\n'))) {
    final cleaned = _clean(block);
    if (cleaned.isEmpty) continue;

    final qa = RegExp(
      r'^Q(?:uestion)?\s*[:.\-]\s*([\s\S]+?)\s*A(?:nswer)?\s*[:.\-]\s*([\s\S]+)$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (qa != null) {
      drafts.add(
        CardDraft(front: qa.group(1)!.trim(), back: qa.group(2)!.trim()),
      );
      continue;
    }

    final lines = cleaned.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length == 1) {
      final pair = splitInlinePair(lines.first);
      if (pair != null) {
        drafts.add(pair);
      }
      continue;
    }

    final front = lines.first.trim();
    final back = lines.skip(1).join('\n').trim();
    if (front.isNotEmpty && back.isNotEmpty) {
      drafts.add(CardDraft(front: front, back: back));
    }
  }

  return drafts;
}

/// Splits a single line on `|`, ` - ` or `:` into a front/back pair.
CardDraft? splitInlinePair(String line) {
  for (final separator in <RegExp>[
    RegExp(r'\s*\|\s*'),
    RegExp(r'\s+[–—-]\s+'),
    RegExp(r'\s*::\s*'),
    RegExp(r'\s*:\s+'),
  ]) {
    final parts = line.split(separator);
    if (parts.length >= 2) {
      final front = parts.first.trim();
      final back = parts.skip(1).join(' ').trim();
      if (front.isNotEmpty && back.isNotEmpty) {
        return CardDraft(front: front, back: back);
      }
    }
  }
  return null;
}

/// Parses the bulk-add textarea: one card per line as `front | back`
/// (`-`, `::` and `:` also work), blank lines ignored.
List<CardDraft> parseBulkCards(String input) {
  final drafts = <CardDraft>[];
  for (final line in input.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trim().isEmpty) continue;
    final pair = splitInlinePair(line.trim());
    if (pair != null) drafts.add(pair);
  }
  return drafts;
}
