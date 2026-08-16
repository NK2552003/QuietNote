import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders GFM tables as a **content-sized, horizontally scrollable** table.
///
/// flutter_markdown's own table path forces every column to one width: flex
/// columns squeeze wide tables into the viewport until they're unreadable, and
/// a `FixedColumnWidth` makes narrow columns waste space while still clipping
/// long cells.
///
/// This used to hand `Table` a `defaultColumnWidth: IntrinsicColumnWidth()`
/// inside a horizontal `SingleChildScrollView` — which reads as though it
/// should give every column its natural content width, but `Table` measures
/// `IntrinsicColumnWidth` by asking each cell's render object for its
/// max-intrinsic-width *before* the surrounding scroll view has resolved the
/// unbounded width it's offering, and unlike `pdf`'s `Table` (used for the
/// PDF export, where widths are plain numbers with no such ambiguity),
/// Flutter's `Table` silently falls back to dividing the available viewport
/// width evenly across columns when that measurement isn't reliable — which
/// is exactly the "every column squeezed to a third of the screen, text
/// wrapping onto a dozen lines" look this was meant to prevent.
///
/// So column widths are computed explicitly instead — same approach as the
/// PDF exporter: each column is sized from its longest cell text (with a
/// floor set by its longest unbroken word, so one long token never forces a
/// narrower wrap than it needs), clamped to a sensible min/max. Those are
/// plain numbers handed to `FixedColumnWidth`, so there's nothing left for
/// `Table` to fall back on — the table's total width reliably exceeds the
/// viewport for wide tables, and the horizontal scroll view actually scrolls.
///
/// Header styling, per-column alignment, borders and inline formatting inside
/// cells all match the shared stylesheet.
class ScrollableTableBuilder extends MarkdownElementBuilder {
  ScrollableTableBuilder({required this.styleSheet, required this.borderColor});

  final MarkdownStyleSheet styleSheet;
  final Color borderColor;

  /// Below this a column would be narrower than its own padding looks right at.
  static const double _minColumnWidth = 90;

  /// Long prose cells shouldn't stretch one column across three screens.
  static const double _maxColumnWidth = 320;

  /// Average glyph width as a fraction of font size, used to turn a
  /// character count into an estimated pixel width — the same heuristic
  /// [MarkdownPdfExporter] uses for its own column sizing.
  static const double _emFactor = 0.52;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'table') return null;
    return buildTable(element);
  }

  /// The actual table-widget construction, split out from
  /// [visitElementAfter] so it can be called directly — see
  /// [extractTableBlocks] in markdown_preview.dart, which parses and
  /// renders GFM tables itself rather than going through
  /// `MarkdownBody`'s `builders` dispatch for the `table` tag at all. That
  /// bypass exists because, in practice, this builder was never observed
  /// to run: registering it under `builders['table']` had no visible effect
  /// on a real table (same squeezed, non-scrolling result before and after
  /// substantial changes to the sizing logic below), which only makes
  /// sense if `MarkdownBody` isn't actually invoking a custom builder for
  /// `table` in the flutter_markdown version this app pins. Calling this
  /// method directly removes that uncertainty — nothing here depends on
  /// flutter_markdown choosing to hand the `table` element back to us.
  Widget? buildTable(md.Element element) {
    if (element.tag != 'table') return null;

    final List<md.Element> rows = <md.Element>[];
    for (final md.Node section in element.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      if (section.tag == 'thead' || section.tag == 'tbody') {
        rows.addAll(
          (section.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((md.Element e) => e.tag == 'tr'),
        );
      } else if (section.tag == 'tr') {
        rows.add(section);
      }
    }
    if (rows.isEmpty) return null;

    final int columns = rows
        .map((md.Element r) =>
            (r.children ?? const <md.Node>[]).whereType<md.Element>().length)
        .fold<int>(0, (int a, int b) => a > b ? a : b);
    if (columns == 0) return null;

    final EdgeInsets cellPadding = styleSheet.tableCellsPadding ??
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8);

    final double headSize = styleSheet.tableHead?.fontSize ?? 14;
    final double bodySize = styleSheet.tableBody?.fontSize ?? 14;
    final List<double> widths = _columnWidths(
      rows: rows,
      columns: columns,
      padding: cellPadding,
      headSize: headSize,
      bodySize: bodySize,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: styleSheet.tableBorder ??
              TableBorder.all(color: borderColor, width: 1),
          columnWidths: <int, TableColumnWidth>{
            for (int i = 0; i < columns; i++) i: FixedColumnWidth(widths[i]),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: <TableRow>[
            for (final md.Element row in rows)
              TableRow(
                decoration: _isHeaderRow(row)
                    ? BoxDecoration(color: borderColor.withValues(alpha: 0.18))
                    : null,
                children: <Widget>[
                  for (int i = 0; i < columns; i++)
                    _cell(_cellAt(row, i), cellPadding),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// One explicit pixel width per column: estimated from the longest cell
  /// text in that column (floored by its longest single word, so a long
  /// token like a URL still gets room to sit on one line up to the column
  /// cap), clamped to [_minColumnWidth]–[_maxColumnWidth].
  List<double> _columnWidths({
    required List<md.Element> rows,
    required int columns,
    required EdgeInsets padding,
    required double headSize,
    required double bodySize,
  }) {
    final List<int> longest = List<int>.filled(columns, 1);
    final List<int> longestWord = List<int>.filled(columns, 1);
    final List<bool> isHeaderCol = List<bool>.filled(columns, false);

    for (final md.Element row in rows) {
      final bool header = _isHeaderRow(row);
      for (int i = 0; i < columns; i++) {
        final md.Element? cell = _cellAt(row, i);
        if (header && cell?.tag == 'th') isHeaderCol[i] = true;
        final String text = (cell?.textContent ?? '').trim();
        if (text.length > longest[i]) longest[i] = text.length;
        for (final String word in text.split(RegExp(r'\s+'))) {
          if (word.length > longestWord[i]) longestWord[i] = word.length;
        }
      }
    }

    final double horizontalPad = padding.horizontal;
    return <double>[
      for (int i = 0; i < columns; i++)
        () {
          final double em =
              (isHeaderCol[i] ? headSize : bodySize) * _emFactor;
          final double wordFloor =
              (longestWord[i] * em + horizontalPad).clamp(
            _minColumnWidth,
            _maxColumnWidth,
          );
          return (longest[i] * em + horizontalPad).clamp(
            wordFloor,
            _maxColumnWidth,
          );
        }(),
    ];
  }

  static md.Element? _cellAt(md.Element row, int index) {
    final List<md.Element> cells =
        (row.children ?? const <md.Node>[]).whereType<md.Element>().toList();
    return index < cells.length ? cells[index] : null;
  }

  Widget _cell(md.Element? cell, EdgeInsets padding) {
    final bool header = cell?.tag == 'th';
    final TextStyle base = (header
            ? styleSheet.tableHead
            : styleSheet.tableBody) ??
        const TextStyle();
    return Padding(
      padding: padding,
      child: RichText(
        textAlign: header
            ? (styleSheet.tableHeadAlign ?? _align(cell))
            : _align(cell),
        text: TextSpan(children: _spans(cell?.children, base)),
      ),
    );
  }

  static bool _isHeaderRow(md.Element row) =>
      (row.children ?? const <md.Node>[])
          .whereType<md.Element>()
          .any((md.Element c) => c.tag == 'th');

  static TextAlign _align(md.Element? cell) {
    switch (cell?.attributes['style']) {
      case 'text-align: center;':
        return TextAlign.center;
      case 'text-align: right;':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  List<InlineSpan> _spans(List<md.Node>? nodes, TextStyle style) {
    final List<InlineSpan> spans = <InlineSpan>[];
    if (nodes == null) return spans;
    for (final md.Node node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: _unescape(node.text), style: style));
        continue;
      }
      if (node is! md.Element) continue;
      switch (node.tag) {
        case 'em':
          spans.addAll(_spans(node.children,
              style.merge(styleSheet.em).copyWith(fontStyle: FontStyle.italic)));
          break;
        case 'strong':
          spans.addAll(_spans(node.children,
              style.merge(styleSheet.strong).copyWith(fontWeight: FontWeight.w700)));
          break;
        case 'del':
          spans.addAll(_spans(node.children,
              style.copyWith(decoration: TextDecoration.lineThrough)));
          break;
        case 'code':
          spans.add(TextSpan(
            text: node.textContent,
            style: style.merge(styleSheet.code),
          ));
          break;
        case 'mark':
          spans.addAll(_spans(node.children,
              style.copyWith(backgroundColor: borderColor.withValues(alpha: 0.35))));
          break;
        case 'a':
          spans.addAll(_spans(node.children, style.merge(styleSheet.a)));
          break;
        case 'br':
          spans.add(const TextSpan(text: '\n'));
          break;
        default:
          spans.addAll(_spans(node.children, style));
      }
    }
    return spans;
  }

  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
