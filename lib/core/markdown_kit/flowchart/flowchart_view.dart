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
      nodeBorder: colors.border,
      nodeText: colors.foreground,
      decisionFill: colors.primary.withValues(alpha: 0.10),
      edgeColor: colors.foregroundMuted,
      edgeLabelBackground: colors.background,
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

class _FlowchartPainter extends CustomPainter {
  _FlowchartPainter({
    required this.graph,
    required this.palette,
    required this.labelStyle,
  });

  final FlowGraph graph;
  final FlowchartPalette palette;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    for (final FlowEdge edge in graph.edges) {
      final FlowNode? from = graph.nodes[edge.fromId];
      final FlowNode? to = graph.nodes[edge.toId];
      if (from == null || to == null || from == to) continue;
      _paintEdge(canvas, from, to, edge);
    }
    for (final FlowNode node in graph.nodes.values) {
      _paintNode(canvas, node);
    }
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
      ..strokeWidth = 1.3;

    switch (node.shape) {
      case FlowNodeShape.rect:
      case FlowNodeShape.subroutine:
        final RRect r = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, border);
        if (node.shape == FlowNodeShape.subroutine) {
          final double inset = 5;
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
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, border);
        break;
      case FlowNodeShape.stadium:
        final RRect r =
            RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, border);
        break;
      case FlowNodeShape.circle:
        final Offset center = rect.center;
        final double radius = math.min(rect.width, rect.height) / 2;
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

  void _paintEdge(Canvas canvas, FlowNode from, FlowNode to, FlowEdge edge) {
    final Rect a = Rect.fromLTWH(from.x, from.y, from.width, from.height);
    final Rect b = Rect.fromLTWH(to.x, to.y, to.width, to.height);

    final bool horizontal = graph.direction == FlowDirection.leftToRight ||
        graph.direction == FlowDirection.rightToLeft;
    final bool reversed = graph.direction == FlowDirection.bottomToTop ||
        graph.direction == FlowDirection.rightToLeft;

    Offset start;
    Offset end;
    if (horizontal) {
      final bool aBeforeB = reversed ? a.left > b.left : a.left < b.left;
      start = aBeforeB ? Offset(a.right, a.center.dy) : Offset(a.left, a.center.dy);
      end = aBeforeB ? Offset(b.left, b.center.dy) : Offset(b.right, b.center.dy);
    } else {
      final bool aBeforeB = reversed ? a.top > b.top : a.top < b.top;
      start = aBeforeB ? Offset(a.center.dx, a.bottom) : Offset(a.center.dx, a.top);
      end = aBeforeB ? Offset(b.center.dx, b.top) : Offset(b.center.dx, b.bottom);
    }

    final Paint linePaint = Paint()
      ..color = palette.edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge.style == FlowEdgeStyle.thick ? 2.4 : 1.4
      ..strokeCap = StrokeCap.round;

    final Path path = Path()..moveTo(start.dx, start.dy);
    // A gentle curve through a midpoint reads far better than a dead-straight
    // line once nodes are offset from each other within their rank.
    final Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final Offset c1 = horizontal
        ? Offset(mid.dx, start.dy)
        : Offset(start.dx, mid.dy);
    final Offset c2 = horizontal ? Offset(mid.dx, end.dy) : Offset(end.dx, mid.dy);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

    if (edge.style == FlowEdgeStyle.dashed) {
      _drawDashedPath(canvas, path, linePaint);
    } else {
      canvas.drawPath(path, linePaint);
    }

    if (edge.arrowEnd) _drawArrowHead(canvas, end, horizontal, reversed, linePaint.color);
    if (edge.arrowStart) _drawArrowHead(canvas, start, horizontal, !reversed, linePaint.color);

    if (edge.label != null && edge.label!.isNotEmpty) {
      _drawEdgeLabel(canvas, edge.label!, mid);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, bool horizontal, bool pointingForward, Color color) {
    const double size = 7;
    final Paint paint = Paint()..color = color..style = PaintingStyle.fill;
    final double dir = pointingForward ? 1 : -1;
    final Path path = Path();
    if (horizontal) {
      path
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - size * dir, tip.dy - size * 0.6)
        ..lineTo(tip.dx - size * dir, tip.dy + size * 0.6)
        ..close();
    } else {
      path
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - size * 0.6, tip.dy - size * dir)
        ..lineTo(tip.dx + size * 0.6, tip.dy - size * dir)
        ..close();
    }
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

    final Rect chip = Rect.fromCenter(
      center: center,
      width: painter.width + 10,
      height: painter.height + 6,
    );
    final Paint bg = Paint()..color = palette.edgeLabelBackground;
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(4)), bg);
    painter.paint(canvas, Offset(chip.left + 5, chip.top + 3));
  }

  @override
  bool shouldRepaint(covariant _FlowchartPainter oldDelegate) {
    return oldDelegate.graph != graph || oldDelegate.palette != palette;
  }
}
