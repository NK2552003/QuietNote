import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/code_block.dart';
import 'package:quietnote/core/markdown_kit/inline_balance.dart';
import 'package:quietnote/core/markdown_kit/markdown_outline.dart';
import 'package:quietnote/core/markdown_kit/math_syntax.dart';

/// Renders Markdown with (near-)full GitHub-Flavored-Markdown support plus
/// the extras a note/journal app benefits from: LaTeX math (`$x$`,
/// `$$x$$`), `==highlighted==` text, syntax-highlighted fenced code blocks,
/// ```mermaid``` flowcharts/diagrams (tap for fullscreen pan+zoom +
/// download), and ```chart``` blocks. One shared widget backs every
/// preview surface in the app (editor's Preview tab, the read-only note/
/// journal screens) so they never drift out of sync with each other.
class RichMarkdownPreview extends StatelessWidget {
  const RichMarkdownPreview({
    super.key,
    required this.data,
    this.imageResolver,
    this.emptyPlaceholder = '*Nothing written yet. Switch to Edit and start typing — '
        'headings, checklists, tables, `code`, \$x^2\$ math, and ```mermaid``` '
        'flowcharts are all supported.*',
    this.selectable = true,
    this.shrinkWrap = true,
    this.outlineController,
  });

  /// Raw markdown source.
  final String data;

  /// Resolves image URIs (including the app's `local-image://` /
  /// `local-file://` schemes) to a displayable widget.
  final Widget Function(BuildContext context, Uri uri)? imageResolver;

  final String emptyPlaceholder;
  final bool selectable;
  final bool shrinkWrap;

  /// When provided, every `#`–`######` heading in [data] is tracked here so a
  /// caller can show a floating "jump to section" index — see
  /// [MarkdownOutlineFab].
  final MarkdownOutlineController? outlineController;

  @override
  Widget build(BuildContext context) {
    final bool dark = context.ui.brightness == Brightness.dark;
    final String raw = data.trim().isEmpty ? emptyPlaceholder : data;
    final String source = normalizeHeadingBoundaries(neutralizeDanglingCustomMarkers(raw));
    final MarkdownStyleSheet styleSheet = buildStyleSheet(context);

    final MarkdownOutlineController? outline = outlineController;
    if (outline == null) {
      return _body(context, source, styleSheet, dark);
    }

    // Headings are rendered by flutter_markdown's own h1–h6 path (never by a
    // custom element builder): taking over a block tag with a custom builder
    // hands that tag's whole layout — and flutter_markdown's internal block/
    // text-style bookkeeping for it — to us, which is what previously let a
    // heading's style bleed onto the paragraph that followed it. To still be
    // able to scroll to a heading, the document is split at its heading lines
    // and each section is rendered as its own `MarkdownBody` inside a keyed
    // wrapper. Same parser, same stylesheet, same visual result.
    final List<_MarkdownSection> sections = splitIntoSections(source);
    final List<MarkdownHeading> collected = <MarkdownHeading>[];
    final Set<String> liveCacheIds = <String>{};
    final Map<String, int> occurrences = <String, int>{};
    final double spacing = styleSheet.blockSpacing ?? 14;

    final List<Widget> children = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      final _MarkdownSection section = sections[i];
      Widget child = _body(context, section.markdown, styleSheet, dark);

      final String? title = section.title;
      if (title != null && section.level != null) {
        final int occurrence = occurrences[title] ?? 0;
        occurrences[title] = occurrence + 1;
        final String cacheId = '${section.level}::$title::$occurrence';
        liveCacheIds.add(cacheId);
        final GlobalKey key = outline.keyFor(cacheId);
        collected.add(
          MarkdownHeading(level: section.level!, text: title, key: key),
        );
        child = KeyedSubtree(key: key, child: child);
      }

      if (i > 0) children.add(SizedBox(height: spacing));
      children.add(child);
    }

    // The sections above only report their headings once this widget's own
    // build has produced a live element tree, so committing from a post-frame
    // callback guarantees every GlobalKey is attached to a mounted widget
    // before anything tries to scroll to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      outline.commit(collected, liveCacheIds);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _body(
    BuildContext context,
    String source,
    MarkdownStyleSheet styleSheet,
    bool dark,
  ) {
    return MarkdownBody(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      shrinkWrap: shrinkWrap,
      selectable: selectable,
      data: _ensureTrailingInlineContent(source),
      inlineSyntaxes: <md.InlineSyntax>[
        MathBlockSyntax(),
        MathInlineSyntax(),
        HighlightMarkSyntax(),
      ],
      builders: <String, MarkdownElementBuilder>{
        'pre': RichCodeBlockBuilder(dark: dark),
        'math_inline': MathInlineBuilder(),
        'math_block': MathBlockBuilder(),
        'mark': HighlightMarkBuilder(dark: dark),
      },
      sizedImageBuilder: imageResolver == null
          ? null
          : (MarkdownImageConfig config) => imageResolver!(context, config.uri),
      styleSheet: styleSheet,
    );
  }

  static MarkdownStyleSheet buildStyleSheet(BuildContext context) {
    final colors = context.uiColors;
    final text = context.uiText;
    return MarkdownStyleSheet(
      p: text.body,
      h1: text.heading.copyWith(fontSize: 27, fontWeight: FontWeight.w800, height: 1.35),
      h2: text.heading.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.35),
      h3: text.subheading.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      h4: text.subheading.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h5: text.bodyStrong,
      h6: text.bodyStrong.copyWith(color: colors.foregroundMuted),
      em: text.body.copyWith(fontStyle: FontStyle.italic),
      strong: text.body.copyWith(fontWeight: FontWeight.w700),
      del: text.body.copyWith(
        decoration: TextDecoration.lineThrough,
        color: colors.foregroundMuted,
      ),
      blockquote: text.body.copyWith(
        color: colors.foregroundMuted,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: colors.border, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      code: text.numeric.copyWith(
        backgroundColor: colors.surfaceMuted,
        fontSize: (text.numeric.fontSize ?? 13) * 0.95,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      listBullet: text.body,
      listIndent: 22,
      checkbox: text.body.copyWith(color: colors.primary),
      tableHead: text.bodyStrong,
      tableBody: text.body,
      tableBorder: TableBorder.all(color: colors.border, width: 1),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // flutter_markdown adds horizontal scrolling for fixed-width columns.
      // Flex columns instead force every table into the viewport, squeezing
      // wide tables until their contents become unreadable.
      tableColumnWidth: const FixedColumnWidth(160),
      a: text.body.copyWith(color: colors.primary, decoration: TextDecoration.underline),
      img: text.body,
      blockSpacing: 14,
    );
  }
}

/// One slice of a document: an ATX heading line plus everything under it
/// until the next heading (or, for the very first slice, any preamble that
/// appears before the first heading — [level] and [title] are null there).
class _MarkdownSection {
  const _MarkdownSection({required this.markdown, this.level, this.title});

  final String markdown;
  final int? level;
  final String? title;
}

/// CommonMark ATX heading: up to 3 leading spaces, 1–6 `#`, then a space/tab
/// or end of line. `#hashtag` (no space) deliberately does NOT match, so
/// inline hashtags typed in note content are never treated as headings.
final RegExp _atxHeading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*))?$');
final RegExp _fence = RegExp(r'^ {0,3}(```+|~~~+)');

/// Splits [source] at top-level ATX heading lines. Lines inside fenced code
/// blocks are never treated as headings.
List<_MarkdownSection> splitIntoSections(String source) {
  final List<String> lines = source.split('\n');
  final List<_MarkdownSection> sections = <_MarkdownSection>[];
  List<String> buffer = <String>[];
  int? level;
  String? title;
  bool inFence = false;

  void flush() {
    final String text = buffer.join('\n');
    if (text.trim().isEmpty && level == null) return;
    sections.add(_MarkdownSection(markdown: text, level: level, title: title));
  }

  for (final String line in lines) {
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      buffer.add(line);
      continue;
    }

    final RegExpMatch? match = inFence ? null : _atxHeading.firstMatch(line);
    if (match != null) {
      flush();
      buffer = <String>[line];
      level = (match.group(1) ?? '#').length;
      title = _plainHeadingText(match.group(2) ?? '');
      if (title.isEmpty) {
        level = null;
        title = null;
      }
      continue;
    }
    buffer.add(line);
  }
  flush();

  if (sections.isEmpty) {
    sections.add(_MarkdownSection(markdown: source));
  }
  return sections;
}

/// Strips the closing `###` of a closed ATX heading and the most common
/// inline markers, so the outline sheet shows readable labels.
String _plainHeadingText(String raw) {
  String text = raw.replaceFirst(RegExp(r'\s+#+\s*$'), '').trim();
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (Match m) => m.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r'[*_`~]'), '');
  text = text.replaceAll('==', '');
  return text.trim();
}

/// Guards against `'package:flutter_markdown/src/builder.dart': Failed
/// assertion: '_inlines.isEmpty': is not true` — a long-standing crash in
/// flutter_markdown's widget builder that a handful of other apps have hit
/// with their own custom inline syntaxes. Unlike `*`, `_` and `` ` ``,
/// which the underlying `markdown` package's CommonMark-compliant delimiter
/// algorithm already resolves safely when unmatched, [MathBlockSyntax],
/// [MathInlineSyntax] and [HighlightMarkSyntax] each fire off a single raw
/// regex match with no such bookkeeping. A stray, uncleaned `$` (a price:
/// "cost $20"), `==` (a comparison typed outside a code fence: "if (a ==
/// b)"), or `$$` left with nothing to pair with can leave the parser's
/// internal span stack unbalanced, and that is what flutter_markdown's
/// builder then trips on.
///
/// This runs before the document ever reaches the parser and, per
/// paragraph (never inside a fenced code block, and never touching
/// characters already escaped with `\`), counts each of those three
/// markers; if a marker has an odd number of occurrences — meaning the
/// last one has no partner to close it — a `\` is inserted right before
/// that last occurrence so it renders as a literal character instead of
/// being treated as an opener.
String neutralizeDanglingCustomMarkers(String source) {
  final List<String> lines = source.split('\n');
  final List<String> out = <String>[];
  final List<String> buffer = <String>[];
  bool inFence = false;

  void flush() {
    if (buffer.isEmpty) return;
    out.add(_balanceCustomMarkers(buffer.join('\n')));
    buffer.clear();
  }

  for (final String line in lines) {
    if (_fence.hasMatch(line)) {
      flush();
      out.add(line);
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    buffer.add(line);
  }
  flush();
  return out.join('\n');
}

String _balanceCustomMarkers(String chunk) {
  String text = chunk;
  // `$$` first, mirroring MathBlockSyntax being registered ahead of
  // MathInlineSyntax, so a balanced `$$formula$$` block is settled before
  // the single-`$` pass ever looks at it.
  text = _neutralizeToken(text, r'$$');
  text = _neutralizeToken(text, '==');
  text = _neutralizeSingleDollar(text);
  return text;
}

/// Pairs up consecutive, non-overlapping, unescaped occurrences of [token]
/// (open, close, open, close, ...). If one is left over with nothing to
/// pair with, a `\` is inserted right before it.
String _neutralizeToken(String text, String token) {
  final int len = token.length;
  final List<int> positions = <int>[];
  int i = 0;
  while (i <= text.length - len) {
    if (text.startsWith(token, i) && (i == 0 || text[i - 1] != '\\')) {
      positions.add(i);
      i += len;
    } else {
      i++;
    }
  }
  if (positions.length.isEven) return text;
  final int last = positions.last;
  return '${text.substring(0, last)}\\${text.substring(last)}';
}

/// Same idea as [_neutralizeToken] for a single `$`, but skips straight
/// over any `$$` pair (already settled by the earlier pass) so a balanced
/// math block is never miscounted as two dangling single dollars.
String _neutralizeSingleDollar(String text) {
  final List<int> positions = <int>[];
  int i = 0;
  while (i < text.length) {
    if (text[i] == r'$' && (i == 0 || text[i - 1] != '\\')) {
      if (i + 1 < text.length && text[i + 1] == r'$') {
        i += 2; // opening half of a `$$` token — already handled
        continue;
      }
      if (i > 0 && text[i - 1] == r'$') {
        i += 1; // closing half of a `$$` token — already handled
        continue;
      }
      positions.add(i);
    }
    i += 1;
  }
  if (positions.length.isEven) return text;
  final int last = positions.last;
  return '${text.substring(0, last)}\\${text.substring(last)}';
}

/// flutter_markdown's builder trips `Failed assertion: '_inlines.isEmpty'`
/// whenever a document (or, here, one of [splitIntoSections]'s per-heading
/// slices) ends while a parent inline element that never received a single
/// child widget is still on its internal stack — see
/// [markdownLeaksInlineStack] for the mechanism. A trailing fenced code
/// block is the most common producer, but it is far from the only one: an
/// indented (4-space) code block, an unterminated fence, a trailing table,
/// or an image-only last paragraph all leave the same dangling entry, and
/// a fence-shaped last line is neither necessary nor sufficient to detect
/// it.
///
/// So instead of guessing from the text, the document is parsed once with
/// the exact same parser configuration the preview uses and the builder's
/// stack bookkeeping is replayed over the resulting AST. Only when that
/// replay predicts a leak is an invisible zero-width-space paragraph
/// appended — enough of an ordinary trailing inline span for
/// flutter_markdown to close out its stack cleanly, with nothing visible
/// to the reader and no stray gap added to documents that don't need it.
String _ensureTrailingInlineContent(String source) {
  if (source.trim().isEmpty) return source;
  if (markdownLeaksInlineStack(source)) {
    return '${source.trimRight()}\n\n\u200B';
  }
  return source;
}


/// Two independent defenses against a heading silently absorbing text it
/// shouldn't, both applied as a single line-by-line pass before the
/// document ever reaches the markdown parser. Content inside fenced code
/// blocks is left completely untouched by either.
///
/// 1. **Accidental Setext headings.** A line of only `-` (or `=`)
///    characters directly under a line of text — with **no blank line
///    between them** — is CommonMark's Setext heading syntax: it silently
///    turns the line above into a heading and swallows the `-`/`=` line
///    instead of showing it. This app never intentionally writes Setext
///    headings (the toolbar only ever inserts ATX `# ` headings), but
///    people naturally type a `---` divider right after a paragraph.
///
/// 2. **Headings merging with adjacent text.** An ATX heading renders as a
///    cleanly isolated block when it has a blank line on *both* sides.
///    Forcing that removes any lazy-continuation ambiguity.
///
/// Both fixes only ever *insert* blank lines into the source that's handed
/// to the parser (never delete or reorder anything a person wrote), and a
/// blank line between blocks doesn't introduce any visible extra spacing of
/// its own — on-screen gaps come entirely from
/// [MarkdownStyleSheet.blockSpacing].
String normalizeHeadingBoundaries(String source) {
  final List<String> lines = source.split('\n');
  final RegExp setextUnderline = RegExp(r'^ {0,3}([-=])\1*[ \t]*$');
  final RegExp atxHeadingLine = RegExp(r'^ {0,3}#{1,6}(?:[ \t]|$)');
  bool inFence = false;
  final List<String> out = <String>[];

  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];

    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }

    final bool precedingLineNeedsGap = out.isNotEmpty && out.last.trim().isNotEmpty;

    if (setextUnderline.hasMatch(line) && precedingLineNeedsGap) {
      out.add('');
    } else if (atxHeadingLine.hasMatch(line) && precedingLineNeedsGap) {
      out.add('');
    }

    out.add(line);

    if (atxHeadingLine.hasMatch(line)) {
      final String? next = i + 1 < lines.length ? lines[i + 1] : null;
      if (next != null && next.trim().isNotEmpty) {
        out.add('');
      }
    }
  }
  return out.join('\n');
}
