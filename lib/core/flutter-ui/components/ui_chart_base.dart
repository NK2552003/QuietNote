import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// A generic chart data point. Charts take data only — never styling.
class UiChartPoint {
  const UiChartPoint({required this.label, required this.values});

  /// X-axis label (date, time bucket, category).
  final String label;

  /// One value per series, in series order.
  final List<double> values;
}

class UiChartSeries {
  const UiChartSeries({
    required this.name,
    this.color,
    this.type = UiChartSeriesType.line,
    this.axis = UiChartAxis.left,
    this.lineGlow = false,
    this.fillOpacity,
    this.gradientColors,
    this.showDots = false,
  });

  final String name;
  final Color? color;
  final UiChartSeriesType type;
  final UiChartAxis axis;
  final bool lineGlow;
  final double? fillOpacity;
  final List<Color>? gradientColors;
  final bool showDots;
}

enum UiChartSeriesType { line, area, bar }

enum UiChartAxis { left, right }

/// Horizontal reference line drawn over a chart plot (target, average, alert
/// level). Generic counterpart of `UiPriceLine` for non-price charts.
@immutable
class UiChartThreshold {
  const UiChartThreshold({
    required this.value,
    required this.label,
    this.color,
    this.dashed = true,
  });

  final double value;
  final String label;
  final Color? color;
  final bool dashed;
}

/// Unified chart widget: Line, Area, Bar, Combo and Spark are all
/// configurations of this one component (no duplicated painting code).
///
/// Interaction is built in: drag/hover shows a crosshair with a themed value
/// tooltip, and legend entries toggle their series.
class UiChart extends StatefulWidget {
  const UiChart({
    super.key,
    required this.data,
    required this.series,
    this.height,
    this.showGrid = true,
    this.showAxisLabels = true,
    this.showLegend = true,
    this.valueFormatter,
    this.curved = true,
    this.minimal = false,
    this.interactive = true,
    this.toggleableLegend = true,
    this.stacked = false,
    this.glow = false,
    this.thresholds = const <UiChartThreshold>[],
  });

  /// Sparkline preset: no axes, no grid, no legend, short height.
  const UiChart.spark({
    super.key,
    required this.data,
    required this.series,
    this.height,
    this.valueFormatter,
    this.curved = true,
  })  : showGrid = false,
        showAxisLabels = false,
        showLegend = false,
        minimal = true,
        interactive = false,
        toggleableLegend = false,
        stacked = false,
        glow = false,
        thresholds = const <UiChartThreshold>[];

  final List<UiChartPoint> data;
  final List<UiChartSeries> series;
  final double? height;
  final bool showGrid;
  final bool showAxisLabels;
  final bool showLegend;
  final UiValueFormatter? valueFormatter;
  final bool curved;
  final bool minimal;

  /// Crosshair + value tooltip on hover/drag.
  final bool interactive;

  /// Tap a legend entry to hide/show that series.
  final bool toggleableLegend;

  /// Stack bar/area series cumulatively instead of overlaying them.
  final bool stacked;

  /// Soft blurred halo drawn beneath line/area strokes.
  final bool glow;

  /// Horizontal reference lines (targets, averages, alert levels).
  final List<UiChartThreshold> thresholds;

  @override
  State<UiChart> createState() => _UiChartState();
}

class _UiChartState extends State<UiChart> {
  final Set<int> _hidden = <int>{};
  int? _active;

  @override
  void didUpdateWidget(UiChart old) {
    super.didUpdateWidget(old);
    if (old.series.length != widget.series.length) _hidden.clear();
  }

  List<int> get _visibleIdx => <int>[
        for (int i = 0; i < widget.series.length; i++)
          if (!_hidden.contains(i)) i,
      ];

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final r = context.uiRes;
    final double h = context.sz(
      widget.height ??
          (widget.minimal
              ? theme.sizes.sparkHeight
              : r.pick<double>(
                  mobile: theme.sizes.chartHeight,
                  tablet: theme.sizes.chartHeight * 1.15,
                  desktop: theme.sizes.chartHeight * 1.3,
                )),
    );

    final List<Color> colors = <Color>[
      for (int i = 0; i < widget.series.length; i++)
        widget.series[i].color ??
            theme.colors.series[i % theme.colors.series.length],
    ];

    final List<int> shown = _visibleIdx;
    final bool axes = widget.showAxisLabels && !widget.minimal;
    final EdgeInsets pad = EdgeInsets.only(
      left: axes ? context.sz(40) : 0,
      bottom: axes ? context.sz(22) : 0,
      top: context.sz(4),
      right: context.sz(4),
    );
    final UiValueFormatter fmt = widget.valueFormatter ?? uiCompactNumber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.showLegend && widget.series.length > 1) ...<Widget>[
          Wrap(
            spacing: context.sp(theme.spacing.lg),
            runSpacing: context.sp(theme.spacing.xs),
            children: <Widget>[
              for (int i = 0; i < widget.series.length; i++)
                UiInteractive(
                  enabled: widget.toggleableLegend,
                  onTap: widget.toggleableLegend
                      ? () => setState(() {
                            if (_hidden.contains(i)) {
                              _hidden.remove(i);
                            } else if (_hidden.length <
                                widget.series.length - 1) {
                              _hidden.add(i);
                            }
                          })
                      : null,
                  builder: (BuildContext ctx, UiInteractiveState s) {
                    final bool off = _hidden.contains(i);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: ctx.sz(8),
                          height: ctx.sz(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: off ? theme.colors.border : colors[i],
                          ),
                        ),
                        SizedBox(width: ctx.sp(theme.spacing.xs)),
                        Text(
                          widget.series[i].name,
                          style: ctx.uiText.caption.copyWith(
                            color: off
                                ? theme.colors.foregroundSubtle
                                : theme.colors.foregroundMuted,
                            decoration:
                                off ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
          SizedBox(height: context.sp(theme.spacing.md)),
        ],
        SizedBox(
          height: h,
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) {
              final double w = c.maxWidth;
              void track(Offset local) {
                if (!widget.interactive || widget.data.isEmpty) return;
                final double plotW = w - pad.left - pad.right;
                final double t =
                    ((local.dx - pad.left) / (plotW <= 0 ? 1 : plotW))
                        .clamp(0.0, 1.0);
                final int i =
                    (t * (widget.data.length - 1)).round().clamp(
                          0,
                          widget.data.length - 1,
                        );
                if (i != _active) setState(() => _active = i);
              }

              final Widget paint = CustomPaint(
                size: Size(w, h),
                painter: _ChartPainter(
                  data: widget.data,
                  series: <UiChartSeries>[
                    for (final int i in shown) widget.series[i],
                  ],
                  seriesIndices: shown,
                  colors: <Color>[for (final int i in shown) colors[i]],
                  gridColor: theme.colors.border,
                  axisTextColor: theme.colors.foregroundSubtle,
                  axisTextStyle: ctx.uiText.caption,
                  showGrid: widget.showGrid && !widget.minimal,
                  showAxisLabels: axes,
                  curved: widget.curved,
                  formatter: fmt,
                  // Label density adapts to available width.
                  maxXLabels:
                      ctx.uiRes.pick<int>(mobile: 4, tablet: 6, desktop: 8),
                  padding: pad,
                  strokeWidth: ctx.sz(2),
                  activeIndex: widget.interactive ? _active : null,
                  crosshairColor: theme.colors.borderStrong,
                  surfaceColor: theme.colors.surface,
                  stacked: widget.stacked,
                  glow: widget.glow,
                  thresholds: widget.thresholds,
                  thresholdColor: theme.colors.warning,
                ),
              );

              if (!widget.interactive) return paint;

              return MouseRegion(
                onHover: (e) => track(e.localPosition),
                onExit: (_) => setState(() => _active = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails d) => track(d.localPosition),
                  onHorizontalDragUpdate: (DragUpdateDetails d) =>
                      track(d.localPosition),
                  onHorizontalDragEnd: (_) => setState(() => _active = null),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: paint),
                      if (_active != null && shown.isNotEmpty)
                        _Tooltip(
                          point: widget.data[_active!],
                          seriesIndices: shown,
                          series: widget.series,
                          colors: colors,
                          formatter: fmt,
                          alignRight: (_active! / (widget.data.length - 1)
                                  .clamp(1, 1 << 30)) >
                              0.6,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Crosshair value card. Purely presentational; every value comes from tokens.
class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.point,
    required this.seriesIndices,
    required this.series,
    required this.colors,
    required this.formatter,
    required this.alignRight,
  });

  final UiChartPoint point;
  final List<int> seriesIndices;
  final List<UiChartSeries> series;
  final List<Color> colors;
  final UiValueFormatter formatter;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Align(
      alignment: alignRight ? Alignment.topLeft : Alignment.topRight,
      child: Container(
        margin: EdgeInsets.all(context.sp(theme.spacing.xs)),
        padding: EdgeInsets.symmetric(
          horizontal: context.sp(theme.spacing.md),
          vertical: context.sp(theme.spacing.xs),
        ),
        decoration: BoxDecoration(
          color: theme.colors.surface,
          borderRadius: context.radius(theme.radii.md),
          border: Border.all(
            color: theme.colors.border,
            width: theme.borders.hairline,
          ),
          boxShadow: theme.shadows.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (point.label.isNotEmpty)
              Text(
                point.label,
                style: context.uiText.caption
                    .copyWith(color: theme.colors.foregroundMuted),
              ),
            for (final int i in seriesIndices)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: context.sz(6),
                    height: context.sz(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors[i],
                    ),
                  ),
                  SizedBox(width: context.sp(theme.spacing.xs)),
                  Text(
                    series[i].name.isEmpty ? '' : '${series[i].name}  ',
                    style: context.uiText.caption
                        .copyWith(color: theme.colors.foregroundMuted),
                  ),
                  Text(
                    formatter(
                      i < point.values.length ? point.values[i] : 0,
                    ),
                    style: context.uiText.numeric
                        .copyWith(color: theme.colors.foreground),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.data,
    required this.series,
    required this.colors,
    required this.gridColor,
    required this.axisTextColor,
    required this.axisTextStyle,
    required this.showGrid,
    required this.showAxisLabels,
    required this.curved,
    required this.formatter,
    required this.maxXLabels,
    required this.padding,
    required this.strokeWidth,
    this.seriesIndices,
    this.activeIndex,
    this.crosshairColor,
    this.surfaceColor,
    this.stacked = false,
    this.glow = false,
    this.thresholds = const <UiChartThreshold>[],
    this.thresholdColor,
  });

  final List<UiChartPoint> data;
  final List<UiChartSeries> series;

  /// Maps each painted series back to its column in [UiChartPoint.values],
  /// so hiding a series never shifts the remaining ones.
  final List<int>? seriesIndices;
  final List<Color> colors;
  final Color gridColor;
  final Color axisTextColor;
  final TextStyle axisTextStyle;
  final bool showGrid;
  final bool showAxisLabels;
  final bool curved;
  final UiValueFormatter formatter;
  final int maxXLabels;
  final EdgeInsets padding;
  final double strokeWidth;
  final int? activeIndex;
  final Color? crosshairColor;
  final Color? surfaceColor;
  final bool stacked;
  final bool glow;
  final List<UiChartThreshold> thresholds;
  final Color? thresholdColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || series.isEmpty) return;
    final Rect plot = Rect.fromLTRB(
      padding.left,
      padding.top,
      size.width - padding.right,
      size.height - padding.bottom,
    );

    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final UiChartPoint p in data) {
      for (final double v in p.values) {
        minY = math.min(minY, v);
        maxY = math.max(maxY, v);
      }
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    // Include zero baseline for bar series.
    if (series.any((UiChartSeries s) => s.type == UiChartSeriesType.bar)) {
      minY = math.min(minY, 0);
    }

    double yOf(double v) =>
        plot.bottom - (v - minY) / (maxY - minY) * plot.height;
    double xOf(int i) => data.length == 1
        ? plot.center.dx
        : plot.left + i / (data.length - 1) * plot.width;

    if (showGrid) {
      final Paint grid = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      for (int i = 0; i <= 4; i++) {
        final double y = plot.top + plot.height * i / 4;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      }
    }

    if (showAxisLabels) {
      for (int i = 0; i <= 4; i++) {
        final double y = plot.bottom - plot.height * i / 4;
        final double value = minY + (maxY - minY) * i / 4;
        _text(canvas, formatter(value), Offset(0, y - 6), plot.left - 4,
            TextAlign.right);
      }
      final int step = math.max(1, (data.length / maxXLabels).ceil());
      for (int i = 0; i < data.length; i += step) {
        _text(
          canvas,
          data[i].label,
          Offset(xOf(i) - 24, plot.bottom + 4),
          48,
          TextAlign.center,
        );
      }
    }

    // Bars first so lines draw above them.
    final List<int> barIdx = <int>[
      for (int i = 0; i < series.length; i++)
        if (series[i].type == UiChartSeriesType.bar) i,
    ];
    if (barIdx.isNotEmpty) {
      final double slot = plot.width / data.length;
      if (stacked && barIdx.length > 1) {
        final double barW = slot * 0.6;
        for (int i = 0; i < data.length; i++) {
          double posCum = 0;
          double negCum = 0;
          final double cx = plot.left + slot * (i + 0.5);
          for (int b = 0; b < barIdx.length; b++) {
            final double v = _value(i, barIdx[b]);
            final double base = v >= 0 ? posCum : negCum;
            final double top = base + v;
            if (v >= 0) {
              posCum = top;
            } else {
              negCum = top;
            }
            final Rect bar = Rect.fromLTRB(
              cx - barW / 2,
              yOf(math.max(base, top)),
              cx + barW / 2,
              yOf(math.min(base, top)),
            );
            canvas.drawRect(bar, Paint()..color = colors[barIdx[b]]);
          }
        }
      } else {
        final double barW = slot * 0.6 / barIdx.length;
        for (int b = 0; b < barIdx.length; b++) {
          final Paint paint = Paint()..color = colors[barIdx[b]];
          for (int i = 0; i < data.length; i++) {
            final double v = _value(i, barIdx[b]);
            final double cx = plot.left + slot * (i + 0.5);
            final double left = cx - (barIdx.length * barW) / 2 + b * barW;
            final Rect bar = Rect.fromLTRB(
              left,
              math.min(yOf(v), yOf(0)),
              left + barW * 0.9,
              math.max(yOf(v), yOf(0)),
            );
            canvas.drawRRect(
              RRect.fromRectAndCorners(
                bar,
                topLeft: Radius.circular(strokeWidth),
                topRight: Radius.circular(strokeWidth),
              ),
              paint,
            );
          }
        }
      }
    }

    // Reference threshold lines (targets, averages, alerts).
    for (final UiChartThreshold t in thresholds) {
      final double ty = yOf(t.value);
      final Color tint = t.color ?? thresholdColor ?? gridColor;
      final Paint tp = Paint()
        ..color = tint
        ..strokeWidth = 1.2;
      if (t.dashed) {
        const double dash = 5;
        for (double x = plot.left; x < plot.right; x += dash * 2) {
          canvas.drawLine(
              Offset(x, ty), Offset(math.min(x + dash, plot.right), ty), tp);
        }
      } else {
        canvas.drawLine(Offset(plot.left, ty), Offset(plot.right, ty), tp);
      }
      _text(canvas, t.label, Offset(plot.right - 60, ty - 14), 60,
          TextAlign.right);
    }

    final List<double> areaBase = List<double>.filled(data.length, 0);
    for (int s = 0; s < series.length; s++) {
      if (series[s].type == UiChartSeriesType.bar) continue;
      final bool isArea = series[s].type == UiChartSeriesType.area;
      final bool doStack = stacked && isArea;
      double topOf(int i) => doStack ? areaBase[i] + _value(i, s) : _value(i, s);

      final Path path = Path();
      for (int i = 0; i < data.length; i++) {
        final Offset p = Offset(xOf(i), yOf(topOf(i)));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else if (curved) {
          final Offset prev = Offset(xOf(i - 1), yOf(topOf(i - 1)));
          final double midX = (prev.dx + p.dx) / 2;
          path.cubicTo(midX, prev.dy, midX, p.dy, p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }

      if (isArea) {
        final Path fill = Path();
        if (doStack) {
          for (int i = 0; i < data.length; i++) {
            final Offset o = Offset(xOf(i), yOf(topOf(i)));
            i == 0 ? fill.moveTo(o.dx, o.dy) : fill.lineTo(o.dx, o.dy);
          }
          for (int i = data.length - 1; i >= 0; i--) {
            final Offset o = Offset(xOf(i), yOf(areaBase[i]));
            fill.lineTo(o.dx, o.dy);
          }
          fill.close();
        } else {
          fill.addPath(path, Offset.zero);
          fill.lineTo(plot.right, plot.bottom);
          fill.lineTo(plot.left, plot.bottom);
          fill.close();
        }
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors[s].withValues(alpha: 0.30),
                colors[s].withValues(alpha: 0.02),
              ],
            ).createShader(plot),
        );
      }

      if (glow) {
        canvas.drawPath(
          path,
          Paint()
            ..color = colors[s].withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 3
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 1.6),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = colors[s]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

      if (doStack) {
        for (int i = 0; i < data.length; i++) {
          areaBase[i] += _value(i, s);
        }
      }
    }

    _drawCrosshair(canvas, plot, minY, maxY);
  }

  double _value(int pointIndex, int seriesIndex) {
    final List<double> vals = data[pointIndex].values;
    final int col = seriesIndices == null || seriesIndex >= seriesIndices!.length
        ? seriesIndex
        : seriesIndices![seriesIndex];
    return col < vals.length ? vals[col] : 0;
  }

  /// Vertical crosshair + markers for the hovered point.
  void _drawCrosshair(Canvas canvas, Rect plot, double minY, double maxY) {
    final int? i = activeIndex;
    if (i == null || i < 0 || i >= data.length || crosshairColor == null) return;
    final double dx = data.length == 1
        ? plot.center.dx
        : plot.left + plot.width * (i / (data.length - 1));
    canvas.drawLine(
      Offset(dx, plot.top),
      Offset(dx, plot.bottom),
      Paint()
        ..color = crosshairColor!
        ..strokeWidth = strokeWidth / 2,
    );
    final double span = (maxY - minY) == 0 ? 1 : (maxY - minY);
    for (int s = 0; s < series.length; s++) {
      if (series[s].type == UiChartSeriesType.bar) continue;
      final double dy =
          plot.bottom - ((_value(i, s) - minY) / span) * plot.height;
      canvas
        ..drawCircle(
          Offset(dx, dy),
          strokeWidth * 2,
          Paint()..color = surfaceColor ?? gridColor,
        )
        ..drawCircle(
          Offset(dx, dy),
          strokeWidth * 2,
          Paint()
            ..color = colors[s]
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth,
        );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    TextAlign align,
  ) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: axisTextStyle.copyWith(color: axisTextColor),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.data != data ||
      old.series != series ||
      old.colors != colors ||
      old.activeIndex != activeIndex;
}
