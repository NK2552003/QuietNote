import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/code_block.dart';
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
  });

  /// Raw markdown source.
  final String data;

  /// Resolves image URIs (including the app's `local-image://` /
  /// `local-file://` schemes) to a displayable widget.
  final Widget Function(BuildContext context, Uri uri)? imageResolver;

  final String emptyPlaceholder;
  final bool selectable;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final bool dark = context.ui.brightness == Brightness.dark;
    final String source = data.trim().isEmpty ? emptyPlaceholder : data;

    return MarkdownBody(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      shrinkWrap: shrinkWrap,
      selectable: selectable,
      data: source,
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
      styleSheet: buildStyleSheet(context),
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
      tableColumnWidth: const FlexColumnWidth(),
      a: text.body.copyWith(color: colors.primary, decoration: TextDecoration.underline),
      img: text.body,
      blockSpacing: 14,
    );
  }
}
