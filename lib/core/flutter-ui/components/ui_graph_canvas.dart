import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import '../theme/ui_tokens.dart';
import 'ui_common.dart';

/// A node in a knowledge/relationship graph (journal entry, strategy, ticker).
@immutable
class UiGraphNode {
  const UiGraphNode({
    required this.id,
    required this.label,
    this.group,
    this.intent = UiIntent.primary,
    this.weight = 1,
    this.icon,
  });

  final String id;
  final String label;
  final String? group;
  final UiIntent intent;

  /// Relative node size (1 = default).
  final double weight;
  final IconData? icon;
}

@immutable
class UiGraphEdge {
  const UiGraphEdge({
    required this.from,
    required this.to,
    this.label,
    this.strength = 1,
  });

  final String from;
  final String to;
  final String? label;
  final double strength;
}

/// Pannable / zoomable node-link canvas with a deterministic force-directed
/// layout (seeded, so the same graph always renders the same way).
class UiGraphCanvas extends StatefulWidget {
  const UiGraphCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    this.selectedId,
    this.onSelect,
    this.height,
    this.iterations = 260,
  });

  final List<UiGraphNode> nodes;
  final List<UiGraphEdge> edges;
  final String? selectedId;
  final ValueChanged<UiGraphNode?>? onSelect;
  final double? height;
  final int iterations;

  @override
  State<UiGraphCanvas> createState() => _UiGraphCanvasState();
}

class _UiGraphCanvasState extends State<UiGraphCanvas> {
  final TransformationController _controller = TransformationController();
  Map<String, Offset> _positions = <String, Offset>{};
  Size _lastSize = Size.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UiGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes || oldWidget.edges != widget.edges) {
      _positions = <String, Offset>{};
    }
  }

  Map<String, Offset> _layout(Size size) {
    final math.Random rnd = math.Random(7);
    final Map<String, Offset> pos = <String, Offset>{
      for (int i = 0; i < widget.nodes.length; i++)
        widget.nodes[i].id: Offset(
          size.width / 2 +
              math.cos(i * 2 * math.pi / math.max(1, widget.nodes.length)) *
                  size.width /
                  3.2 +
              rnd.nextDouble() * 6,
          size.height / 2 +
              math.sin(i * 2 * math.pi / math.max(1, widget.nodes.length)) *
                  size.height /
                  3.2 +
              rnd.nextDouble() * 6,
        ),
    };

    final double k = math.sqrt(
      (size.width * size.height) / math.max(1, widget.nodes.length),
    );
    for (int step = 0; step < widget.iterations; step++) {
      final double temp = k * (1 - step / widget.iterations) * 0.08;
      final Map<String, Offset> disp = <String, Offset>{
        for (final UiGraphNode n in widget.nodes) n.id: Offset.zero,
      };

      for (int i = 0; i < widget.nodes.length; i++) {
        for (int j = i + 1; j < widget.nodes.length; j++) {
          final String a = widget.nodes[i].id;
          final String b = widget.nodes[j].id;
          Offset delta = pos[a]! - pos[b]!;
          double dist = delta.distance;
          if (dist < 0.01) {
            delta = const Offset(0.5, 0.5);
            dist = delta.distance;
          }
          final Offset force = delta / dist * (k * k / dist);
          disp[a] = disp[a]! + force;
          disp[b] = disp[b]! - force;
        }
      }

      for (final UiGraphEdge e in widget.edges) {
        final Offset? pa = pos[e.from];
        final Offset? pb = pos[e.to];
        if (pa == null || pb == null) continue;
        final Offset delta = pa - pb;
        final double dist = math.max(0.01, delta.distance);
        final Offset force = delta / dist * (dist * dist / k) * e.strength;
        disp[e.from] = disp[e.from]! - force;
        disp[e.to] = disp[e.to]! + force;
      }

      for (final UiGraphNode n in widget.nodes) {
        final Offset d = disp[n.id]!;
        final double dist = math.max(0.01, d.distance);
        final Offset move = d / dist * math.min(dist, temp);
        final Offset next = pos[n.id]! + move;
        pos[n.id] = Offset(
          next.dx.clamp(40.0, math.max(41.0, size.width - 40)),
          next.dy.clamp(30.0, math.max(31.0, size.height - 30)),
        );
      }
    }
    return pos;
  }

  double _nodeRadius(BuildContext context, UiGraphNode n) =>
      context.sz(14) * (0.8 + n.weight.clamp(0.5, 3) * 0.25);

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    final double height = widget.height ?? context.sz(360);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints box) {
          final Size size = Size(box.maxWidth, box.maxHeight);
          if (_positions.isEmpty || _lastSize != size) {
            _lastSize = size;
            _positions = _layout(size);
          }
          return ClipRRect(
            borderRadius: ctx.radius(theme.radii.xl),
            child: Container(
              color: theme.colors.surfaceMuted,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.5,
                maxScale: 3,
                boundaryMargin: EdgeInsets.all(ctx.sz(120)),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails d) {
                    UiGraphNode? hit;
                    for (final UiGraphNode n in widget.nodes) {
                      final Offset p = _positions[n.id]!;
                      if ((p - d.localPosition).distance <=
                          _nodeRadius(ctx, n) + 6) {
                        hit = n;
                        break;
                      }
                    }
                    widget.onSelect?.call(hit);
                  },
                  child: CustomPaint(
                    size: size,
                    painter: _UiGraphPainter(
                      nodes: widget.nodes,
                      edges: widget.edges,
                      positions: _positions,
                      colors: theme.colors,
                      selectedId: widget.selectedId,
                      labelStyle: ctx.uiText.caption
                          .copyWith(color: theme.colors.foreground),
                      radiusOf: (UiGraphNode n) => _nodeRadius(ctx, n),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UiGraphPainter extends CustomPainter {
  _UiGraphPainter({
    required this.nodes,
    required this.edges,
    required this.positions,
    required this.colors,
    required this.selectedId,
    required this.labelStyle,
    required this.radiusOf,
  });

  final List<UiGraphNode> nodes;
  final List<UiGraphEdge> edges;
  final Map<String, Offset> positions;
  final UiColors colors;
  final String? selectedId;
  final TextStyle labelStyle;
  final double Function(UiGraphNode node) radiusOf;

  Color _tint(UiIntent intent) {
    switch (intent) {
      case UiIntent.neutral:
        return colors.foregroundMuted;
      case UiIntent.primary:
        return colors.primary;
      case UiIntent.bullish:
      case UiIntent.success:
        return colors.bullish;
      case UiIntent.bearish:
      case UiIntent.danger:
        return colors.bearish;
      case UiIntent.warning:
        return colors.warning;
      case UiIntent.info:
        return colors.info;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint edgePaint = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = 1.2;

    for (final UiGraphEdge e in edges) {
      final Offset? a = positions[e.from];
      final Offset? b = positions[e.to];
      if (a == null || b == null) continue;
      final bool active =
          selectedId != null && (e.from == selectedId || e.to == selectedId);
      canvas.drawLine(
        a,
        b,
        active
            ? (Paint()
              ..color = colors.primary
              ..strokeWidth = 2)
            : edgePaint,
      );
    }

    for (final UiGraphNode n in nodes) {
      final Offset p = positions[n.id]!;
      final double r = radiusOf(n);
      final Color tint = _tint(n.intent);
      final bool selected = n.id == selectedId;
      canvas.drawCircle(
        p,
        r + (selected ? 4 : 0),
        Paint()..color = tint.withValues(alpha: selected ? 0.28 : 0.16),
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = tint
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.4 : 1.4,
      );
      final TextPainter tp = TextPainter(
        text: TextSpan(text: n.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 110);
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + r + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _UiGraphPainter old) =>
      old.positions != positions ||
      old.selectedId != selectedId ||
      old.nodes != nodes ||
      old.edges != edges;
}

/// Legend for a graph canvas: one swatch per group.
class UiGraphLegend extends StatelessWidget {
  const UiGraphLegend({super.key, required this.entries, this.vertical = true});

  final Map<String, UiIntent> entries;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    final List<Widget> items = <Widget>[
      for (final MapEntry<String, UiIntent> e in entries.entries)
        Padding(
          padding: EdgeInsets.only(
            bottom: vertical ? context.sp(theme.spacing.sm) : 0,
            right: vertical ? 0 : context.sp(theme.spacing.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: context.sz(10),
                height: context.sz(10),
                decoration: BoxDecoration(
                  color: e.value.color(context),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: context.sp(theme.spacing.xs)),
              Text(
                e.key,
                style: context.uiText.caption
                    .copyWith(color: theme.colors.foregroundMuted),
              ),
            ],
          ),
        ),
    ];
    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: items,
          )
        : Wrap(children: items);
  }
}
