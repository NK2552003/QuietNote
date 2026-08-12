import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_icon_button.dart';

/// Month calendar grid. Single date or range selection, fully themed.
class UiCalendar extends StatefulWidget {
  const UiCalendar({
    super.key,
    this.selected,
    this.range,
    this.onDateSelected,
    this.onRangeSelected,
    this.firstDate,
    this.lastDate,
    this.rangeMode = false,
    this.markedDates = const <DateTime>{},
    this.monthCount = 1,
  });

  final DateTime? selected;
  final DateTimeRange? range;
  final ValueChanged<DateTime>? onDateSelected;
  final ValueChanged<DateTimeRange>? onRangeSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool rangeMode;

  /// Days highlighted with a dot (earnings dates, events).
  final Set<DateTime> markedDates;

  /// Show several consecutive months at once (range pickers on wide screens).
  /// Falls back to a stacked layout on phones.
  final int monthCount;


  @override
  State<UiCalendar> createState() => _UiCalendarState();
}

class _UiCalendarState extends State<UiCalendar> {
  late DateTime _month = DateTime(
    (widget.selected ?? DateTime.now()).year,
    (widget.selected ?? DateTime.now()).month,
  );
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  static const List<String> _weekdays = <String>[
    'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su',
  ];
  static const List<String> _months = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.range?.start;
    _rangeEnd = widget.range?.end;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _disabled(DateTime day) {
    if (widget.firstDate != null && day.isBefore(widget.firstDate!)) return true;
    if (widget.lastDate != null && day.isAfter(widget.lastDate!)) return true;
    return false;
  }

  void _tap(DateTime day) {
    if (_disabled(day)) return;
    if (!widget.rangeMode) {
      widget.onDateSelected?.call(day);
      setState(() {});
      return;
    }
    setState(() {
      if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
        _rangeStart = day;
        _rangeEnd = null;
      } else if (day.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
    if (_rangeStart != null && _rangeEnd != null) {
      widget.onRangeSelected?.call(
        DateTimeRange(start: _rangeStart!, end: _rangeEnd!),
      );
    }
  }

  String _label(DateTime m) => '${_months[m.month - 1]} ${m.year}';

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final int count = widget.monthCount < 1 ? 1 : widget.monthCount;
    final bool stacked = context.uiRes.isMobile || count == 1;
    final List<DateTime> months = <DateTime>[
      for (int i = 0; i < count; i++) DateTime(_month.year, _month.month + i),
    ];

    Widget titled(DateTime m) => Column(
          children: <Widget>[
            if (count > 1) ...<Widget>[
              Text(
                _label(m),
                style: context.uiText.label.copyWith(color: c.foreground),
              ),
              SizedBox(height: context.sp(theme.spacing.xs)),
            ],
            _monthBody(context, m),
          ],
        );

    return Container(
      padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: context.radius(theme.radii.xl),
        border: Border.all(color: c.border, width: theme.borders.hairline),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              UiIconButton(
                icon: Icons.chevron_left,
                size: UiSize.sm,
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
              ),
              Expanded(
                child: Text(
                  count > 1
                      ? '${_label(months.first)} – ${_label(months.last)}'
                      : _label(months.first),
                  textAlign: TextAlign.center,
                  style: context.uiText.bodyStrong.copyWith(color: c.foreground),
                ),
              ),
              UiIconButton(
                icon: Icons.chevron_right,
                size: UiSize.sm,
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
              ),
            ],
          ),
          SizedBox(height: context.sp(theme.spacing.sm)),
          if (stacked)
            for (final DateTime m in months)
              Padding(
                padding: EdgeInsets.only(bottom: context.sp(theme.spacing.md)),
                child: titled(m),
              )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < months.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: context.sp(theme.spacing.lg)),
                  Expanded(child: titled(months[i])),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _monthBody(BuildContext context, DateTime month) {
    final theme = context.ui;
    final c = theme.colors;
    final int leading = DateTime(month.year, month.month).weekday - 1;
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String d in _weekdays)
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: context.uiText.caption
                      .copyWith(color: c.foregroundSubtle),
                ),
              ),
          ],
        ),
        SizedBox(height: context.sp(theme.spacing.xs)),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: leading + daysInMonth,
            itemBuilder: (BuildContext ctx, int index) {
              if (index < leading) return const SizedBox.shrink();
              final DateTime day = DateTime(
                month.year,
                month.month,
                index - leading + 1,
              );
              final bool isSelected = widget.rangeMode
                  ? (_rangeStart != null && _sameDay(day, _rangeStart!)) ||
                      (_rangeEnd != null && _sameDay(day, _rangeEnd!))
                  : widget.selected != null && _sameDay(day, widget.selected!);
              final bool inRange = widget.rangeMode &&
                  _rangeStart != null &&
                  _rangeEnd != null &&
                  day.isAfter(_rangeStart!) &&
                  day.isBefore(_rangeEnd!);
              final bool isToday = _sameDay(day, DateTime.now());
              final bool marked = widget.markedDates
                  .any((DateTime d) => _sameDay(d, day));
              final bool off = _disabled(day);

              return UiInteractive(
                enabled: !off,
                onTap: () => _tap(day),
                builder: (BuildContext c2, UiInteractiveState s) =>
                    AnimatedContainer(
                  duration: theme.motion.fast,
                  margin: EdgeInsets.all(c2.sz(2)),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? c.primary
                        : inRange
                            ? c.primary.withValues(alpha: 0.12)
                            : (s.hovered ? c.surfaceHover : Colors.transparent),
                    borderRadius: c2.radius(theme.radii.md),
                    border: isToday && !isSelected
                        ? Border.all(
                            color: c.borderStrong,
                            width: theme.borders.hairline,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '${day.day}',
                        style: c2.uiText.label.copyWith(
                          color: off
                              ? c.disabledForeground
                              : isSelected
                                  ? c.onPrimary
                                  : c.foreground,
                        ),
                      ),
                      if (marked)
                        Container(
                          margin: EdgeInsets.only(top: c2.sz(2)),
                          width: c2.sz(4),
                          height: c2.sz(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? c.onPrimary : c.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
        ),
      ],
    );
  }
}
