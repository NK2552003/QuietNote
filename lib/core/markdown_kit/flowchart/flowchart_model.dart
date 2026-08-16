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

/// A plain x/y point. Used instead of `dart:ui`'s `Offset` so this file
/// (parsed and laid out well before anything touches the Flutter widget
/// tree) stays a pure Dart model with no Flutter dependency.
class FlowPoint {
  const FlowPoint(this.x, this.y);
  final double x;
  final double y;
}

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

  /// Intermediate bend points the edge must route through, filled in by
  /// the layout pass for any edge that spans more than one rank (one
  /// waypoint per rank it crosses, from a zero-size dummy node inserted at
  /// that rank). Empty for edges between adjacent (or the same) ranks,
  /// which are drawn as a single segment straight between the two nodes.
  /// The painter figures out the actual attachment points on the node
  /// boundaries itself — this list only carries the bend points in
  /// between, so a long edge is a chain of rank-adjacent segments and can
  /// never cut straight through an unrelated box.
  List<FlowPoint> waypoints = const <FlowPoint>[];
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

  /// Margin kept around the laid-out content so arrowheads, label chips
  /// and node shadows near the edge of the diagram never get clipped by
  /// the canvas bounds. The layout pass offsets every node's position by
  /// this same amount (see `FlowchartLayout._applyCanvasPadding`), so the
  /// margin ends up on every side rather than only the trailing one.
  static const double canvasPadding = 16;

  /// Overall canvas size once every node has been positioned by the layout
  /// pass (see `flowchart_layout.dart`).
  double get contentWidth =>
      nodes.values.fold<double>(
        0,
        (double max, FlowNode n) => n.x + n.width > max ? n.x + n.width : max,
      ) +
      canvasPadding;

  double get contentHeight =>
      nodes.values.fold<double>(
        0,
        (double max, FlowNode n) => n.y + n.height > max ? n.y + n.height : max,
      ) +
      canvasPadding;
}
