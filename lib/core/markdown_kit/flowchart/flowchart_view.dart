import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

import 'flowchart_layout.dart';
import 'flowchart_model.dart';
import 'flowchart_parser.dart';

/// Colour set a [FlowchartView] paints with. Two ways to get one:
/// [FlowchartPalette.themed] follows the app's live theme (light/dark, and
/// re-themes automatically if the person switches while looking at it);
/// [FlowchartPalette.printFriendly] is a fixed light palette for contexts
/// that need to stay readable regardless of the app's theme, like an
/// exported PDF page.
class FlowchartPalette {
  const FlowchartPalette({
    required this.background,
    required this.nodeFill,
    required this.nodeBorder,
    required this.nodeText,
    required this.decisionFill,
    required this.edgeColor,
    required this.edgeLabelBackground,
    required this.edgeLabelText,
  });

  factory FlowchartPalette.themed(BuildContext context) {
    final colors = context.uiColors;
    return FlowchartPalette(
      background: Colors.transparent,
      nodeFill: colors.surface,
      nodeBorder: colors.borderStrong,
      nodeText: colors.foreground,
      decisionFill: colors.primary.withValues(alpha: 0.10),
      edgeColor: colors.foregroundMuted,
      edgeLabelBackground: colors.surface,
      edgeLabelText: colors.foregroundMuted,
    );
  }

  factory FlowchartPalette.printFriendly() => const FlowchartPalette(
        background: Colors.white,
        nodeFill: Color(0xFFF6F5F3),
        nodeBorder: Color(0xFF33322F),
        nodeText: Color(0xFF1A1A1A),
        decisionFill: Color(0xFFEDEAE3),
        edgeColor: Color(0xFF5B5A56),
        edgeLabelBackground: Colors.white,
        edgeLabelText: Color(0xFF5B5A56),
      );

  final Color background;
  final Color nodeFill;
  final Color nodeBorder;
  final Color nodeText;
  final Color decisionFill;
  final Color edgeColor;
  final Color edgeLabelBackground;
  final Color edgeLabelText;
}

/// Renders a Mermaid-flavoured flowchart from `source`, laid out and
/// painted entirely in Flutter — no external renderer, no async engine that
/// can silently fail to produce anything. A diagram that fails to parse (or
/// has nothing in it) still shows something explicit instead of a blank
/// space.
class FlowchartView extends StatelessWidget {
  const FlowchartView({super.key, required this.source, required this.palette});

  final String source;
  final FlowchartPalette palette;

  @override
  Widget build(BuildContext context) {
    final FlowGraph graph = FlowchartParser.parse(source);

    if (graph.isEmpty) {
      return _EmptyDiagram(palette: palette);
    }

    final TextStyle labelStyle = TextStyle(
      fontSize: 12.5,
      height: 1.25,
      color: palette.nodeText,
      fontWeight: FontWeight.w500,
    );
    FlowchartLayout.apply(graph, labelStyle);

    final double width = math.max(graph.contentWidth, 40);
    final double height = math.max(graph.contentHeight, 40);

    return Container(
      color: palette.background,
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: _FlowchartPainter(
          graph: graph,
          palette: palette,
          labelStyle: labelStyle,
        ),
      ),
    );
  }
}

class _EmptyDiagram extends StatelessWidget {
  const _EmptyDiagram({required this.palette});
  final FlowchartPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.background,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, size: 16, color: palette.edgeLabelText),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "Couldn't find any nodes in this flowchart.",
              style: TextStyle(fontSize: 12.5, color: palette.edgeLabelText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where on a node's boundary an edge attaches. Used to bucket every edge
/// touching a given node by which side of it they leave/enter from, so
/// several edges sharing a side can be spread out along it instead of
/// stacking on the same point.
enum _Face { top, bottom, left, right }

/// The two endpoints of one edge's route, resolved to actual attachment
/// points on the node boundaries (after port distribution).
class _PortPair {
  const _PortPair(this.start, this.end);
  final Offset start;
  final Offset end;
}

/// One edge's claim on a face of a node, waiting to be spread evenly along
/// that face once every edge touching it has been collected.
class _PortSlot {
  _PortSlot({required this.edgeIndex, required this.isStart, required this.sortKey});
  final int edgeIndex;
  final bool isStart;
  final double sortKey;
}

class _Segment {
  const _Segment(this.a, this.b);
  final Offset a;
  final Offset b;
  double get length => (b - a).distance;
}

class _FlowchartPainter extends CustomPainter {
  _FlowchartPainter({
    required this.graph,
    required this.palette,
    required this.labelStyle,
  });

  final FlowGraph graph;
  final FlowchartPalette palette;
  final TextStyle labelStyle;

  /// Chip rects already placed this paint, used to nudge a new label out
  /// of the way of ones already drawn. Cleared at the start of every
  /// [paint] call.
  final List<Rect> _labelRects = <Rect>[];

  @override
  void paint(Canvas canvas, Size size) {
    _labelRects.clear();
    final Map<int, _PortPair> ports = _computePorts();

    for (int i = 0; i < graph.edges.length; i++) {
      final FlowEdge edge = graph.edges[i];
      final FlowNode? from = graph.nodes[edge.fromId];
      final FlowNode? to = graph.nodes[edge.toId];
      if (from == null || to == null) continue;
      if (from == to) {
        _paintSelfLoop(canvas, from, edge);
        continue;
      }
      final _PortPair? pair = ports[i];
      if (pair == null) continue;
      _paintRoutedEdge(canvas, edge, pair.start, pair.end);
    }
    for (final FlowNode node in graph.nodes.values) {
      _paintNode(canvas, node);
    }
  }

  // ---- ports -----------------------------------------------------------

  /// Figures out, for every edge, exactly where on its two nodes' boundary
  /// it attaches. Edges sharing a face on the same node are spread evenly
  /// along that face (ordered by the other endpoint's cross-axis
  /// position) instead of all converging on the center, which is what used
  /// to make several edges leaving/entering the same node stack exactly on
  /// top of each other.
  Map<int, _PortPair> _computePorts() {
    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;
    final bool reversed = graph.direction == FlowDirection.bottomToTop ||
        graph.direction == FlowDirection.rightToLeft;

    final Map<String, List<_PortSlot>> buckets = <String, List<_PortSlot>>{};

    String key(String nodeId, _Face face) => '$nodeId#${face.index}';

    for (int i = 0; i < graph.edges.length; i++) {
      final FlowEdge edge = graph.edges[i];
      final FlowNode? from = graph.nodes[edge.fromId];
      final FlowNode? to = graph.nodes[edge.toId];
      if (from == null || to == null || from == to) continue;

      final Rect a = Rect.fromLTWH(from.x, from.y, from.width, from.height);
      final Rect b = Rect.fromLTWH(to.x, to.y, to.width, to.height);
      final bool aBeforeB = horizontal
          ? (reversed ? a.left > b.left : a.left < b.left)
          : (reversed ? a.top > b.top : a.top < b.top);

      final _Face startFace = horizontal
          ? (aBeforeB ? _Face.right : _Face.left)
          : (aBeforeB ? _Face.bottom : _Face.top);
      final _Face endFace = horizontal
          ? (aBeforeB ? _Face.left : _Face.right)
          : (aBeforeB ? _Face.top : _Face.bottom);

      final double startSortKey = horizontal ? b.center.dy : b.center.dx;
      final double endSortKey = horizontal ? a.center.dy : a.center.dx;

      buckets
          .putIfAbsent(key(from.id, startFace), () => <_PortSlot>[])
          .add(_PortSlot(edgeIndex: i, isStart: true, sortKey: startSortKey));
      buckets
          .putIfAbsent(key(to.id, endFace), () => <_PortSlot>[])
          .add(_PortSlot(edgeIndex: i, isStart: false, sortKey: endSortKey));
    }

    final Map<int, Offset> startOffsets = <int, Offset>{};
    final Map<int, Offset> endOffsets = <int, Offset>{};

    buckets.forEach((String bucketKey, List<_PortSlot> slots) {
      final int hashIdx = bucketKey.lastIndexOf('#');
      final String nodeId = bucketKey.substring(0, hashIdx);
      final _Face face = _Face.values[int.parse(bucketKey.substring(hashIdx + 1))];
      final FlowNode? node = graph.nodes[nodeId];
      if (node == null) return;
      final Rect rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);

      slots.sort((_PortSlot s1, _PortSlot s2) => s1.sortKey.compareTo(s2.sortKey));
      final int n = slots.length;
      for (int i = 0; i < n; i++) {
        final double t = (i + 1) / (n + 1);
        final Offset pos;
        switch (face) {
          case _Face.top:
            pos = Offset(rect.left + rect.width * t, rect.top);
            break;
          case _Face.bottom:
            pos = Offset(rect.left + rect.width * t, rect.bottom);
            break;
          case _Face.left:
            pos = Offset(rect.left, rect.top + rect.height * t);
            break;
          case _Face.right:
            pos = Offset(rect.right, rect.top + rect.height * t);
            break;
        }
        if (slots[i].isStart) {
          startOffsets[slots[i].edgeIndex] = pos;
        } else {
          endOffsets[slots[i].edgeIndex] = pos;
        }
      }
    });

    final Map<int, _PortPair> result = <int, _PortPair>{};
    for (int i = 0; i < graph.edges.length; i++) {
      final Offset? s = startOffsets[i];
      final Offset? e = endOffsets[i];
      if (s != null && e != null) {
        result[i] = _PortPair(s, e);
      }
    }
    return result;
  }

  // ---- nodes ---------------------------------------------------------

  void _paintNode(Canvas canvas, FlowNode node) {
    final Rect rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
    final Paint fill = Paint()
      ..color = node.shape == FlowNodeShape.diamond
          ? palette.decisionFill
          : palette.nodeFill
      ..style = PaintingStyle.fill;
    final Paint border = Paint()
      ..color = palette.nodeBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    // A faint drop shadow gives every node a touch of depth — the same
    // quiet "card" feel diagrams render with elsewhere — instead of the
    // flat, slightly harsh look of a plain fill + stroke.
    final Paint shadow = Paint()
      ..color = const Color(0x14000000)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    switch (node.shape) {
      case FlowNodeShape.rect:
      case FlowNodeShape.subroutine:
        final RRect r = RRect.fromRectAndRadius(rect, const Radius.circular(9));
        canvas.drawRRect(r.shift(const Offset(0, 1.5)), shadow);
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, border);
        if (node.shape == FlowNodeShape.subroutine) {
          const double inset = 5;
          final Paint bar = Paint()
            ..color = palette.nodeBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3;
          canvas.drawLine(
            Offset(rect.left + inset, rect.top),
            Offset(rect.left + inset, rect.bottom),
            bar,
          );
          canvas.drawLine(
            Offset(rect.right - inset, rect.top),
            Offset(rect.right - inset, rect.bottom),
            bar,
          );
        }
        break;
      case FlowNodeShape.rounded:
        final RRect r =
            RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2.6));
        canvas.drawRRect(r.shift(const Offset(0, 1.5)), shadow);
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, border);
        break;
      case FlowNodeShape.stadium:
        final RRect r =
            RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
        canvas.drawRRect(r.shift(const Offset(0, 1.5)), shadow);
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, border);
        break;
      case FlowNodeShape.circle:
        final Offset center = rect.center;
        final double radius = math.min(rect.width, rect.height) / 2;
        canvas.drawCircle(center + const Offset(0, 1.5), radius, shadow);
        canvas.drawCircle(center, radius, fill);
        canvas.drawCircle(center, radius, border);
        break;
      case FlowNodeShape.diamond:
        final Path path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path.shift(const Offset(0, 1.5)), shadow);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, border);
        break;
      case FlowNodeShape.hexagon:
        final double cut = rect.width * 0.16;
        final Path path = Path()
          ..moveTo(rect.left + cut, rect.top)
          ..lineTo(rect.right - cut, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.right - cut, rect.bottom)
          ..lineTo(rect.left + cut, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path.shift(const Offset(0, 1.5)), shadow);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, border);
        break;
      case FlowNodeShape.cylinder:
        final double capH = rect.height * 0.18;
        canvas.drawRect(
          Rect.fromLTRB(rect.left, rect.top + capH / 2, rect.right, rect.bottom - capH / 2),
          fill,
        );
        canvas.drawOval(Rect.fromLTWH(rect.left, rect.top, rect.width, capH), fill);
        canvas.drawOval(
          Rect.fromLTWH(rect.left, rect.bottom - capH, rect.width, capH),
          fill,
        );
        final Path outline = Path()
          ..moveTo(rect.left, rect.top + capH / 2)
          ..lineTo(rect.left, rect.bottom - capH / 2)
          ..addArc(
            Rect.fromLTWH(rect.left, rect.bottom - capH, rect.width, capH),
            math.pi,
            math.pi,
          )
          ..moveTo(rect.right, rect.bottom - capH / 2)
          ..lineTo(rect.right, rect.top + capH / 2)
          ..addArc(Rect.fromLTWH(rect.left, rect.top, rect.width, capH), 0, math.pi);
        canvas.drawPath(outline, border);
        canvas.drawOval(Rect.fromLTWH(rect.left, rect.top, rect.width, capH), border);
        break;
      case FlowNodeShape.flag:
        final Path path = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right - 10, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.right - 10, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, border);
        break;
    }

    _drawLabel(canvas, node.label, rect, node.shape);
  }

  void _drawLabel(Canvas canvas, String text, Rect rect, FlowNodeShape shape) {
    // A diamond's readable interior is a smaller inscribed box, so its text
    // is measured against a narrower width than the raw node bounds.
    final double maxWidth = shape == FlowNodeShape.diamond
        ? rect.width * 0.6
        : rect.width - 16;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: math.max(maxWidth, 10));
    final Offset offset = Offset(
      rect.center.dx - painter.width / 2,
      rect.center.dy - painter.height / 2,
    );
    painter.paint(canvas, offset);
  }

  // ---- edges ----------------------------------------------------------

  /// Paints an edge as a rounded polyline through `start`, every waypoint
  /// the layout inserted for it (one per rank it spans), and `end` — so a
  /// long edge bends around whatever it needs to instead of being drawn as
  /// one long curve straight through the boxes in between. Each hop is
  /// routed as a right-angle "L" (via [_orthogonalize]) rather than a
  /// diagonal line, so edges leave/enter nodes straight-on and only ever
  /// bend at 90°.
  void _paintRoutedEdge(Canvas canvas, FlowEdge edge, Offset start, Offset end) {
    final List<Offset> points = _orthogonalize(<Offset>[
      start,
      for (final FlowPoint p in edge.waypoints) Offset(p.x, p.y),
      end,
    ]);

    final Paint linePaint = Paint()
      ..color = palette.edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge.style == FlowEdgeStyle.thick ? 2.2 : 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = _roundedPolyline(points, 16);

    if (edge.style == FlowEdgeStyle.dashed) {
      _drawDashedPath(canvas, path, linePaint);
    } else {
      canvas.drawPath(path, linePaint);
    }

    if (edge.arrowEnd) {
      _drawArrowHead(canvas, end, end - points[points.length - 2], linePaint.color);
    }
    if (edge.arrowStart) {
      _drawArrowHead(canvas, start, start - points[1], linePaint.color);
    }

    if (edge.label != null && edge.label!.isNotEmpty) {
      final _Segment longest = _longestSegment(points);
      final Offset anchor = Offset(
        (longest.a.dx + longest.b.dx) / 2,
        (longest.a.dy + longest.b.dy) / 2,
      );
      _drawEdgeLabel(canvas, edge.label!, anchor);
    }
  }

  void _paintSelfLoop(Canvas canvas, FlowNode node, FlowEdge edge) {
    final Rect rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
    final double loopSize = math.max(22, rect.height * 0.5);
    final Offset exit = Offset(rect.right, rect.top + rect.height * 0.32);
    final Offset enter = Offset(rect.right, rect.top + rect.height * 0.68);
    final Offset bulge1 = Offset(rect.right + loopSize, exit.dy - loopSize * 0.35);
    final Offset bulge2 = Offset(rect.right + loopSize, enter.dy + loopSize * 0.35);

    final Paint linePaint = Paint()
      ..color = palette.edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge.style == FlowEdgeStyle.thick ? 2.2 : 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path()
      ..moveTo(exit.dx, exit.dy)
      ..cubicTo(bulge1.dx, bulge1.dy, bulge2.dx, bulge2.dy, enter.dx, enter.dy);

    if (edge.style == FlowEdgeStyle.dashed) {
      _drawDashedPath(canvas, path, linePaint);
    } else {
      canvas.drawPath(path, linePaint);
    }

    if (edge.arrowEnd) {
      _drawArrowHead(canvas, enter, enter - bulge2, linePaint.color);
    }

    if (edge.label != null && edge.label!.isNotEmpty) {
      _drawEdgeLabel(
        canvas,
        edge.label!,
        Offset(rect.right + loopSize + 6, (exit.dy + enter.dy) / 2),
      );
    }
  }

  /// Turns a sequence of straight hops into right-angle ("L"-shaped) ones:
  /// between each consecutive pair of points, a hop that isn't already
  /// axis-aligned gets a bend inserted at the midpoint along the flow's
  /// main axis, so the segment travels straight out along the flow
  /// direction, turns once, then travels straight in — instead of cutting
  /// diagonally across the canvas. An already axis-aligned hop (same x for
  /// a vertical flow, same y for a horizontal one) is left as a single
  /// straight segment.
  List<Offset> _orthogonalize(List<Offset> points) {
    if (points.length < 2) return points;
    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;

    final List<Offset> out = <Offset>[points.first];
    for (int i = 0; i < points.length - 1; i++) {
      final Offset a = points[i];
      final Offset b = points[i + 1];
      if (horizontal) {
        if ((b.dy - a.dy).abs() > 0.5) {
          final double midX = (a.dx + b.dx) / 2;
          out.add(Offset(midX, a.dy));
          out.add(Offset(midX, b.dy));
        }
      } else {
        if ((b.dx - a.dx).abs() > 0.5) {
          final double midY = (a.dy + b.dy) / 2;
          out.add(Offset(a.dx, midY));
          out.add(Offset(b.dx, midY));
        }
      }
      out.add(b);
    }
    return out;
  }

  /// A polyline through [points] with each interior corner rounded off by
  /// [radius] (or less, if the adjoining segments are shorter than that).
  Path _roundedPolyline(List<Offset> points, double radius) {
    final Path path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length < 3) {
      if (points.length == 2) path.lineTo(points.last.dx, points.last.dy);
      return path;
    }
    for (int i = 1; i < points.length - 1; i++) {
      final Offset prev = points[i - 1];
      final Offset curr = points[i];
      final Offset next = points[i + 1];
      final Offset toPrev = prev - curr;
      final Offset toNext = next - curr;
      final double lenPrev = toPrev.distance;
      final double lenNext = toNext.distance;
      final double r = math.min(radius, math.min(lenPrev, lenNext) / 2);
      final Offset p1 = lenPrev == 0 ? curr : curr + toPrev / lenPrev * r;
      final Offset p2 = lenNext == 0 ? curr : curr + toNext / lenNext * r;
      path.lineTo(p1.dx, p1.dy);
      path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  _Segment _longestSegment(List<Offset> points) {
    _Segment best = _Segment(points[0], points[1]);
    double bestLen = best.length;
    for (int i = 1; i < points.length - 1; i++) {
      final _Segment seg = _Segment(points[i], points[i + 1]);
      if (seg.length > bestLen) {
        bestLen = seg.length;
        best = seg;
      }
    }
    return best;
  }

  /// Draws an arrowhead at [tip], oriented along [approach] — the
  /// direction of travel arriving at the tip. Using the actual final
  /// segment direction (rather than assuming purely horizontal/vertical)
  /// keeps the arrow correctly oriented even where a route's last leg
  /// isn't axis-aligned, e.g. a self-loop or a port offset from center.
  void _drawArrowHead(Canvas canvas, Offset tip, Offset approach, Color color) {
    const double size = 7.5;
    final double len = approach.distance;
    final Offset dir = len == 0 ? const Offset(0, 1) : approach / len;
    final Offset normal = Offset(-dir.dy, dir.dx);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeJoin = StrokeJoin.round;

    final Offset back = tip - dir * size;
    final Offset p1 = back + normal * (size * 0.42);
    final Offset p2 = back - normal * (size * 0.42);
    final Offset notch = tip - dir * (size * 0.45);

    // A slightly slimmer, closed triangle (versus a plain isoceles one)
    // reads as a lot cleaner/sharper at small sizes — closer to how
    // Mermaid/Claude draw arrowheads.
    final Path path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(notch.dx, notch.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashLength = 5;
    const double gapLength = 4;
    for (final ui.PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final double next = math.min(distance + (draw ? dashLength : gapLength), metric.length);
        if (draw) {
          canvas.drawPath(metric.extractPath(distance, next), paint);
        }
        distance = next;
        draw = !draw;
      }
    }
  }

  void _drawEdgeLabel(Canvas canvas, String text, Offset center) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(fontSize: 11, color: palette.edgeLabelText),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 140);

    final double w = painter.width + 12;
    final double h = painter.height + 7;

    // Nudge straight down, a chip-height at a time, until it clears every
    // label already placed this paint — a simple occupied-rect check
    // rather than full collision layout, but enough to keep two labels on
    // crossing/adjacent edges from landing on top of each other.
    Offset placeAt = center;
    Rect chip = Rect.fromCenter(center: placeAt, width: w, height: h);
    int attempts = 0;
    while (attempts < 6 && _labelRects.any((Rect r) => r.overlaps(chip))) {
      placeAt = Offset(placeAt.dx, placeAt.dy + h + 3);
      chip = Rect.fromCenter(center: placeAt, width: w, height: h);
      attempts++;
    }
    _labelRects.add(chip);

    final RRect chipRRect = RRect.fromRectAndRadius(chip, const Radius.circular(5));
    final Paint bg = Paint()..color = palette.edgeLabelBackground;
    final Paint chipBorder = Paint()
      ..color = palette.edgeColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(chipRRect, bg);
    canvas.drawRRect(chipRRect, chipBorder);
    painter.paint(canvas, Offset(chip.left + 6, chip.top + 3.5));
  }

  @override
  bool shouldRepaint(covariant _FlowchartPainter oldDelegate) {
    return oldDelegate.graph != graph || oldDelegate.palette != palette;
  }
}
