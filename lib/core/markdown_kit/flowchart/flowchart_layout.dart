import 'package:flutter/widgets.dart';

import 'flowchart_model.dart';

/// A Sugiyama-style layered layout:
///
/// 1. rank nodes by longest path, after temporarily reversing any edge
///    that would otherwise create a cycle (found via a DFS back-edge scan),
/// 2. insert zero-size "dummy" nodes wherever an edge spans more than one
///    rank, so long edges become a chain of rank-adjacent segments instead
///    of one line drawn straight through whatever sits in between,
/// 3. reorder each rank with a few barycenter sweeps to cut down on edge
///    crossings, keeping the ordering with the fewest crossings seen,
/// 4. assign cross-axis coordinates with a median pass so a parent centers
///    over its children, resolving any overlaps left behind with a
///    left-to-right sweep that enforces a fixed minimum gap.
///
/// Nowhere near a full graph-layout library, but stable, fast, and good
/// enough for the small diagrams people actually put in notes.
class FlowchartLayout {
  static const double _rankGap = 72;
  static const double _nodeGap = 28;
  static const double _hPad = 16;
  static const double _vPad = 12;

  /// Runs the layout in place — every [FlowNode] in [graph] gets its `x`,
  /// `y`, `width`, `height` filled in, and every [FlowEdge] gets its
  /// `waypoints` filled in.
  static void apply(FlowGraph graph, TextStyle labelStyle) {
    if (graph.isEmpty) return;

    _measure(graph, labelStyle);

    final Set<int> backEdges = _detectBackEdges(graph);
    final Map<String, int> rank = _computeRanks(graph, backEdges);
    final int maxRank = rank.values.fold(0, (int m, int r) => r > m ? r : m);

    final List<List<_LNode>> layers =
        List.generate(maxRank + 1, (_) => <_LNode>[]);
    final Map<String, _LNode> realBoxes = <String, _LNode>{};
    for (final FlowNode node in graph.nodes.values) {
      final _LNode box = _LNode(rank: rank[node.id] ?? 0, real: node)
        ..width = node.width
        ..height = node.height;
      realBoxes[node.id] = box;
      layers[box.rank].add(box);
    }

    final Map<int, List<_LNode>> dummyChains = _insertDummyNodes(
      graph,
      rank,
      layers,
    );

    _linkNeighbors(graph, realBoxes, dummyChains);
    for (final List<_LNode> layer in layers) {
      _setOrder(layer);
    }
    _reduceCrossings(layers);
    _assignCrossAxis(graph, layers);
    _assignMainAxis(graph, layers);
    _finalizePositions(graph, layers);
    _applyCanvasPadding(layers);
    _computeEdgeRoutes(graph, dummyChains);
  }

  // ---- measurement ------------------------------------------------------

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

      node.width = w.clamp(72, 260);
      node.height = h.clamp(44, 140);
    }
  }

  // ---- layering -----------------------------------------------------

  /// Standard white/gray/black DFS back-edge scan, run iteratively (not
  /// recursively) so a long chain of nodes can't blow the call stack. Any
  /// edge whose target is still "in progress" (gray) when the edge is
  /// followed closes a cycle — that edge is reported so the caller can
  /// treat it as reversed for ranking purposes only. This replaces the old
  /// guard-counter/fallback approach: once these edges are logically
  /// flipped, the remaining graph is guaranteed acyclic and ranking needs
  /// no escape hatch at all.
  static Set<int> _detectBackEdges(FlowGraph graph) {
    final Map<String, List<int>> outEdgeIdx = <String, List<int>>{
      for (final String id in graph.nodes.keys) id: <int>[],
    };
    final Map<String, int> indegree = <String, int>{
      for (final String id in graph.nodes.keys) id: 0,
    };
    for (int i = 0; i < graph.edges.length; i++) {
      final FlowEdge e = graph.edges[i];
      if (!graph.nodes.containsKey(e.fromId) ||
          !graph.nodes.containsKey(e.toId)) {
        continue;
      }
      if (e.fromId == e.toId) continue; // self-loop: irrelevant to ranking
      outEdgeIdx[e.fromId]!.add(i);
      indegree[e.toId] = (indegree[e.toId] ?? 0) + 1;
    }

    final Set<int> backEdges = <int>{};
    // 0 = unvisited, 1 = in progress (on the current DFS path), 2 = done.
    final Map<String, int> state = <String, int>{};

    // Which edge gets flagged as the "back" edge of a cycle depends on
    // where the DFS starts inside that cycle — and starting from an
    // arbitrary node (previously just declaration order) can reverse the
    // wrong edge, stranding nodes that are really deep in the flow up at
    // rank 0. Visiting true sources first (nodes nothing points to, e.g.
    // "Splash") — in the order they first appear — before falling back to
    // whatever's left over (nodes only reachable from inside a cycle, with
    // no unambiguous starting point) means the DFS reverses the actual
    // "navigate back" edge instead of some unrelated edge that happened to
    // be visited first, so a diagram with a clear entry point reliably
    // lays out top-to-bottom the way it reads.
    final List<String> startOrder = <String>[
      for (final String id in graph.nodes.keys)
        if ((indegree[id] ?? 0) == 0) id,
      for (final String id in graph.nodes.keys)
        if ((indegree[id] ?? 0) != 0) id,
    ];

    for (final String start in startOrder) {
      if ((state[start] ?? 0) != 0) continue;
      final List<_DfsFrame> stack = <_DfsFrame>[_DfsFrame(start)];
      state[start] = 1;
      while (stack.isNotEmpty) {
        final _DfsFrame frame = stack.last;
        final List<int> outs = outEdgeIdx[frame.id]!;
        if (frame.next < outs.length) {
          final int edgeIdx = outs[frame.next];
          frame.next++;
          final String to = graph.edges[edgeIdx].toId;
          final int st = state[to] ?? 0;
          if (st == 0) {
            state[to] = 1;
            stack.add(_DfsFrame(to));
          } else if (st == 1) {
            backEdges.add(edgeIdx);
          }
          // st == 2: a forward/cross edge — fine as-is, not a cycle.
        } else {
          state[frame.id] = 2;
          stack.removeLast();
        }
      }
    }
    return backEdges;
  }

  /// Longest-path layering via Kahn's algorithm over the effective (back
  /// edges reversed) graph. Because that graph is guaranteed acyclic, this
  /// terminates cleanly and every node gets a real rank — no fallback to
  /// rank 0 for anything still standing when the queue empties.
  static Map<String, int> _computeRanks(FlowGraph graph, Set<int> backEdges) {
    final Map<String, int> indeg = <String, int>{
      for (final String id in graph.nodes.keys) id: 0,
    };
    final Map<String, List<String>> outAdj = <String, List<String>>{
      for (final String id in graph.nodes.keys) id: <String>[],
    };

    for (int i = 0; i < graph.edges.length; i++) {
      final FlowEdge e = graph.edges[i];
      if (!graph.nodes.containsKey(e.fromId) ||
          !graph.nodes.containsKey(e.toId)) {
        continue;
      }
      if (e.fromId == e.toId) continue;
      final bool back = backEdges.contains(i);
      final String from = back ? e.toId : e.fromId;
      final String to = back ? e.fromId : e.toId;
      outAdj[from]!.add(to);
      indeg[to] = (indeg[to] ?? 0) + 1;
    }

    final Map<String, int> rank = <String, int>{};
    final List<String> queue = <String>[
      for (final String id in graph.nodes.keys)
        if ((indeg[id] ?? 0) == 0) id,
    ];
    for (final String id in queue) {
      rank[id] = 0;
    }

    final Map<String, int> remaining = Map<String, int>.from(indeg);
    int head = 0;
    while (head < queue.length) {
      final String u = queue[head++];
      final int ru = rank[u] ?? 0;
      for (final String v in outAdj[u] ?? const <String>[]) {
        final int candidate = ru + 1;
        if (!rank.containsKey(v) || candidate > rank[v]!) {
          rank[v] = candidate;
        }
        remaining[v] = (remaining[v] ?? 0) - 1;
        if (remaining[v] == 0) {
          queue.add(v);
        }
      }
    }

    // Defensive only: with back edges reversed the graph is acyclic, so
    // every node should already be ranked. Anything left over (there
    // shouldn't be) still gets a rank rather than being dropped.
    for (final String id in graph.nodes.keys) {
      rank.putIfAbsent(id, () => 0);
    }
    return rank;
  }

  // ---- dummy nodes for multi-rank edges ------------------------------

  /// For every edge that spans more than one rank, inserts a chain of
  /// zero-size dummy nodes — one per intermediate rank, in the order the
  /// edge actually travels from `fromId` to `toId` — into [layers]. Returns
  /// the chain per edge index so later stages can link them up as
  /// neighbours and, at the end, read their final positions back out as
  /// the edge's waypoints.
  static Map<int, List<_LNode>> _insertDummyNodes(
    FlowGraph graph,
    Map<String, int> rank,
    List<List<_LNode>> layers,
  ) {
    final Map<int, List<_LNode>> chains = <int, List<_LNode>>{};
    for (int ei = 0; ei < graph.edges.length; ei++) {
      final FlowEdge e = graph.edges[ei];
      if (!graph.nodes.containsKey(e.fromId) ||
          !graph.nodes.containsKey(e.toId)) {
        continue;
      }
      if (e.fromId == e.toId) continue; // self-loop, drawn separately

      final int rFrom = rank[e.fromId]!;
      final int rTo = rank[e.toId]!;
      if ((rTo - rFrom).abs() <= 1) continue; // adjacent/same rank: direct

      final int step = rTo > rFrom ? 1 : -1;
      final List<_LNode> chain = <_LNode>[];
      for (int r = rFrom + step; r != rTo; r += step) {
        final _LNode dummy = _LNode(rank: r);
        layers[r].add(dummy);
        chain.add(dummy);
      }
      chains[ei] = chain;
    }
    return chains;
  }

  static void _linkNeighbors(
    FlowGraph graph,
    Map<String, _LNode> realBoxes,
    Map<int, List<_LNode>> dummyChains,
  ) {
    void link(_LNode a, _LNode b) {
      if (a.rank == b.rank) return;
      if (a.rank < b.rank) {
        a.downNeighbors.add(b);
        b.upNeighbors.add(a);
      } else {
        a.upNeighbors.add(b);
        b.downNeighbors.add(a);
      }
    }

    for (int ei = 0; ei < graph.edges.length; ei++) {
      final FlowEdge e = graph.edges[ei];
      final _LNode? fromBox = realBoxes[e.fromId];
      final _LNode? toBox = realBoxes[e.toId];
      if (fromBox == null || toBox == null || fromBox == toBox) continue;

      final List<_LNode>? chain = dummyChains[ei];
      if (chain == null || chain.isEmpty) {
        if ((fromBox.rank - toBox.rank).abs() == 1) {
          link(fromBox, toBox);
        }
        // Same-rank direct edges contribute no vertical neighbour relation
        // for crossing reduction / median positioning purposes.
        continue;
      }
      _LNode prev = fromBox;
      for (final _LNode d in chain) {
        link(prev, d);
        prev = d;
      }
      link(prev, toBox);
    }
  }

  // ---- crossing reduction ---------------------------------------------

  static void _setOrder(List<_LNode> layer) {
    for (int i = 0; i < layer.length; i++) {
      layer[i].order = i;
    }
  }

  static List<List<_LNode>> _snapshotOrder(List<List<_LNode>> layers) => [
        for (final List<_LNode> layer in layers) List<_LNode>.from(layer),
      ];

  static void _restoreOrder(
    List<List<_LNode>> layers,
    List<List<_LNode>> snapshot,
  ) {
    for (int i = 0; i < layers.length; i++) {
      layers[i]
        ..clear()
        ..addAll(snapshot[i]);
    }
  }

  /// Alternating down/up barycenter sweeps, keeping whichever ordering
  /// produced the fewest counted crossings across all rank boundaries.
  static void _reduceCrossings(List<List<_LNode>> layers) {
    if (layers.length < 2) return;

    List<List<_LNode>> best = _snapshotOrder(layers);
    int bestScore = _countCrossings(layers);
    if (bestScore == 0) return;

    const int sweeps = 4;
    for (int s = 0; s < sweeps && bestScore > 0; s++) {
      for (int r = 1; r < layers.length; r++) {
        _barycenterSort(layers[r], up: true);
        _setOrder(layers[r]);
      }
      int score = _countCrossings(layers);
      if (score < bestScore) {
        bestScore = score;
        best = _snapshotOrder(layers);
        if (bestScore == 0) break;
      }

      for (int r = layers.length - 2; r >= 0; r--) {
        _barycenterSort(layers[r], up: false);
        _setOrder(layers[r]);
      }
      score = _countCrossings(layers);
      if (score < bestScore) {
        bestScore = score;
        best = _snapshotOrder(layers);
      }
    }

    _restoreOrder(layers, best);
    for (final List<_LNode> layer in layers) {
      _setOrder(layer);
    }
  }

  static void _barycenterSort(List<_LNode> layer, {required bool up}) {
    if (layer.length < 2) return;
    final int n = layer.length;
    final List<double> keys = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final List<_LNode> neighbors =
          up ? layer[i].upNeighbors : layer[i].downNeighbors;
      if (neighbors.isEmpty) {
        // No pull from the adjacent rank: stay roughly where it already
        // was rather than collapsing to one end of the layer.
        keys[i] = i.toDouble();
      } else {
        double sum = 0;
        for (final _LNode nb in neighbors) {
          sum += nb.order;
        }
        keys[i] = sum / neighbors.length;
      }
    }
    final List<int> idx = List<int>.generate(n, (int i) => i);
    idx.sort((int a, int b) {
      final int cmp = keys[a].compareTo(keys[b]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    final List<_LNode> reordered = [for (final int i in idx) layer[i]];
    layer
      ..clear()
      ..addAll(reordered);
  }

  static int _countCrossings(List<List<_LNode>> layers) {
    int total = 0;
    for (int r = 0; r < layers.length - 1; r++) {
      final List<List<int>> segs = <List<int>>[];
      for (final _LNode u in layers[r]) {
        for (final _LNode v in u.downNeighbors) {
          segs.add(<int>[u.order, v.order]);
        }
      }
      segs.sort((List<int> a, List<int> b) =>
          a[0] != b[0] ? a[0] - b[0] : a[1] - b[1]);
      for (int i = 0; i < segs.length; i++) {
        for (int j = i + 1; j < segs.length; j++) {
          if (segs[j][1] < segs[i][1]) total++;
        }
      }
    }
    return total;
  }

  // ---- coordinate assignment -------------------------------------------

  static void _assignCrossAxis(FlowGraph graph, List<List<_LNode>> layers) {
    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;
    double extent(_LNode n) => horizontal ? n.height : n.width;

    // Initial pass: pack each rank left-to-right in its (now
    // crossing-minimised) order.
    for (final List<_LNode> layer in layers) {
      double cursor = 0;
      for (final _LNode n in layer) {
        n.cross = cursor + extent(n) / 2;
        cursor += extent(n) + _nodeGap;
      }
    }

    // Priority/median refinement: pull each node toward the median of its
    // neighbours in the adjacent rank, then resolve any overlaps with a
    // left-to-right sweep enforcing the fixed minimum gap. A few
    // alternating down/up passes let a parent settle over its children
    // (and vice versa) instead of only ever looking one way.
    const int passes = 4;
    for (int p = 0; p < passes; p++) {
      if (p.isEven) {
        for (int r = 1; r < layers.length; r++) {
          _medianPass(layers[r], up: true, extent: extent);
        }
      } else {
        for (int r = layers.length - 2; r >= 0; r--) {
          _medianPass(layers[r], up: false, extent: extent);
        }
      }
    }

    double minEdge = double.infinity;
    for (final List<_LNode> layer in layers) {
      for (final _LNode n in layer) {
        final double left = n.cross - extent(n) / 2;
        if (left < minEdge) minEdge = left;
      }
    }
    if (minEdge.isFinite) {
      for (final List<_LNode> layer in layers) {
        for (final _LNode n in layer) {
          n.cross -= minEdge;
        }
      }
    }
  }

  static void _medianPass(
    List<_LNode> layer, {
    required bool up,
    required double Function(_LNode) extent,
  }) {
    if (layer.isEmpty) return;
    final List<double> desired = <double>[
      for (final _LNode n in layer)
        _median(up ? n.upNeighbors : n.downNeighbors) ?? n.cross,
    ];
    double prevRightEdge = double.negativeInfinity;
    for (int i = 0; i < layer.length; i++) {
      final _LNode n = layer[i];
      final double half = extent(n) / 2;
      double pos = desired[i];
      if (prevRightEdge.isFinite) {
        final double minCenter = prevRightEdge + _nodeGap + half;
        if (pos < minCenter) pos = minCenter;
      }
      n.cross = pos;
      prevRightEdge = pos + half;
    }
  }

  static double? _median(List<_LNode> neighbors) {
    if (neighbors.isEmpty) return null;
    final List<double> values = [for (final _LNode n in neighbors) n.cross]
      ..sort();
    final int m = values.length;
    if (m.isOdd) return values[m ~/ 2];
    return (values[m ~/ 2 - 1] + values[m ~/ 2]) / 2;
  }

  static void _assignMainAxis(FlowGraph graph, List<List<_LNode>> layers) {
    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;
    double extent(_LNode n) => horizontal ? n.width : n.height;

    final List<double> rankExtent = <double>[
      for (final List<_LNode> layer in layers)
        layer.fold<double>(
          0,
          (double m, _LNode n) => extent(n) > m ? extent(n) : m,
        ),
    ];

    double cursor = 0;
    for (int r = 0; r < layers.length; r++) {
      for (final _LNode n in layers[r]) {
        n.main = cursor + extent(n) / 2;
      }
      cursor += rankExtent[r] + _rankGap;
    }
    final double total = cursor - _rankGap;

    final bool flip = graph.direction == FlowDirection.bottomToTop ||
        graph.direction == FlowDirection.rightToLeft;
    if (flip) {
      for (final List<_LNode> layer in layers) {
        for (final _LNode n in layer) {
          n.main = total - n.main;
        }
      }
    }
  }

  static void _finalizePositions(FlowGraph graph, List<List<_LNode>> layers) {
    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;
    for (final List<_LNode> layer in layers) {
      for (final _LNode n in layer) {
        final double cx = horizontal ? n.main : n.cross;
        final double cy = horizontal ? n.cross : n.main;
        n.centerX = cx;
        n.centerY = cy;
        final FlowNode? real = n.real;
        if (real != null) {
          real.x = cx - real.width / 2;
          real.y = cy - real.height / 2;
        }
      }
    }
  }

  static void _applyCanvasPadding(List<List<_LNode>> layers) {
    const double pad = FlowGraph.canvasPadding;
    for (final List<_LNode> layer in layers) {
      for (final _LNode n in layer) {
        n.centerX += pad;
        n.centerY += pad;
        final FlowNode? real = n.real;
        if (real != null) {
          real.x += pad;
          real.y += pad;
        }
      }
    }
  }

  static void _computeEdgeRoutes(
    FlowGraph graph,
    Map<int, List<_LNode>> dummyChains,
  ) {
    for (int ei = 0; ei < graph.edges.length; ei++) {
      final List<_LNode>? chain = dummyChains[ei];
      if (chain == null || chain.isEmpty) {
        graph.edges[ei].waypoints = const <FlowPoint>[];
      } else {
        graph.edges[ei].waypoints = [
          for (final _LNode d in chain) FlowPoint(d.centerX, d.centerY),
        ];
      }
    }
  }
}

/// One node in the layered layout graph: either a real [FlowNode] (`real`
/// non-null) or a zero-size dummy standing in for an edge passing through
/// this rank. Only used internally by [FlowchartLayout] — never exposed
/// outside this file.
class _LNode {
  _LNode({required this.rank, this.real});

  final int rank;
  final FlowNode? real;

  double width = 0;
  double height = 0;

  /// Position within its rank after crossing reduction.
  int order = 0;

  /// Cross-axis center (perpendicular to the flow direction).
  double cross = 0;

  /// Main-axis center (along the flow direction, i.e. which rank/row).
  double main = 0;

  /// Final screen-space center, filled in by `_finalizePositions`.
  double centerX = 0;
  double centerY = 0;

  final List<_LNode> upNeighbors = <_LNode>[];
  final List<_LNode> downNeighbors = <_LNode>[];
}

class _DfsFrame {
  _DfsFrame(this.id);
  final String id;
  int next = 0;
}
