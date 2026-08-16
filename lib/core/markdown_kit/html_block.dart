import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quietnote/core/markdown_kit/math_syntax.dart' show HighlightMarkBuilder;
import 'package:quietnote/core/markdown_kit/scrollable_table.dart';

/// ---------------------------------------------------------------------
/// Safe raw-HTML support for [RichMarkdownPreview].
///
/// Neither `flutter_markdown` nor the `markdown` package it sits on ever
/// build a widget-buildable element tree for raw HTML. Block-level HTML
/// (`HtmlBlockSyntax` in the `markdown` package) is captured as a single
/// un-parsed [md.Text] node. Inline HTML tags are matched by
/// `InlineHtmlSyntax`, but that class extends `TextSyntax` with no
/// substitute, so `onMatch` just advances the parser past the tag without
/// adding a node — the raw tag text is written out unchanged as plain
/// text on the next flush. Either way, there is no per-tag `md.Element`
/// for a builder to ever be handed. That's why raw HTML today either
/// shows up as literal angle-bracket text or silently vanishes, depending
/// on how it interacts with surrounding block parsing.
///
/// Rather than replacing `MarkdownBody`'s parser (or writing a general
/// HTML/DOM engine), this file adds one more "custom syntax + custom
/// builder" pair to markdown_kit — the exact same shape
/// [MathBlockSyntax]/[MathBlockBuilder] and
/// [HighlightMarkSyntax]/[HighlightMarkBuilder] already use for `$x$` and
/// `==mark==`:
///
///  1. [renderSafeHtml] runs once, before the document ever reaches
///     `MarkdownBody`. It walks the source line by line (skipping fenced
///     code blocks entirely, exactly like [normalizeHeadingBoundaries]
///     does), and for each well-formed run of *recognized* raw HTML tags
///     parses just that subset with a small dedicated stack-based
///     tokenizer into an [HtmlNode] tree, then replaces the run in the
///     source with a short private-use-area placeholder token. Anything
///     that isn't a recognized tag — including ordinary Markdown — is
///     left completely untouched.
///  2. [HtmlPlaceholderSyntax], an `md.InlineSyntax` shaped just like
///     [MathInlineSyntax], matches that placeholder token and turns it
///     into a single `html_node` [md.Element] carrying the id.
///  3. [HtmlInlineBuilder], a `MarkdownElementBuilder` registered under
///     `'html_node'` in the same `builders` map as `'mark'`/`'pre'`/etc,
///     looks the id back up in the registry [renderSafeHtml] populated
///     and renders the [HtmlNode] tree with plain Flutter widgets —
///     reusing [ScrollableTableBuilder] for `<table>` and
///     [HighlightMarkBuilder]'s styling for `<mark>`, rather than
///     reimplementing either.
///
/// Malformed/unclosed tags degrade gracefully (auto-closed, never
/// thrown), mirroring the defensive style already used in
/// `flowchart_parser.dart` — nothing here can crash the preview.
/// ---------------------------------------------------------------------

/// One node of the small tree [renderSafeHtml] builds for a single
/// recognized run of raw HTML.
sealed class HtmlNode {
  const HtmlNode();
}

class HtmlTextNode extends HtmlNode {
  const HtmlTextNode(this.text);
  final String text;
}

class HtmlElementNode extends HtmlNode {
  const HtmlElementNode(this.tag, this.attributes, this.children);
  final String tag;
  final Map<String, String> attributes;
  final List<HtmlNode> children;
}

/// Self-closing / no-children tags.
const Set<String> kHtmlVoidTags = <String>{'br', 'hr', 'img'};

/// "This is user-authored note content, not trusted input" — these are
/// stripped entirely, along with all of their content, rather than being
/// rendered as text or passed through.
const Set<String> kHtmlStrippedTags = <String>{
  'script', 'style', 'iframe', 'object', 'embed', 'form', 'input',
};

const Set<String> _inlineFormatTags = <String>{
  'b', 'strong', 'i', 'em', 'u', 's', 'del', 'mark', 'br', 'sub', 'sup', 'span', 'a',
};
const Set<String> _structuralTags = <String>{'div', 'p', 'blockquote', 'hr', 'ul', 'ol', 'li'};
const Set<String> _tableTags = <String>{'table', 'thead', 'tbody', 'tr', 'td', 'th'};

/// Every tag [renderSafeHtml] will actually render something for.
const Set<String> kHtmlAllowedTags = <String>{
  ..._inlineFormatTags,
  ..._structuralTags,
  ..._tableTags,
  'img',
};

const Set<String> _blockLevelTags = <String>{'div', 'p', 'blockquote', 'ul', 'ol', 'hr', 'table'};

final RegExp _fenceLine = RegExp(r'^ {0,3}(```+|~~~+)');
final RegExp _htmlTag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^<>]*?)?)\s*(/?)>');
final RegExp _attrPattern = RegExp(
  r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?''',
);

/// Private-use-area character used to bracket the numeric id embedded in
/// the placeholder text `renderSafeHtml` substitutes into the source —
/// vanishingly unlikely to collide with anything a person actually types,
/// and matched by [HtmlPlaceholderSyntax] via [_placeholderPattern].
const String _htmlPlaceholderMarker = '\uE000';
final RegExp _placeholderPattern = RegExp('$_htmlPlaceholderMarker(\\d+)$_htmlPlaceholderMarker');

class _IdGen {
  int _next = 0;
  String next() => (_next++).toString();
}

class _OpenFrame {
  _OpenFrame({required this.tag, required this.attributes, required this.stripped});
  final String tag;
  final Map<String, String> attributes;
  final bool stripped;
  final List<HtmlNode> children = <HtmlNode>[];
}

/// Scans [source] for recognized raw-HTML runs (skipping fenced code
/// blocks) and replaces each one with a short placeholder token, recording
/// the parsed [HtmlNode] tree for that run under a fresh id in
/// [registry]. A `<script>`/`<style>`/... run (see [kHtmlStrippedTags]) is
/// replaced with nothing at all, rather than a placeholder, since it
/// should render no widget. Everything else — ordinary Markdown, and any
/// HTML tag this app doesn't recognize — passes through unchanged.
String renderSafeHtml(String source, Map<String, HtmlNode> registry) {
  if (!source.contains('<')) return source;

  final List<String> lines = source.split('\n');
  final List<String> out = <String>[];
  final List<String> segment = <String>[];
  final _IdGen gen = _IdGen();
  bool inFence = false;

  void flushSegment() {
    if (segment.isEmpty) return;
    out.add(_transformHtmlSegment(segment.join('\n'), registry, gen));
    segment.clear();
  }

  for (final String line in lines) {
    if (_fenceLine.hasMatch(line)) {
      flushSegment();
      out.add(line);
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    segment.add(line);
  }
  flushSegment();
  return out.join('\n');
}

String _transformHtmlSegment(String text, Map<String, HtmlNode> registry, _IdGen gen) {
  if (!text.contains('<')) return text;

  final StringBuffer out = StringBuffer();
  final List<_OpenFrame> stack = <_OpenFrame>[];
  int cursor = 0; // Position up to which `out` has already captured text.
  int lastPos = 0; // Position up to which the tokenizer has consumed tokens.
  int? runStart;

  void attach(HtmlNode node) {
    if (stack.isEmpty) return;
    if (stack.last.stripped) return;
    stack.last.children.add(node);
  }

  void captureText(int start, int end) {
    if (end <= start || stack.isEmpty || stack.last.stripped) return;
    final String raw = text.substring(start, end);
    if (raw.isEmpty) return;
    stack.last.children.add(HtmlTextNode(_unescapeEntities(raw)));
  }

  void finishRun(HtmlNode? rootNode, int end) {
    if (rootNode != null) {
      final String id = gen.next();
      registry[id] = rootNode;
      out.write('$_htmlPlaceholderMarker$id$_htmlPlaceholderMarker');
    }
    cursor = end;
    runStart = null;
  }

  for (final RegExpMatch m in _htmlTag.allMatches(text)) {
    final bool isClose = m.group(1) == '/';
    final String tagName = m.group(2)!.toLowerCase();
    final bool recognized = kHtmlAllowedTags.contains(tagName) || kHtmlStrippedTags.contains(tagName);
    if (!recognized) continue; // Left as literal text, exactly as today.

    captureText(lastPos, m.start);
    lastPos = m.end;

    if (stack.isEmpty && isClose) {
      continue; // Stray closer with nothing open — leave as literal text.
    }
    if (stack.isEmpty && !isClose) {
      out.write(text.substring(cursor, m.start));
      runStart = m.start;
    }

    if (!isClose) {
      final Map<String, String> attrs = _parseAttrs(m.group(3) ?? '');
      final bool stripped = kHtmlStrippedTags.contains(tagName);
      final bool selfClosing = m.group(4) == '/' || kHtmlVoidTags.contains(tagName);
      if (selfClosing) {
        final HtmlNode? node = stripped ? null : HtmlElementNode(tagName, attrs, const <HtmlNode>[]);
        if (stack.isEmpty) {
          finishRun(node, m.end);
        } else if (node != null) {
          attach(node);
        }
      } else {
        stack.add(_OpenFrame(tag: tagName, attributes: attrs, stripped: stripped));
      }
      continue;
    }

    // Closing tag: find a matching open frame anywhere on the stack.
    int idx = -1;
    for (int i = stack.length - 1; i >= 0; i--) {
      if (stack[i].tag == tagName) {
        idx = i;
        break;
      }
    }
    if (idx == -1) continue; // No matching opener — ignore the stray closer.

    // Auto-close anything opened (and never closed) after the match.
    while (stack.length - 1 > idx) {
      final _OpenFrame popped = stack.removeLast();
      if (!popped.stripped) attach(HtmlElementNode(popped.tag, popped.attributes, popped.children));
    }
    final _OpenFrame closing = stack.removeLast();
    final HtmlNode? node =
        closing.stripped ? null : HtmlElementNode(closing.tag, closing.attributes, closing.children);
    if (stack.isEmpty) {
      finishRun(node, m.end);
    } else if (node != null) {
      attach(node);
    }
  }

  captureText(lastPos, text.length);
  if (stack.isNotEmpty) {
    // Unclosed markup at the end of the segment — degrade gracefully by
    // auto-closing everything still open instead of losing the run.
    while (stack.length > 1) {
      final _OpenFrame popped = stack.removeLast();
      if (!popped.stripped) attach(HtmlElementNode(popped.tag, popped.attributes, popped.children));
    }
    final _OpenFrame root = stack.removeLast();
    final HtmlNode? node = root.stripped ? null : HtmlElementNode(root.tag, root.attributes, root.children);
    finishRun(node, text.length);
  }

  out.write(text.substring(cursor));
  return out.toString();
}

Map<String, String> _parseAttrs(String raw) {
  final Map<String, String> attrs = <String, String>{};
  for (final RegExpMatch m in _attrPattern.allMatches(raw)) {
    final String? name = m.group(1)?.toLowerCase();
    if (name == null || name.isEmpty) continue;
    if (name.startsWith('on')) continue; // Strip event handlers.
    attrs[name] = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
  }
  return attrs;
}

String _unescapeEntities(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', '\u00A0')
    .replaceAll('&amp;', '&');

bool _isSafeUrl(String value) {
  final String normalized = value.replaceAll(RegExp(r'[\x00-\x20]'), '').toLowerCase();
  return !normalized.startsWith('javascript:') && !normalized.startsWith('data:text/html');
}

double? _parseLength(String? raw) {
  if (raw == null) return null;
  final String? digits = RegExp(r'[\d.]+').stringMatch(raw);
  return digits == null ? null : double.tryParse(digits);
}

/// Matches the placeholder token [renderSafeHtml] writes into the source
/// and turns it into a single `html_node` element — the same shape
/// [MathInlineSyntax]/[HighlightMarkSyntax] use for their own tokens.
class HtmlPlaceholderSyntax extends md.InlineSyntax {
  HtmlPlaceholderSyntax() : super(_placeholderPattern.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String id = match[1] ?? '';
    if (id.isEmpty) return false;
    parser.addNode(md.Element.text('html_node', id));
    return true;
  }
}

/// Renders the [HtmlNode] tree [renderSafeHtml] parsed out of the source,
/// looked up by the id carried on the `html_node` element's text content.
///
/// Deliberately does **not** override `isBlockElement()` — see
/// [MathBlockBuilder] for why: `html_node`, like `math_block`, is produced
/// by an *inline* syntax, so declaring it a block element would corrupt
/// flutter_markdown's inline-element stack bookkeeping and risk the
/// `_inlines.isEmpty` crash `inline_balance.dart` exists to prevent.
/// Instead this returns an ordinary widget, which flutter_markdown embeds
/// as a `WidgetSpan` — exactly how the (visually block-shaped) display-
/// math widget already renders inline today.
class HtmlInlineBuilder extends MarkdownElementBuilder {
  HtmlInlineBuilder({
    required this.registry,
    required this.styleSheet,
    required this.dark,
    required this.tableBuilder,
    required this.selectable,
    this.resolveImage,
  });

  final Map<String, HtmlNode> registry;
  final MarkdownStyleSheet styleSheet;
  final bool dark;
  final ScrollableTableBuilder tableBuilder;
  final bool selectable;
  final Widget Function(Uri uri)? resolveImage;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final HtmlNode? node = registry[element.textContent];
    if (node == null) return null;
    return _renderBlockNode(node, preferredStyle ?? styleSheet.p ?? const TextStyle());
  }

  Widget _renderBlockNode(HtmlNode node, TextStyle style) {
    if (node is HtmlTextNode) return _paragraph(<HtmlNode>[node], style);
    final HtmlElementNode el = node as HtmlElementNode;
    switch (el.tag) {
      case 'table':
      case 'thead':
      case 'tbody':
      case 'tr':
      case 'td':
      case 'th':
        final md.Element? table = _toMdTableElement(el);
        final Widget? widget = table == null ? null : tableBuilder.buildTable(table);
        return widget ?? const SizedBox.shrink();
      case 'blockquote':
        return Container(
          decoration: styleSheet.blockquoteDecoration,
          padding: styleSheet.blockquotePadding,
          child: _renderChildrenAsBlocks(el.children, style.merge(styleSheet.blockquote)),
        );
      case 'div':
      case 'p':
        return _renderChildrenAsBlocks(el.children, style);
      case 'hr':
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: styleSheet.horizontalRuleDecoration,
        );
      case 'ul':
      case 'ol':
        return _renderList(el, style);
      case 'li':
        return _renderList(HtmlElementNode('ul', const <String, String>{}, <HtmlNode>[el]), style);
      default:
        // An inline-formatting tag (b, i, span, a, mark, ...) sitting at
        // the outermost level of a run — render it as one paragraph.
        return _paragraph(<HtmlNode>[el], style);
    }
  }

  Widget _renderChildrenAsBlocks(List<HtmlNode> children, TextStyle style) {
    final List<Widget> widgets = <Widget>[];
    List<HtmlNode> pending = <HtmlNode>[];
    final double spacing = styleSheet.blockSpacing ?? 14;

    void flushPending() {
      if (pending.isEmpty) return;
      if (widgets.isNotEmpty) widgets.add(SizedBox(height: spacing));
      widgets.add(_paragraph(pending, style));
      pending = <HtmlNode>[];
    }

    for (final HtmlNode child in children) {
      final bool isBlock = child is HtmlElementNode && _blockLevelTags.contains(child.tag);
      if (isBlock) {
        flushPending();
        if (widgets.isNotEmpty) widgets.add(SizedBox(height: spacing));
        widgets.add(_renderBlockNode(child, style));
      } else {
        pending.add(child);
      }
    }
    flushPending();

    if (widgets.isEmpty) return const SizedBox.shrink();
    if (widgets.length == 1) return widgets.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _renderList(HtmlElementNode list, TextStyle style) {
    final bool ordered = list.tag == 'ol';
    final List<HtmlElementNode> items =
        list.children.whereType<HtmlElementNode>().where((HtmlElementNode c) => c.tag == 'li').toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final double indent = styleSheet.listIndent ?? 22;
    final TextStyle bulletStyle = styleSheet.listBullet ?? style;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: indent,
                  child: Text(ordered ? '${i + 1}.' : '\u2022', style: bulletStyle, textAlign: TextAlign.right),
                ),
                const SizedBox(width: 6),
                Expanded(child: _renderChildrenAsBlocks(items[i].children, style)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _paragraph(List<HtmlNode> nodes, TextStyle style) {
    final List<InlineSpan> spans = _inlineSpans(nodes, style);
    if (spans.isEmpty) return const SizedBox.shrink();
    final TextSpan span = TextSpan(children: spans, style: style);
    return selectable ? SelectableText.rich(span) : Text.rich(span);
  }

  List<InlineSpan> _inlineSpans(List<HtmlNode> nodes, TextStyle style) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final HtmlNode node in nodes) {
      if (node is HtmlTextNode) {
        if (node.text.isEmpty) continue;
        spans.add(TextSpan(text: node.text, style: style));
        continue;
      }
      final HtmlElementNode el = node as HtmlElementNode;
      switch (el.tag) {
        case 'b':
        case 'strong':
          spans.addAll(
            _inlineSpans(el.children, style.merge(styleSheet.strong).copyWith(fontWeight: FontWeight.w700)),
          );
          break;
        case 'i':
        case 'em':
          spans.addAll(
            _inlineSpans(el.children, style.merge(styleSheet.em).copyWith(fontStyle: FontStyle.italic)),
          );
          break;
        case 'u':
          spans.addAll(_inlineSpans(el.children, style.copyWith(decoration: TextDecoration.underline)));
          break;
        case 's':
        case 'del':
          spans.addAll(
            _inlineSpans(
              el.children,
              style.merge(styleSheet.del).copyWith(decoration: TextDecoration.lineThrough),
            ),
          );
          break;
        case 'mark':
          final Widget? highlighted = HighlightMarkBuilder(dark: dark)
              .visitElementAfter(md.Element.text('mark', _plainText(el)), style);
          spans.add(
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: highlighted ?? const SizedBox.shrink()),
          );
          break;
        case 'br':
          spans.add(const TextSpan(text: '\n'));
          break;
        case 'sub':
          spans.add(_scriptSpan(el, style, dy: 3));
          break;
        case 'sup':
          spans.add(_scriptSpan(el, style, dy: -6));
          break;
        case 'span':
          spans.addAll(_inlineSpans(el.children, style.merge(_spanStyle(el.attributes))));
          break;
        case 'a':
          spans.addAll(_inlineSpans(el.children, style.merge(styleSheet.a)));
          break;
        case 'img':
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _image(el)));
          break;
        default:
          // Block-level tag reached from inline context (e.g. a stray <p>
          // nested inside a <span>) — flatten to inline rather than drop.
          spans.addAll(_inlineSpans(el.children, style));
      }
    }
    return spans;
  }

  WidgetSpan _scriptSpan(HtmlElementNode el, TextStyle style, {required double dy}) {
    final TextStyle smaller = style.copyWith(fontSize: (style.fontSize ?? 14) * 0.7);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Text.rich(TextSpan(children: _inlineSpans(el.children, smaller))),
      ),
    );
  }

  String _plainText(HtmlNode node) {
    if (node is HtmlTextNode) return node.text;
    final HtmlElementNode el = node as HtmlElementNode;
    return el.children.map(_plainText).join();
  }

  TextStyle _spanStyle(Map<String, String> attributes) {
    final String css = attributes['style'] ?? '';
    Color? color;
    Color? background;
    for (final String decl in css.split(';')) {
      final int i = decl.indexOf(':');
      if (i == -1) continue;
      final String prop = decl.substring(0, i).trim().toLowerCase();
      final String value = decl.substring(i + 1).trim();
      if (prop == 'color') color = _parseCssColor(value);
      if (prop == 'background-color' || prop == 'background') background = _parseCssColor(value);
    }
    return TextStyle(color: color, backgroundColor: background);
  }

  Widget _image(HtmlElementNode el) {
    final String src = el.attributes['src'] ?? '';
    final String alt = el.attributes['alt'] ?? '';
    if (src.isEmpty || !_isSafeUrl(src)) return const SizedBox.shrink();

    final Uri? uri = Uri.tryParse(src);
    if (uri == null) return const SizedBox.shrink();

    final double? width = _parseLength(el.attributes['width']);
    final double? height = _parseLength(el.attributes['height']);

    Widget child;
    if (resolveImage != null) {
      child = resolveImage!(uri);
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      child = Image.network(src, width: width, height: height, semanticLabel: alt.isEmpty ? null : alt);
    } else {
      return Tooltip(
        message: alt.isEmpty ? 'Image unavailable' : alt,
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    if (width != null || height != null) {
      child = SizedBox(width: width, height: height, child: child);
    }
    return child;
  }
}

const Map<String, Color> _namedCssColors = <String, Color>{
  'red': Colors.red,
  'blue': Colors.blue,
  'green': Colors.green,
  'yellow': Colors.yellow,
  'orange': Colors.orange,
  'purple': Colors.purple,
  'black': Colors.black,
  'white': Colors.white,
  'gray': Colors.grey,
  'grey': Colors.grey,
  'pink': Colors.pink,
  'brown': Colors.brown,
  'cyan': Colors.cyan,
  'teal': Colors.teal,
  'indigo': Colors.indigo,
};

/// Parses only `color`/`background-color` out of an inline `style="..."`
/// attribute — hex (`#rgb`/`#rrggbb`/`#rrggbbaa`), `rgb()`/`rgba()`, and a
/// handful of common CSS color names. Anything else in the attribute
/// (and every other CSS property) is ignored.
Color? _parseCssColor(String value) {
  final String v = value.trim().toLowerCase();
  if (v.startsWith('#')) {
    String hex = v.substring(1);
    if (hex.length == 3) hex = hex.split('').map((String c) => '$c$c').join();
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final int? argb = int.tryParse(hex, radix: 16);
    return argb == null ? null : Color(argb);
  }
  final RegExpMatch? rgb =
      RegExp(r'^rgba?\(([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s]+([\d.]+))?\)$').firstMatch(v);
  if (rgb != null) {
    final int r = (int.tryParse(rgb.group(1) ?? '') ?? 0).clamp(0, 255).toInt();
    final int g = (int.tryParse(rgb.group(2) ?? '') ?? 0).clamp(0, 255).toInt();
    final int b = (int.tryParse(rgb.group(3) ?? '') ?? 0).clamp(0, 255).toInt();
    final double a = (double.tryParse(rgb.group(4) ?? '1') ?? 1).clamp(0, 1).toDouble();
    return Color.fromRGBO(r, g, b, a);
  }
  return _namedCssColors[v];
}

/// Converts an [HtmlElementNode] table (or a bare `<tr>`/`<td>` fragment)
/// into the `md.Element` shape [ScrollableTableBuilder.buildTable] already
/// knows how to render, so the actual table layout is never duplicated.
md.Element? _toMdTableElement(HtmlElementNode el) {
  final HtmlElementNode table =
      el.tag == 'table' ? el : HtmlElementNode('table', const <String, String>{}, <HtmlNode>[el]);
  final md.Node converted = _toMdNode(table);
  return converted is md.Element ? converted : null;
}

md.Node _toMdNode(HtmlNode node) {
  if (node is HtmlTextNode) return md.Text(node.text);
  final HtmlElementNode el = node as HtmlElementNode;
  final String tag = switch (el.tag) {
    'i' => 'em',
    'b' => 'strong',
    's' => 'del',
    _ => el.tag,
  };
  final List<md.Node> children = el.children.map(_toMdNode).toList();
  final md.Element built = md.Element(tag, children);
  if (tag == 'td' || tag == 'th') {
    final String raw = (el.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');
    if (raw.contains('text-align:center')) built.attributes['style'] = 'text-align: center;';
    if (raw.contains('text-align:right')) built.attributes['style'] = 'text-align: right;';
  }
  return built;
}
