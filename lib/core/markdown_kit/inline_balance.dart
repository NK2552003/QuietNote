import 'dart:convert';

import 'package:markdown/markdown.dart' as md;
import 'package:quietnote/core/markdown_kit/math_syntax.dart';

/// Mirrors `flutter_markdown`'s internal block/inline bookkeeping closely
/// enough to predict, *before* any widget is built, whether rendering a
/// given document would trip
/// `'package:flutter_markdown/src/builder.dart': Failed assertion:
/// '_inlines.isEmpty': is not true`.
///
/// Root cause of that crash (flutter_markdown 0.7.x, `builder.dart`):
/// `_addAnonymousBlockIfNeeded()` only calls `_inlines.clear()` **inside**
/// `if (inline.children.isNotEmpty)`. So whenever a block pushes a parent
/// inline element that never receives a single child widget, that inline
/// is left on the stack forever. The classic producer is a fenced/indented
/// code block: `pre` has a custom builder in this app, so
/// `MarkdownBuilder.visitText` delegates to
/// `MarkdownElementBuilder.visitText`, whose default returns `null` — the
/// `pre` parent inline therefore ends with zero children and leaks.
///
/// The leak is invisible as long as *some* later block contributes inline
/// text: the next `visitText` reuses the stale entry and the following
/// flush clears it. It only becomes a crash when the leak is still open at
/// the end of the document — i.e. when the last content-bearing block
/// produced no inline text (a document, or an outline section, that ends
/// with a code block, a table, an image-only paragraph, an unterminated
/// fence, ...).
///
/// When [markdownLeaksInlineStack] returns true, appending a tiny
/// zero-width-space paragraph gives the builder one ordinary trailing
/// inline span to close out on. Any unexpected failure here answers
/// `true`: the flush paragraph is invisible, so over-applying it is always
/// safer than missing a crash.
bool markdownLeaksInlineStack(String source, {Set<String> blockBuilderTags = const <String>{'pre'}, Set<String> builderTags = const <String>{'pre', 'math_inline', 'math_block', 'mark'}}) {
  try {
    final md.Document document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: <md.InlineSyntax>[
        MathBlockSyntax(),
        MathInlineSyntax(),
        HighlightMarkSyntax(),
      ],
      encodeHtml: false,
    );
    final List<md.Node> nodes =
        document.parseLines(const LineSplitter().convert(source));
    final _InlineStackProbe probe = _InlineStackProbe(
      blockTags: <String>{..._kBlockTags, ...blockBuilderTags},
      builderTags: builderTags,
    );
    return probe.leaks(nodes);
  } catch (_) {
    return true;
  }
}

const Set<String> _kBlockTags = <String>{
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre',
  'ol', 'ul', 'hr', 'table', 'thead', 'tbody', 'tr', 'section',
};

class _Inline {
  int children = 0;
}

class _InlineStackProbe {
  _InlineStackProbe({required this.blockTags, required this.builderTags});

  final Set<String> blockTags;
  final Set<String> builderTags;

  final List<String?> _blocks = <String?>[null];
  final List<_Inline> _inlines = <_Inline>[];

  bool leaks(List<md.Node> nodes) {
    for (final md.Node node in nodes) {
      _visit(node);
    }
    return _inlines.isNotEmpty;
  }

  void _visit(md.Node node) {
    if (node is md.Text) {
      _text();
      return;
    }
    if (node is! md.Element) return;
    if (!_before(node)) return;
    for (final md.Node child in node.children ?? const <md.Node>[]) {
      _visit(child);
    }
    _after(node);
  }

  void _text() {
    if (_blocks.last == null) return;
    _parentInlineIfNeeded();
    // flutter_markdown hands text inside a custom-built block to that
    // builder's `visitText`, which returns null by default -> no child.
    final String? blockTag = _blocks.last;
    if (blockTag != null && builderTags.contains(blockTag)) return;
    _inlines.last.children += 1;
  }

  bool _before(md.Element element) {
    final String tag = element.tag;
    if (tag == 'a' && (element.children?.isEmpty ?? true)) return false;

    if (blockTags.contains(tag)) {
      _flushAnonymousBlock();
      _blocks.add(tag);
    } else {
      _parentInlineIfNeeded();
      _inlines.add(_Inline());
    }
    return true;
  }

  void _after(md.Element element) {
    final String tag = element.tag;
    if (blockTags.contains(tag)) {
      _flushAnonymousBlock();
      if (_blocks.length > 1) _blocks.removeLast();
      return;
    }

    if (_inlines.isEmpty) return;
    final _Inline current = _inlines.removeLast();
    if (_inlines.isEmpty) return;
    final _Inline parent = _inlines.last;
    if (builderTags.contains(tag) || tag == 'img' || tag == 'br') {
      if (current.children == 0) current.children = 1;
    }
    parent.children += current.children;
  }

  void _parentInlineIfNeeded() {
    if (_inlines.isEmpty) _inlines.add(_Inline());
  }

  void _flushAnonymousBlock() {
    if (_inlines.isEmpty) return;
    if (_inlines.length > 1) {
      // flutter_markdown would throw on `_inlines.single` here; treat any
      // such shape as unsafe.
      _inlines
        ..clear()
        ..add(_Inline());
      return;
    }
    if (_inlines.single.children > 0) _inlines.clear();
  }
}
