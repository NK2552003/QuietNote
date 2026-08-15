import 'package:flutter/widgets.dart';

import 'flowchart_model.dart';

/// A minimal Sugiyama-style layered layout: rank nodes by longest path from
/// a root, order nodes within a rank by first appearance, then place them
/// on a grid sized to fit each node's measured label. Nowhere near a full
/// graph-layout library, but stable, fast, and good enough for the small
/// diagrams people actually put in notes.
class FlowchartLayout {
  static const double _rankGap = 56;
  static const double _nodeGap = 20;
  static const double _hPad = 14;
  static const double _vPad = 10;

  /// Runs the layout in place — every [FlowNode] in [graph] gets its `x`,
  /// `y`, `width`, `height` filled in.
  static void apply(FlowGraph graph, TextStyle labelStyle) {
    if (graph.isEmpty) return;

    _measure(graph, labelStyle);
    final Map<String, int> rank = _computeRanks(graph);
    final List<List<FlowNode>> byRank = _groupByRank(graph, rank);
    _position(graph, byRank);
  }

  static void _measure(FlowGraph graph, TextStyle style) {
    for (final FlowNode node in graph.nodes.values) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: node.label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 4,
        ellipsis: '…',
      )..layout(maxWidth: 200);

      double w = painter.width + _hPad * 2;
      double h = painter.height + _vPad * 2;

      switch (node.shape) {
        case FlowNodeShape.diamond:
          // A diamond's usable interior is roughly half its bounding box,
          // so it needs to be noticeably larger to fit the same text.
          w = w * 1.6 + 20;
          h = h * 1.7 + 16;
          break;
        case FlowNodeShape.circle:
          final double side = w > h ? w : h;
          w = h = side * 1.15;
          break;
        case FlowNodeShape.hexagon:
          w += 24;
          break;
        case FlowNodeShape.stadium:
          w += 12;
          h += 4;
          break;
        default:
          break;
      }

      node.width = w.clamp(64, 240);
      node.height = h.clamp(40, 140);
    }
  }

  /// Longest-path layering via a Kahn's-algorithm topological pass. Cycles
  /// (a node's own edges eventually pointing back to it — rare in notes,
  /// but real diagrams do have retry loops) are broken by forcing through
  /// whatever node is left once the queue stalls, rather than looping
  /// forever or leaving nodes unranked.
  static Map<String, int> _computeRanks(FlowGraph graph) {
    final Map<String, int> inDegree = <String, int>{
      for (final String id in graph.nodes.keys) id: 0,
    };
    final Map<String, List<String>> outEdges = <String, List<String>>{
      for (final String id in graph.nodes.keys) id: <String>[],
    };
    for (final FlowEdge e in graph.edges) {
      if (!graph.nodes.containsKey(e.fromId) || !graph.nodes.containsKey(e.toId)) {
        continue;
      }
      outEdges[e.fromId]!.add(e.toId);
      inDegree[e.toId] = (inDegree[e.toId] ?? 0) + 1;
    }

    final Map<String, int> rank = <String, int>{};
    final List<String> queue = <String>[
      for (final String id in graph.nodes.keys)
        if (inDegree[id] == 0) id,
    ];
    // A graph that's all cycles (no in-degree-0 node at all) still needs a
    // starting point — fall back to first-declared node.
    if (queue.isEmpty && graph.nodes.isNotEmpty) {
      queue.add(graph.nodes.keys.first);
    }
    for (final String id in queue) {
      rank[id] = 0;
    }

    final Map<String, int> remainingIn = Map<String, int>.from(inDegree);
    int guard = 0;
    while (rank.length < graph.nodes.length && guard < graph.nodes.length * 4 + 8) {
      guard++;
      if (queue.isEmpty) {
        // Stalled on a cycle: pick any unranked node to unblock it.
        final String? next = graph.nodes.keys.firstWhere(
          (String id) => !rank.containsKey(id),
          orElse: () => '',
        );
        if (next == null || next.isEmpty) break;
        rank[next] = 0;
        queue.add(next);
      }
      final String current = queue.removeAt(0);
      final int currentRank = rank[current] ?? 0;
      for (final String next in outEdges[current] ?? const <String>[]) {
        final int candidate = currentRank + 1;
        if (!rank.containsKey(next) || candidate > rank[next]!) {
          rank[next] = candidate;
        }
        remainingIn[next] = (remainingIn[next] ?? 0) - 1;
        if ((remainingIn[next] ?? 0) <= 0 && !queue.contains(next)) {
          queue.add(next);
        }
      }
    }

    // Anything the pass never reached (disconnected nodes) still needs a
    // rank so it's drawn somewhere rather than silently dropped.
    for (final String id in graph.nodes.keys) {
      rank.putIfAbsent(id, () => 0);
    }
    return rank;
  }

  static List<List<FlowNode>> _groupByRank(
    FlowGraph graph,
    Map<String, int> rank,
  ) {
    final int maxRank = rank.values.fold(0, (int m, int r) => r > m ? r : m);
    final List<List<FlowNode>> byRank =
        List.generate(maxRank + 1, (_) => <FlowNode>[]);
    // Preserve declaration order within a rank for a stable, readable
    // left-to-right (or top-to-bottom) sequence.
    for (final FlowNode node in graph.nodes.values) {
      byRank[rank[node.id] ?? 0].add(node);
    }
    return byRank;
  }

  static void _position(FlowGraph graph, List<List<FlowNode>> byRank) {
    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;

    // Cross-axis size of a rank is the sum of its nodes' cross-axis extents;
    // main-axis size of a rank is the largest main-axis extent in it.
    final List<double> rankMain = <double>[];
    final List<double> rankCross = <double>[];
    for (final List<FlowNode> rank in byRank) {
      double main = 0;
      double cross = 0;
      for (final FlowNode n in rank) {
        final double nMain = horizontal ? n.width : n.height;
        final double nCross = horizontal ? n.height : n.width;
        if (nMain > main) main = nMain;
        cross += nCross + _nodeGap;
      }
      rankMain.add(main);
      rankCross.add(cross > 0 ? cross - _nodeGap : 0);
    }

    final double maxCross =
        rankCross.fold(0, (double m, double c) => c > m ? c : m);

    double mainCursor = 0;
    for (int r = 0; r < byRank.length; r++) {
      final List<FlowNode> rank = byRank[r];
      // Centre this rank's nodes across the widest rank, so a single
      // top-level node isn't pinned to one edge with everything else
      // spread out beside it.
      double crossCursor = (maxCross - rankCross[r]) / 2;
      for (final FlowNode n in rank) {
        final double nCross = horizontal ? n.height : n.width;
        switch (graph.direction) {
          case FlowDirection.topToBottom:
            n.x = crossCursor;
            n.y = mainCursor;
            break;
          case FlowDirection.bottomToTop:
            n.x = crossCursor;
            n.y = mainCursor;
            break;
          case FlowDirection.leftToRight:
            n.x = mainCursor;
            n.y = crossCursor;
            break;
          case FlowDirection.rightToLeft:
            n.x = mainCursor;
            n.y = crossCursor;
            break;
        }
        crossCursor += nCross + _nodeGap;
      }
      mainCursor += rankMain[r] + _rankGap;
    }

    // bottomToTop / rightToLeft: ranks were placed in increasing main-axis
    // order (rank 0 first); flip the main axis so rank 0 actually ends up
    // at the bottom/right as the direction implies.
    if (graph.direction == FlowDirection.bottomToTop ||
        graph.direction == FlowDirection.rightToLeft) {
      final double total = mainCursor - _rankGap;
      for (final FlowNode n in graph.nodes.values) {
        if (graph.direction == FlowDirection.bottomToTop) {
          n.y = total - n.y - n.height;
        } else {
          n.x = total - n.x - n.width;
        }
      }
    }
  }
}
