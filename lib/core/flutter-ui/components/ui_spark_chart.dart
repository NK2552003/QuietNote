import 'package:flutter/material.dart';

import 'ui_chart_base.dart';
import 'ui_common.dart';

/// Sparkline: no axes, no grid, no legend, compact height. Used inline in
/// tables, cards and list rows.
class UiSparkChart extends StatelessWidget {
  const UiSparkChart({
    super.key,
    required this.values,
    this.color,
    this.height,
    this.curved = true,
    this.filled = false,
    this.labels,
    this.valueFormatter,
  });

  /// Raw series values; labels are optional because a spark has no axis.
  final List<double> values;
  final Color? color;
  final double? height;
  final bool curved;
  final bool filled;
  final List<String>? labels;
  final UiValueFormatter? valueFormatter;

  @override
  Widget build(BuildContext context) => UiChart.spark(
        data: <UiChartPoint>[
          for (int i = 0; i < values.length; i++)
            UiChartPoint(
              label: labels != null && i < labels!.length ? labels![i] : '',
              values: <double>[values[i]],
            ),
        ],
        series: <UiChartSeries>[
          UiChartSeries(
            name: '',
            color: color,
            type: filled ? UiChartSeriesType.area : UiChartSeriesType.line,
          ),
        ],
        height: height,
        valueFormatter: valueFormatter,
        curved: curved,
      );
}
