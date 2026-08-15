import 'flowchart_model.dart';

/// Parses a subset of Mermaid's `graph` / `flowchart` syntax into a
/// [FlowGraph] the app can lay out and paint itself.
///
/// This intentionally does not try to be a full Mermaid grammar — it covers
/// what people actually write in notes: a direction header, node shapes
/// (`[]`, `()`, `(())`, `{}`, `([])`, `[[]]`, `{{}}`, `>]`), plain/dashed/
/// thick edges with optional labels (either `-->|text|` or `-- text -->`),
/// chained edges on one line (`A --> B --> C`), `subgraph`/`end` blocks
/// (the grouping box isn't drawn, but every node and edge inside one still
/// is — dropping the whole block used to be why some diagrams rendered
/// empty), and `%%` comments.
///
/// Anything a line doesn't recognise is skipped rather than aborting the
/// whole parse, so one odd line degrades gracefully instead of leaving the
/// entire diagram blank.
class FlowchartParser {
  static FlowGraph parse(String source) {
    final Map<String, FlowNode> nodes = <String, FlowNode>{};
    final List<FlowEdge> edges = <FlowEdge>[];
    FlowDirection direction = FlowDirection.topToBottom;

    final List<String> lines = source.split('\n');
    bool sawHeader = false;

    for (final String rawLine in lines) {
      String line = _stripComment(rawLine).trim();
      if (line.isEmpty) continue;
      if (line.endsWith(';')) line = line.substring(0, line.length - 1).trim();

      if (!sawHeader) {
        final FlowDirection? parsed = _headerDirection(line);
        if (parsed != null) {
          direction = parsed;
          sawHeader = true;
          continue;
        }
        // A header is optional in Mermaid — if the very first non-empty
        // line is already a node/edge definition, treat direction as
        // top-to-bottom (Mermaid's own default) and fall through to parse
        // this line as content.
        sawHeader = true;
      }

      final String lower = line.toLowerCase();
      if (lower == 'end') continue;
      if (lower.startsWith('subgraph')) continue;
      if (lower.startsWith('classdef') ||
          lower.startsWith('class ') ||
          lower.startsWith('style ') ||
          lower.startsWith('click ') ||
          lower.startsWith('linkstyle')) {
        continue;
      }

      _parseLine(line, nodes, edges);
    }

    return FlowGraph(direction: direction, nodes: nodes, edges: edges);
  }

  static String _stripComment(String line) {
    final int i = line.indexOf('%%');
    return i == -1 ? line : line.substring(0, i);
  }

  static FlowDirection? _headerDirection(String line) {
    final RegExpMatch? m =
        RegExp(r'^(graph|flowchart)\s+(TB|TD|BT|LR|RL)\b', caseSensitive: false)
            .firstMatch(line);
    if (m == null) {
      // A bare `graph` / `flowchart` with no direction still counts as the
      // header line (defaults to top-to-bottom) so it isn't parsed as a node.
      if (RegExp(r'^(graph|flowchart)\b', caseSensitive: false).hasMatch(line)) {
        return FlowDirection.topToBottom;
      }
      return null;
    }
    switch (m.group(2)!.toUpperCase()) {
      case 'BT':
        return FlowDirection.bottomToTop;
      case 'LR':
        return FlowDirection.leftToRight;
      case 'RL':
        return FlowDirection.rightToLeft;
      default:
        return FlowDirection.topToBottom;
    }
  }

  /// Connector patterns, most-specific-first so e.g. a dashed arrow with an
  /// inline label is never mistaken for a plain dash. Each captures the
  /// inline label (if the pattern supports one) in group 1.
  static final List<_EdgePattern> _edgePatterns = <_EdgePattern>[
    _EdgePattern(RegExp(r'-\.\s*(.*?)\s*\.->'), FlowEdgeStyle.dashed, true),
    _EdgePattern(RegExp(r'==\s*(.+?)\s*==>'), FlowEdgeStyle.thick, true),
    _EdgePattern(RegExp(r'--\s*(.+?)\s*-->'), FlowEdgeStyle.solid, true),
    _EdgePattern(RegExp(r'-\.->'), FlowEdgeStyle.dashed, false, arrow: true),
    _EdgePattern(RegExp(r'==>'), FlowEdgeStyle.thick, false, arrow: true),
    _EdgePattern(RegExp(r'-->'), FlowEdgeStyle.solid, false, arrow: true),
    _EdgePattern(RegExp(r'-\.-'), FlowEdgeStyle.dashed, false, arrow: false),
    _EdgePattern(RegExp(r'==='), FlowEdgeStyle.thick, false, arrow: false),
    _EdgePattern(RegExp(r'---'), FlowEdgeStyle.solid, false, arrow: false),
  ];

  static void _parseLine(
    String line,
    Map<String, FlowNode> nodes,
    List<FlowEdge> edges,
  ) {
    String remaining = line;
    FlowNode? previous;
    bool madeAnEdge = false;

    while (true) {
      final _EdgeMatch? match = _findEarliestEdge(remaining);
      if (match == null) break;

      final String leftText = remaining.substring(0, match.start).trim();
      final _NodeToken? leftToken =
          previous == null ? _parseNodeToken(leftText) : null;
      final FlowNode fromNode = previous ?? _register(nodes, leftToken, leftText);

      String rest = remaining.substring(match.end);
      String? label = match.inlineLabel;
      // A label can also come as `-->|text|` right after the arrow.
      final RegExpMatch? pipe = RegExp(r'^\s*\|([^|]*)\|').firstMatch(rest);
      if (pipe != null) {
        label = pipe.group(1)?.trim();
        rest = rest.substring(pipe.end);
      }

      final _NodeToken? rightToken = _parseNodeToken(rest.trimLeft());
      if (rightToken == null) break; // malformed tail — stop, keep what we have
      final int leadingWs = rest.length - rest.trimLeft().length;
      final FlowNode toNode =
          _register(nodes, rightToken, rightToken.raw);

      edges.add(
        FlowEdge(
          fromId: fromNode.id,
          toId: toNode.id,
          label: (label != null && label.isNotEmpty) ? label : null,
          style: match.style,
          arrowEnd: match.arrow,
        ),
      );
      madeAnEdge = true;

      previous = toNode;
      remaining = rest.substring(leadingWs + rightToken.consumed);
      if (remaining.trim().isEmpty) break;
    }

    if (!madeAnEdge) {
      // Not an edge line — either a standalone node declaration
      // (`A[Do the thing]`) or an unrecognised line, which is skipped.
      final _NodeToken? token = _parseNodeToken(remaining.trim());
      if (token != null) _register(nodes, token, remaining.trim());
    }
  }

  static FlowNode _register(
    Map<String, FlowNode> nodes,
    _NodeToken? token,
    String fallbackText,
  ) {
    final String id = token?.id ?? fallbackText.trim();
    final FlowNode? existing = nodes[id];
    if (existing != null) {
      // A later, more descriptive definition of an already-referenced id
      // (declared bare earlier, e.g. `A --> B`, then `B[Real label]`
      // further down) should win.
      if (token != null && token.hasExplicitShape) {
        existing.label = token.label;
        existing.shape = token.shape;
      }
      return existing;
    }
    final FlowNode node = FlowNode(
      id: id,
      label: token?.label ?? id,
      shape: token?.shape ?? FlowNodeShape.rect,
    );
    nodes[id] = node;
    return node;
  }

  static _EdgeMatch? _findEarliestEdge(String text) {
    _EdgeMatch? best;
    for (final _EdgePattern pattern in _edgePatterns) {
      final RegExpMatch? m = pattern.regex.firstMatch(text);
      if (m == null) continue;
      if (best != null && m.start >= best.start) continue;
      best = _EdgeMatch(
        start: m.start,
        end: m.end,
        style: pattern.style,
        arrow: pattern.arrow,
        inlineLabel: pattern.hasLabel ? m.group(1)?.trim() : null,
      );
    }
    return best;
  }

  /// Ordered longest-delimiter-first so `((..))` isn't mistaken for `(..)`.
  static final List<_NodePattern> _nodePatterns = <_NodePattern>[
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\(\(([^)]*)\)\)'), FlowNodeShape.circle),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\(\[([^\]]*)\]\)'), FlowNodeShape.stadium),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\[\(([^)]*)\)\]'), FlowNodeShape.cylinder),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\[\[([^\]]*)\]\]'), FlowNodeShape.subroutine),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\{\{([^}]*)\}\}'), FlowNodeShape.hexagon),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\{([^}]*)\}'), FlowNodeShape.diamond),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\(([^)]*)\)'), FlowNodeShape.rounded),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)\[([^\]]*)\]'), FlowNodeShape.rect),
    _NodePattern(RegExp(r'^([A-Za-z0-9_\-]+)>([^\]]*)\]'), FlowNodeShape.flag),
  ];

  static _NodeToken? _parseNodeToken(String text) {
    if (text.isEmpty) return null;
    for (final _NodePattern pattern in _nodePatterns) {
      final RegExpMatch? m = pattern.regex.firstMatch(text);
      if (m == null) continue;
      final String id = m.group(1)!;
      final String label = (m.group(2) ?? '').trim();
      return _NodeToken(
        id: id,
        label: label.isEmpty ? id : label,
        shape: pattern.shape,
        consumed: m.end,
        raw: text,
        hasExplicitShape: true,
      );
    }
    final RegExpMatch? bare = RegExp(r'^[A-Za-z0-9_\-]+').firstMatch(text);
    if (bare == null) return null;
    final String id = bare.group(0)!;
    return _NodeToken(
      id: id,
      label: id,
      shape: FlowNodeShape.rect,
      consumed: bare.end,
      raw: text,
      hasExplicitShape: false,
    );
  }
}

class _EdgePattern {
  const _EdgePattern(this.regex, this.style, this.hasLabel, {this.arrow = true});
  final RegExp regex;
  final FlowEdgeStyle style;
  final bool hasLabel;
  final bool arrow;
}

class _EdgeMatch {
  const _EdgeMatch({
    required this.start,
    required this.end,
    required this.style,
    required this.arrow,
    required this.inlineLabel,
  });
  final int start;
  final int end;
  final FlowEdgeStyle style;
  final bool arrow;
  final String? inlineLabel;
}

class _NodePattern {
  const _NodePattern(this.regex, this.shape);
  final RegExp regex;
  final FlowNodeShape shape;
}

class _NodeToken {
  const _NodeToken({
    required this.id,
    required this.label,
    required this.shape,
    required this.consumed,
    required this.raw,
    required this.hasExplicitShape,
  });
  final String id;
  final String label;
  final FlowNodeShape shape;
  final int consumed;
  final String raw;
  final bool hasExplicitShape;
}
