/// Data model for a parsed ```mermaid``` flowchart. Kept separate from
/// parsing and rendering so each stage (parse → layout → paint) can be
/// reasoned about — and fixed — independently.
library;

/// Node outline. Mirrors the handful of Mermaid flowchart shapes people
/// actually use in notes; anything unrecognised falls back to [rect].
enum FlowNodeShape {
  rect,
  rounded,
  stadium,
  circle,
  diamond,
  subroutine,
  hexagon,
  cylinder,
  flag,
}

/// Line weight/dash style for an edge.
enum FlowEdgeStyle { solid, dashed, thick }

class FlowNode {
  FlowNode({required this.id, required this.label, this.shape = FlowNodeShape.rect});

  final String id;
  String label;
  FlowNodeShape shape;

  /// Filled in by the layout pass.
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
}

class FlowEdge {
  FlowEdge({
    required this.fromId,
    required this.toId,
    this.label,
    this.style = FlowEdgeStyle.solid,
    this.arrowEnd = true,
    this.arrowStart = false,
  });

  final String fromId;
  final String toId;
  final String? label;
  final FlowEdgeStyle style;
  final bool arrowEnd;
  final bool arrowStart;
}

enum FlowDirection { topToBottom, bottomToTop, leftToRight, rightToLeft }

class FlowGraph {
  FlowGraph({
    required this.direction,
    required this.nodes,
    required this.edges,
  });

  /// An empty graph — used as a safe fallback when nothing could be parsed.
  factory FlowGraph.empty() => FlowGraph(
        direction: FlowDirection.topToBottom,
        nodes: <String, FlowNode>{},
        edges: <FlowEdge>[],
      );

  final FlowDirection direction;
  final Map<String, FlowNode> nodes;
  final List<FlowEdge> edges;

  bool get isEmpty => nodes.isEmpty;

  /// Overall canvas size once every node has been positioned by the layout
  /// pass (see `flowchart_layout.dart`).
  double get contentWidth => nodes.values.fold<double>(
        0,
        (double max, FlowNode n) => n.x + n.width > max ? n.x + n.width : max,
      );

  double get contentHeight => nodes.values.fold<double>(
        0,
        (double max, FlowNode n) => n.y + n.height > max ? n.y + n.height : max,
      );
}
