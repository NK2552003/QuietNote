import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_checkbox.dart';
import 'ui_common.dart';
import 'ui_skeleton.dart';

class UiTableColumn<T> {
  const UiTableColumn({
    required this.header,
    required this.cell,
    this.numeric = false,
    this.flex = 1,
    this.width,
    this.hideBelow = UiTableVisibility.always,
    this.compare,
  });

  final String header;
  final Widget Function(BuildContext context, T row) cell;
  final bool numeric;
  final int flex;
  final double? width;

  /// Progressive disclosure: drop low-priority columns on small screens.
  final UiTableVisibility hideBelow;

  /// Provide a comparator to make the column sortable by tapping its header.
  final int Function(T a, T b)? compare;
}

enum UiTableVisibility { always, tabletUp, desktopUp }

/// Responsive data table. On phones it can collapse into stacked cards so the
/// same column definitions serve every screen size.
///
/// Sorting (any column with a `compare`) and pagination (`pageSize`) are
/// handled internally; pass [onSort] to observe changes or [sortColumn] /
/// [sortAscending] to drive sorting from outside (e.g. server-side sorting).
class UiTable<T> extends StatefulWidget {
  const UiTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.stackOnMobile = false,
    this.emptyLabel = 'No data',
    this.pageSize,
    this.onSort,
    this.sortColumn,
    this.sortAscending,
    this.footer,
    this.loading = false,
    this.errorText,
    this.selectable = false,
    this.selectedRows,
    this.onSelectionChanged,
    this.expandableWhen,
    this.expandedBuilder,
    this.stickyHeader = false,
    this.maxBodyHeight,
    this.density = UiDensity.comfortable,
  });

  final List<UiTableColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final bool stackOnMobile;
  final String emptyLabel;

  /// Rows per page. Null disables pagination.
  final int? pageSize;

  /// Called with the column index and direction whenever sorting changes.
  final void Function(int columnIndex, bool ascending)? onSort;

  /// Controlled sort state. When provided, rows are assumed pre-sorted.
  final int? sortColumn;
  final bool? sortAscending;

  /// Optional footer row (totals, summaries).
  final Widget? footer;

  /// Shows skeleton rows instead of data while a fetch is in flight.
  final bool loading;

  /// When set, replaces the table body with an error message.
  final String? errorText;

  /// Renders a leading checkbox column and enables multi-row selection.
  final bool selectable;
  final Set<T>? selectedRows;
  final ValueChanged<Set<T>>? onSelectionChanged;

  /// Renders a leading disclosure chevron; rows for which this returns true
  /// can be expanded to reveal [expandedBuilder] content beneath them.
  final bool Function(T row)? expandableWhen;
  final Widget Function(BuildContext context, T row)? expandedBuilder;

  /// Keeps the header visible while the body scrolls within [maxBodyHeight].
  final bool stickyHeader;
  final double? maxBodyHeight;

  /// Row padding density.
  final UiDensity density;

  @override
  State<UiTable<T>> createState() => _UiTableState<T>();
}

class _UiTableState<T> extends State<UiTable<T>> {
  int? _sortCol;
  bool _asc = true;
  int _page = 0;
  final Set<T> _expanded = <T>{};

  Set<T> get _selected => widget.selectedRows ?? const <Never>{};

  bool get _controlled => widget.sortColumn != null;
  int? get _activeSortCol => _controlled ? widget.sortColumn : _sortCol;
  bool get _activeAsc => _controlled ? (widget.sortAscending ?? true) : _asc;

  @override
  void didUpdateWidget(UiTable<T> old) {
    super.didUpdateWidget(old);
    if (old.rows.length != widget.rows.length) _page = 0;
  }

  List<UiTableColumn<T>> _visible(BuildContext context) {
    final r = context.uiRes;
    return widget.columns.where((UiTableColumn<T> c) {
      switch (c.hideBelow) {
        case UiTableVisibility.always:
          return true;
        case UiTableVisibility.tabletUp:
          return !r.isMobile;
        case UiTableVisibility.desktopUp:
          return r.isDesktop;
      }
    }).toList();
  }

  void _toggleSort(int columnIndex) {
    final bool asc = _activeSortCol == columnIndex ? !_activeAsc : true;
    if (!_controlled) {
      setState(() {
        _sortCol = columnIndex;
        _asc = asc;
        _page = 0;
      });
    }
    widget.onSort?.call(columnIndex, asc);
  }

  List<T> get _sorted {
    final int? col = _activeSortCol;
    if (_controlled || col == null || col >= widget.columns.length) {
      return widget.rows;
    }
    final int Function(T, T)? cmp = widget.columns[col].compare;
    if (cmp == null) return widget.rows;
    final List<T> out = List<T>.of(widget.rows)..sort(cmp);
    return _activeAsc ? out : out.reversed.toList();
  }

  int get _pageCount {
    final int? size = widget.pageSize;
    if (size == null || size <= 0) return 1;
    return (widget.rows.length / size).ceil().clamp(1, 1 << 30);
  }

  List<T> _paged(List<T> source) {
    final int? size = widget.pageSize;
    if (size == null || size <= 0) return source;
    final int start = (_page * size).clamp(0, source.length);
    return source.sublist(start, (start + size).clamp(0, source.length));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double densityPad = widget.density.factor;
    if (widget.errorText != null) {
      return Padding(
        padding: EdgeInsets.all(context.sp(theme.spacing.xl)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline,
                  color: theme.colors.bearish, size: context.sz(theme.sizes.iconLg)),
              SizedBox(height: context.sp(theme.spacing.sm)),
              Text(
                widget.errorText!,
                style: context.uiText.body
                    .copyWith(color: theme.colors.foregroundMuted),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.loading) {
      return Column(
        children: <Widget>[
          for (int i = 0; i < (widget.pageSize ?? 5).clamp(3, 8); i++)
            Padding(
              padding: EdgeInsets.only(bottom: context.sp(theme.spacing.sm)),
              child: UiSkeleton(
                  width: double.infinity,
                  height: theme.sizes.controlHeightMd),
            ),
        ],
      );
    }
    if (widget.rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(context.sp(theme.spacing.xl)),
        child: Center(
          child: Text(
            widget.emptyLabel,
            style: context.uiText.body
                .copyWith(color: theme.colors.foregroundSubtle),
          ),
        ),
      );
    }

    final List<T> visibleRows = _paged(_sorted);

    if (widget.stackOnMobile && context.uiRes.isMobile) {
      return Column(
        children: <Widget>[
          for (final T row in visibleRows)
            UiInteractive(
              enabled: widget.onRowTap != null,
              onTap:
                  widget.onRowTap == null ? null : () => widget.onRowTap!(row),
              builder: (BuildContext ctx, UiInteractiveState s) => Container(
                margin: EdgeInsets.only(bottom: ctx.sp(theme.spacing.sm)),
                padding: EdgeInsets.all(ctx.sp(theme.spacing.lg)),
                decoration: BoxDecoration(
                  color: s.hovered
                      ? theme.colors.surfaceMuted
                      : theme.colors.surface,
                  borderRadius: ctx.radius(theme.radii.lg),
                  border: Border.all(
                    color: theme.colors.border,
                    width: theme.borders.hairline,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    for (final UiTableColumn<T> col in widget.columns)
                      Padding(
                        padding:
                            EdgeInsets.only(bottom: ctx.sp(theme.spacing.xs)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                col.header,
                                style: ctx.uiText.caption.copyWith(
                                  color: theme.colors.foregroundMuted,
                                ),
                              ),
                            ),
                            Flexible(child: col.cell(ctx, row)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (widget.footer != null) widget.footer!,
          if (widget.pageSize != null) _pager(context),
        ],
      );
    }

    final List<UiTableColumn<T>> cols = _visible(context);

    final Widget headerRow = Container(
      color: theme.colors.surfaceMuted,
      padding: EdgeInsets.symmetric(
        horizontal: context.sp(theme.spacing.lg),
        vertical: context.sp(theme.spacing.md),
      ),
      child: Row(
        children: <Widget>[
          if (widget.selectable)
            SizedBox(
              width: context.sz(theme.sizes.controlHeightXs),
              child: UiCheckbox(
                value: visibleRows.isNotEmpty &&
                    visibleRows.every(_selected.contains),
                onChanged: (bool v) => widget.onSelectionChanged
                    ?.call(v ? <T>{..._selected, ...visibleRows} : <T>{}),
              ),
            ),
          if (widget.expandableWhen != null)
            SizedBox(width: context.sz(theme.sizes.controlHeightXs)),
          for (final UiTableColumn<T> col in cols)
            _cellWrap(col, _headerCell(context, col)),
        ],
      ),
    );

    final List<Widget> bodyRows = <Widget>[
      for (int i = 0; i < visibleRows.length; i++)
        Column(
          children: <Widget>[
            UiInteractive(
              enabled: widget.onRowTap != null,
              onTap: widget.onRowTap == null
                  ? null
                  : () => widget.onRowTap!(visibleRows[i]),
              builder: (BuildContext ctx, UiInteractiveState s) => Container(
                decoration: BoxDecoration(
                  color: s.hovered
                      ? theme.colors.surfaceHover
                      : theme.colors.surface,
                  border: Border(
                    top: BorderSide(
                      color: theme.colors.border,
                      width: theme.borders.hairline,
                    ),
                  ),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: ctx.sp(theme.spacing.lg),
                  vertical: ctx.sp(theme.spacing.md) * densityPad,
                ),
                child: Row(
                  children: <Widget>[
                    if (widget.selectable)
                      SizedBox(
                        width: ctx.sz(theme.sizes.controlHeightXs),
                        child: UiCheckbox(
                          value: _selected.contains(visibleRows[i]),
                          onChanged: (bool v) {
                            final Set<T> next = <T>{..._selected};
                            v
                                ? next.add(visibleRows[i])
                                : next.remove(visibleRows[i]);
                            widget.onSelectionChanged?.call(next);
                          },
                        ),
                      ),
                    if (widget.expandableWhen != null)
                      SizedBox(
                        width: ctx.sz(theme.sizes.controlHeightXs),
                        child: widget.expandableWhen!(visibleRows[i])
                            ? UiInteractive(
                                onTap: () => setState(() =>
                                    _expanded.contains(visibleRows[i])
                                        ? _expanded
                                            .remove(visibleRows[i])
                                        : _expanded
                                            .add(visibleRows[i])),
                                builder: (BuildContext c, _) => Icon(
                                  _expanded.contains(visibleRows[i])
                                      ? Icons.expand_more
                                      : Icons.chevron_right,
                                  size: c.sz(theme.sizes.iconSm),
                                  color: theme.colors.foregroundMuted,
                                ),
                              )
                            : null,
                      ),
                    for (final UiTableColumn<T> col in cols)
                      _cellWrap(
                        col,
                        Align(
                          alignment: col.numeric
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: col.cell(ctx, visibleRows[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.expandableWhen != null &&
                widget.expandedBuilder != null &&
                widget.expandableWhen!(visibleRows[i]) &&
                _expanded.contains(visibleRows[i]))
              Container(
                width: double.infinity,
                color: theme.colors.surfaceMuted,
                padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
                child: widget.expandedBuilder!(context, visibleRows[i]),
              ),
          ],
        ),
    ];

    Widget bodyContent = Column(children: bodyRows);
    // When a max body height is supplied (or a sticky header is requested),
    // the header row above stays put while only the row list scrolls.
    if (widget.maxBodyHeight != null) {
      bodyContent = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.sp(widget.maxBodyHeight!)),
        child: SingleChildScrollView(child: bodyContent),
      );
    } else if (widget.stickyHeader) {
      // No explicit height: still isolate the header from the body scroll
      // region so it never scrolls with the rows below it.
      bodyContent = SingleChildScrollView(child: bodyContent);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            borderRadius: context.radius(theme.radii.lg),
            border: Border.all(
              color: theme.colors.border,
              width: theme.borders.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              headerRow,
              bodyContent,
              if (widget.footer != null)
                Container(
                  width: double.infinity,
                  color: theme.colors.surfaceMuted,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.sp(theme.spacing.lg),
                    vertical: context.sp(theme.spacing.md),
                  ),
                  child: widget.footer,
                ),
            ],
          ),
        ),
        if (widget.pageSize != null) _pager(context),
      ],
    );
  }

  Widget _headerCell(BuildContext context, UiTableColumn<T> col) {
    final theme = context.ui;
    final int index = widget.columns.indexOf(col);
    final bool sortable = col.compare != null || widget.onSort != null;
    final bool active = _activeSortCol == index;

    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            col.header,
            textAlign: col.numeric ? TextAlign.right : TextAlign.left,
            style: context.uiText.caption.copyWith(
              color: active
                  ? theme.colors.foreground
                  : theme.colors.foregroundMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (sortable) ...<Widget>[
          SizedBox(width: context.sp(theme.spacing.xxs)),
          Icon(
            active
                ? (_activeAsc ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: context.sz(theme.sizes.iconSm * 0.75),
            color: active
                ? theme.colors.foreground
                : theme.colors.foregroundSubtle,
          ),
        ],
      ],
    );

    final Widget aligned = Align(
      alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: label,
    );

    if (!sortable) return aligned;
    return UiInteractive(
      onTap: () => _toggleSort(index),
      builder: (BuildContext ctx, UiInteractiveState s) => aligned,
    );
  }

  Widget _pager(BuildContext context) {
    final theme = context.ui;
    final int total = _pageCount;
    return Padding(
      padding: EdgeInsets.only(top: context.sp(theme.spacing.md)),
      child: Row(
        children: <Widget>[
          Text(
            'Page ${_page + 1} of $total',
            style: context.uiText.caption
                .copyWith(color: theme.colors.foregroundMuted),
          ),
          const Spacer(),
          _pageButton(
            context,
            Icons.chevron_left,
            _page > 0 ? () => setState(() => _page -= 1) : null,
          ),
          SizedBox(width: context.sp(theme.spacing.xs)),
          _pageButton(
            context,
            Icons.chevron_right,
            _page < total - 1 ? () => setState(() => _page += 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _pageButton(
    BuildContext context,
    IconData icon,
    VoidCallback? onTap,
  ) {
    final theme = context.ui;
    return UiInteractive(
      enabled: onTap != null,
      onTap: onTap,
      builder: (BuildContext ctx, UiInteractiveState s) => Container(
        width: ctx.sz(theme.sizes.minTapTarget * 0.8),
        height: ctx.sz(theme.sizes.minTapTarget * 0.8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.hovered ? theme.colors.surfaceHover : theme.colors.surface,
          borderRadius: ctx.radius(theme.radii.md),
          border: Border.all(
            color: theme.colors.border,
            width: theme.borders.hairline,
          ),
        ),
        child: Icon(
          icon,
          size: ctx.sz(theme.sizes.iconSm),
          color: onTap == null
              ? theme.colors.disabledForeground
              : theme.colors.foreground,
        ),
      ),
    );
  }

  Widget _cellWrap(UiTableColumn<T> col, Widget child) => col.width != null
      ? SizedBox(width: col.width, child: child)
      : Expanded(flex: col.flex, child: child);
}
