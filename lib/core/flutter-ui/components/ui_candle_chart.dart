import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ui_theme.dart';
import '../theme/ui_tokens.dart';
import 'ui_common.dart';

/// A single OHLCV bar.
@immutable
class UiCandle {
  const UiCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  bool get bullish => close >= open;
}

/// Horizontal reference line drawn over the price pane (entry / stop / target).
@immutable
class UiPriceLine {
  const UiPriceLine({
    required this.price,
    required this.label,
    this.intent = UiIntent.primary,
    this.dashed = true,
  });

  final double price;
  final String label;
  final UiIntent intent;
  final bool dashed;
}

/// A marker pinned to a candle index (trade entry / exit annotation).
@immutable
class UiCandleMarker {
  const UiCandleMarker({
    required this.index,
    required this.label,
    this.intent = UiIntent.primary,
    this.above = true,
  });

  final int index;
  final String label;
  final UiIntent intent;
  final bool above;
}

/// Named overlay line computed from the candles (moving average etc.).
@immutable
class UiCandleOverlay {
  const UiCandleOverlay({
    required this.name,
    required this.values,
    this.color,
  });

  final String name;

  /// Same length as the candle list; use `double.nan` for gaps.
  final List<double> values;
  final Color? color;

  /// Simple moving average helper.
  static UiCandleOverlay sma(
    List<UiCandle> candles,
    int period, {
    Color? color,
  }) {
    final List<double> out = <double>[];
    double sum = 0;
    for (int i = 0; i < candles.length; i++) {
      sum += candles[i].close;
      if (i >= period) sum -= candles[i - period].close;
      out.add(i >= period - 1 ? sum / period : double.nan);
    }
    return UiCandleOverlay(name: 'MA$period', values: out, color: color);
  }
}

enum UiPriceChartType { candles, hollow, line, area }

/// Candlestick / OHLC price chart with an optional volume pane, moving-average
/// overlays, price lines, trade markers and a crosshair read-out.
///
/// Everything (colors, spacing, radii, type) resolves from [UiTheme].
class UiCandleChart extends StatefulWidget {
  const UiCandleChart({
    super.key,
    required this.candles,
    this.type = UiPriceChartType.candles,
    this.overlays = const <UiCandleOverlay>[],
    this.priceLines = const <UiPriceLine>[],
    this.markers = const <UiCandleMarker>[],
    this.height,
    this.showVolume = true,
    this.showGrid = true,
    this.interactive = true,
    this.priceFormatter,
    this.onHoverIndex,
  });

  final List<UiCandle> candles;
  final UiPriceChartType type;
  final List<UiCandleOverlay> overlays;
  final List<UiPriceLine> priceLines;
  final List<UiCandleMarker> markers;
  final double? height;
  final bool showVolume;
  final bool showGrid;
  final bool interactive;
  final UiValueFormatter? priceFormatter;
  final ValueChanged<int?>? onHoverIndex;

  @override
  State<UiCandleChart> createState() => _UiCandleChartState();
}

class _UiCandleChartState extends State<UiCandleChart> {
  int? _active;

  void _setActive(int? index) {
    if (_active == index) return;
    setState(() => _active = index);
    widget.onHoverIndex?.call(index);
  }

  String _fmt(num v) =>
      widget.priceFormatter?.call(v) ?? v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    final double height =
        widget.height ?? context.sz(theme.sizes.chartHeight);

    if (widget.candles.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No price data',
            style: context.uiText.caption
                .copyWith(color: theme.colors.foregroundMuted),
          ),
        ),
      );
    }

    final UiCandle? active =
        _active == null ? null : widget.candles[_active!.clamp(0, widget.candles.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _UiCandleReadout(candle: active ?? widget.candles.last, format: _fmt),
        SizedBox(height: context.sp(theme.spacing.sm)),
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) {
              void handle(Offset local) {
                if (!widget.interactive) return;
                final double w = c.maxWidth;
                final double step = w / widget.candles.length;
                final int i = (local.dx / step)
                    .floor()
                    .clamp(0, widget.candles.length - 1);
                _setActive(i);
              }

              final Widget painted = CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _UiCandlePainter(
                  candles: widget.candles,
                  type: widget.type,
                  overlays: widget.overlays,
                  priceLines: widget.priceLines,
                  markers: widget.markers,
                  colors: theme.colors,
                  showVolume: widget.showVolume,
                  showGrid: widget.showGrid,
                  activeIndex: _active,
                  labelStyle: context.uiText.caption
                      .copyWith(color: theme.colors.foregroundSubtle),
                  markerStyle: context.uiText.caption
                      .copyWith(color: theme.colors.foreground),
                  format: _fmt,
                  radius: context.sz(theme.radii.sm),
                ),
              );

              if (!widget.interactive) return painted;
              return MouseRegion(
                onHover: (PointerHoverEvent e) => handle(e.localPosition),
                onExit: (_) => _setActive(null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails d) => handle(d.localPosition),
                  onHorizontalDragUpdate: (DragUpdateDetails d) =>
                      handle(d.localPosition),
                  onHorizontalDragEnd: (_) => _setActive(null),
                  child: painted,
                ),
              );
            },
          ),
        ),
        if (widget.overlays.isNotEmpty) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.sm)),
          Wrap(
            spacing: context.sp(theme.spacing.md),
            runSpacing: context.sp(theme.spacing.xs),
            children: <Widget>[
              for (int i = 0; i < widget.overlays.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: context.sz(10),
                      height: context.sz(2),
                      color: widget.overlays[i].color ??
                          theme.colors.series[i % theme.colors.series.length],
                    ),
                    SizedBox(width: context.sp(theme.spacing.xs)),
                    Text(
                      widget.overlays[i].name,
                      style: context.uiText.caption
                          .copyWith(color: theme.colors.foregroundMuted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _UiCandleReadout extends StatelessWidget {
  const _UiCandleReadout({required this.candle, required this.format});

  final UiCandle candle;
  final String Function(num value) format;

  @override
  Widget build(BuildContext context) {
    final UiColors c = context.uiColors;
    final Color tint = candle.bullish ? c.bullish : c.bearish;
    Widget pair(String label, double value, {Color? color}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$label ',
              style: context.uiText.caption.copyWith(color: c.foregroundSubtle),
            ),
            Text(
              format(value),
              style: context.uiText.numeric
                  .copyWith(color: color ?? c.foreground, fontSize: context.uiText.caption.fontSize),
            ),
          ],
        );

    return Wrap(
      spacing: context.sp(context.uiSpace.md),
      runSpacing: context.sp(context.uiSpace.xs),
      children: <Widget>[
        pair('O', candle.open),
        pair('H', candle.high),
        pair('L', candle.low),
        pair('C', candle.close, color: tint),
        if (candle.volume > 0) pair('V', candle.volume),
      ],
    );
  }
}

class _UiCandlePainter extends CustomPainter {
  _UiCandlePainter({
    required this.candles,
    required this.type,
    required this.overlays,
    required this.priceLines,
    required this.markers,
    required this.colors,
    required this.showVolume,
    required this.showGrid,
    required this.activeIndex,
    required this.labelStyle,
    required this.markerStyle,
    required this.format,
    required this.radius,
  });

  final List<UiCandle> candles;
  final UiPriceChartType type;
  final List<UiCandleOverlay> overlays;
  final List<UiPriceLine> priceLines;
  final List<UiCandleMarker> markers;
  final UiColors colors;
  final bool showVolume;
  final bool showGrid;
  final int? activeIndex;
  final TextStyle labelStyle;
  final TextStyle markerStyle;
  final String Function(num value) format;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final double volumeH = showVolume ? size.height * 0.22 : 0;
    final double priceH = size.height - volumeH - (showVolume ? 6 : 0);

    double lo = double.infinity;
    double hi = -double.infinity;
    for (final UiCandle k in candles) {
      lo = math.min(lo, k.low);
      hi = math.max(hi, k.high);
    }
    for (final UiPriceLine l in priceLines) {
      lo = math.min(lo, l.price);
      hi = math.max(hi, l.price);
    }
    for (final UiCandleOverlay o in overlays) {
      for (final double v in o.values) {
        if (v.isNaN) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (hi <= lo) hi = lo + 1;
    final double pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;

    double y(double price) => priceH - ((price - lo) / (hi - lo)) * priceH;
    final double step = size.width / candles.length;
    final double bodyW = math.max(1.0, step * 0.62);

    // Grid
    if (showGrid) {
      final Paint grid = Paint()
        ..color = colors.border
        ..strokeWidth = 1;
      for (int i = 0; i <= 4; i++) {
        final double gy = priceH * i / 4;
        canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
        _label(canvas, format(hi - (hi - lo) * i / 4), Offset(4, gy + 2));
      }
    }

    // Volume pane
    if (showVolume && volumeH > 0) {
      double maxVol = 0;
      for (final UiCandle k in candles) {
        maxVol = math.max(maxVol, k.volume);
      }
      if (maxVol > 0) {
        final double top = size.height - volumeH;
        for (int i = 0; i < candles.length; i++) {
          final UiCandle k = candles[i];
          final double h = (k.volume / maxVol) * volumeH;
          final Paint p = Paint()
            ..color = (k.bullish ? colors.bullish : colors.bearish)
                .withValues(alpha: 0.35);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(i * step + (step - bodyW) / 2, top + volumeH - h,
                  bodyW, math.max(1, h)),
              Radius.circular(radius / 2),
            ),
            p,
          );
        }
      }
    }

    // Price series
    switch (type) {
      case UiPriceChartType.line:
      case UiPriceChartType.area:
        final Path path = Path();
        for (int i = 0; i < candles.length; i++) {
          final Offset pt = Offset(i * step + step / 2, y(candles[i].close));
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        if (type == UiPriceChartType.area) {
          final Path fill = Path.from(path)
            ..lineTo(size.width, priceH)
            ..lineTo(0, priceH)
            ..close();
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  colors.primary.withValues(alpha: 0.28),
                  colors.primary.withValues(alpha: 0.0),
                ],
              ).createShader(Rect.fromLTWH(0, 0, size.width, priceH)),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );
      case UiPriceChartType.candles:
      case UiPriceChartType.hollow:
        for (int i = 0; i < candles.length; i++) {
          final UiCandle k = candles[i];
          final Color tint = k.bullish ? colors.bullish : colors.bearish;
          final double cx = i * step + step / 2;
          final Paint wick = Paint()
            ..color = tint
            ..strokeWidth = math.max(1, bodyW * 0.14);
          canvas.drawLine(Offset(cx, y(k.high)), Offset(cx, y(k.low)), wick);

          final double top = y(math.max(k.open, k.close));
          final double bottom = y(math.min(k.open, k.close));
          final Rect body = Rect.fromLTRB(
            cx - bodyW / 2,
            top,
            cx + bodyW / 2,
            math.max(bottom, top + 1),
          );
          final bool hollow =
              type == UiPriceChartType.hollow && k.bullish;
          canvas.drawRRect(
            RRect.fromRectAndRadius(body, Radius.circular(radius / 2)),
            Paint()
              ..color = tint
              ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
              ..strokeWidth = 1.4,
          );
        }
    }

    // Overlays
    for (int oi = 0; oi < overlays.length; oi++) {
      final UiCandleOverlay o = overlays[oi];
      final Paint p = Paint()
        ..color = o.color ?? colors.series[oi % colors.series.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      final Path path = Path();
      bool started = false;
      for (int i = 0; i < o.values.length && i < candles.length; i++) {
        final double v = o.values[i];
        if (v.isNaN) continue;
        final Offset pt = Offset(i * step + step / 2, y(v));
        if (!started) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, p);
    }

    // Price lines
    for (final UiPriceLine line in priceLines) {
      final Color tint = _intentColor(line.intent);
      final double ly = y(line.price);
      final Paint p = Paint()
        ..color = tint
        ..strokeWidth = 1.2;
      if (line.dashed) {
        const double dash = 5;
        for (double x = 0; x < size.width; x += dash * 2) {
          canvas.drawLine(Offset(x, ly), Offset(x + dash, ly), p);
        }
      } else {
        canvas.drawLine(Offset(0, ly), Offset(size.width, ly), p);
      }
      _label(
        canvas,
        '${line.label} ${format(line.price)}',
        Offset(size.width - 4, ly - 14),
        style: markerStyle.copyWith(color: tint),
        alignRight: true,
      );
    }

    // Markers
    for (final UiCandleMarker m in markers) {
      if (m.index < 0 || m.index >= candles.length) continue;
      final UiCandle k = candles[m.index];
      final double cx = m.index * step + step / 2;
      final double my = m.above ? y(k.high) - 12 : y(k.low) + 12;
      final Color tint = _intentColor(m.intent);
      canvas.drawCircle(Offset(cx, my), 4, Paint()..color = tint);
      _label(canvas, m.label, Offset(cx + 6, my - 8),
          style: markerStyle.copyWith(color: tint));
    }

    // Crosshair
    if (activeIndex != null &&
        activeIndex! >= 0 &&
        activeIndex! < candles.length) {
      final double cx = activeIndex! * step + step / 2;
      final Paint p = Paint()
        ..color = colors.foregroundSubtle
        ..strokeWidth = 1;
      const double dash = 4;
      for (double yy = 0; yy < size.height; yy += dash * 2) {
        canvas.drawLine(Offset(cx, yy), Offset(cx, yy + dash), p);
      }
      final double cy = y(candles[activeIndex!].close);
      for (double xx = 0; xx < size.width; xx += dash * 2) {
        canvas.drawLine(Offset(xx, cy), Offset(xx + dash, cy), p);
      }
    }
  }

  Color _intentColor(UiIntent intent) {
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

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    TextStyle? style,
    bool alignRight = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style ?? labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, alignRight ? Offset(at.dx - tp.width, at.dy) : at);
  }

  @override
  bool shouldRepaint(covariant _UiCandlePainter old) =>
      old.candles != candles ||
      old.activeIndex != activeIndex ||
      old.type != type ||
      old.overlays != overlays ||
      old.priceLines != priceLines ||
      old.markers != markers ||
      old.colors != colors;
}
