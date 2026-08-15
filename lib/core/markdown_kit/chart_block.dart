import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// Renders a fenced ` ```chart ` code block. The block's content is a small
/// JSON spec, e.g.:
///
/// ```chart
/// {
///   "type": "bar",
///   "title": "Weekly study hours",
///   "labels": ["Mon", "Tue", "Wed", "Thu", "Fri"],
///   "series": [{"name": "Hours", "data": [2, 3, 1.5, 4, 2.5]}]
/// }
/// ```
///
/// `type` is one of `bar`, `line`, `area`, or `pie`. `series` may hold more
/// than one entry for grouped bars / multi-line charts; `pie` only reads
/// the first series, pairing each value with the matching `labels` entry.
/// Built entirely on the app's own [UiChart] / [UiDonutChart] widgets, so
/// it looks native and carries zero extra charting-library dependency.
class ChartBlock extends StatelessWidget {
  const ChartBlock({super.key, required this.spec});

  final String spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(spec);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      data = null;
    }

    if (data == null) {
      return _errorBox(context, "Couldn't read this chart — check the JSON.");
    }

    final String type = (data['type'] as String? ?? 'bar').toLowerCase().trim();
    final String? title = data['title'] as String?;
    final List<String> labels =
        (data['labels'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final List<dynamic> seriesRaw = (data['series'] as List?) ?? const [];

    final List<({String name, List<double> values})> series = [];
    for (int i = 0; i < seriesRaw.length; i++) {
      final entry = seriesRaw[i];
      if (entry is! Map) continue;
      final List<double> values = (entry['data'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const <double>[];
      series.add((name: entry['name']?.toString() ?? 'Series ${i + 1}', values: values));
    }

    if (labels.isEmpty || series.isEmpty) {
      return _errorBox(
        context,
        'Chart needs "labels" and at least one "series".',
      );
    }

    final Widget chart = type == 'pie'
        ? UiDonutChart(
            slices: [
              for (int i = 0; i < labels.length && i < series.first.values.length; i++)
                UiDonutSlice(label: labels[i], value: series.first.values[i].abs()),
            ],
          )
        : UiChart(
            data: [
              for (int i = 0; i < labels.length; i++)
                UiChartPoint(
                  label: labels[i],
                  values: [for (final s in series) i < s.values.length ? s.values[i] : 0],
                ),
            ],
            series: [
              for (final s in series)
                UiChartSeries(
                  name: s.name,
                  type: type == 'line'
                      ? UiChartSeriesType.line
                      : type == 'area'
                          ? UiChartSeriesType.area
                          : UiChartSeriesType.bar,
                  showDots: type == 'line',
                ),
            ],
            height: 220,
          );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insert_chart_outlined, size: 16, color: colors.foregroundMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (title != null && title.trim().isNotEmpty) ? title : 'Chart',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (type == 'pie') Center(child: chart) else chart,
        ],
      ),
    );
  }

  Widget _errorBox(BuildContext context, String message) {
    final colors = context.uiColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12.5, color: colors.foregroundMuted)),
          ),
        ],
      ),
    );
  }
}
