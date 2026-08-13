import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/features/calendar/calendar_event_editor_screen.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

enum _CalendarView { month, agenda }

final _calendarViewProvider = StateProvider<_CalendarView>(
  (ref) => _CalendarView.month,
);
final _selectedDayProvider = StateProvider<DateTime>(
  (ref) => _dateOnly(DateTime.now()),
);
final _calendarQueryProvider = StateProvider<String>((ref) => '');
final _calendarCategoryProvider = StateProvider<String?>((ref) => null);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _dayHeading(DateTime day) {
  final today = _dateOnly(DateTime.now());
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat('EEEE, MMM d').format(day);
}

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent event,
  ) async {
    if (event.id.contains(':')) {
      UiToast.show(
        context,
        title: 'Manage this in its own feature',
        message: 'This calendar item is linked from a task, habit, or goal.',
        intent: UiIntent.info,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('This removes "${event.title}". This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.uiColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(calendarRepositoryProvider).deleteEvent(event.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(aggregatedCalendarEventsProvider);
    final view = ref.watch(_calendarViewProvider);
    final selectedDay = ref.watch(_selectedDayProvider);

    return UiPage(
      header: UiHeader(
        title: 'Calendar',
        leading: const QuietNoteMark(size: 38),
        subtitle: 'Plan your schedule and stay ahead of every commitment.',
        actions: [
          UiIconButton(
            icon: Icons.today_outlined,
            tooltip: 'Jump to today',
            onPressed: () => ref.read(_selectedDayProvider.notifier).state =
                _dateOnly(DateTime.now()),
          ),
        ],
      ),
      floatingActionButton: UiFab(
        tooltip: 'New event',
        onPressed: () => context.push(
          '/calendar/new?date=${selectedDay.toIso8601String()}',
        ),
      ),
      child: eventsAsync.when(
        loading: () => const _CalendarSkeleton(),
        error: (err, stack) => UiCard(
          accentColor: context.uiColors.destructive,
          child: Text(
            'Could not load calendar: $err',
            style: context.uiText.caption.copyWith(
              color: context.uiColors.destructive,
            ),
          ),
        ),
        data: (events) {
          final goalsAsync = ref.watch(goalsStreamProvider);
          final goalTitles = <String, String>{
            for (final g in goalsAsync.maybeWhen(
              data: (g) => g,
              orElse: () => const <Goal>[],
            ))
              g.id: g.title,
          };

          final today = _dateOnly(DateTime.now());
          final thisMonthCount = events
              .where(
                (e) =>
                    e.startTime.year == today.year &&
                    e.startTime.month == today.month,
              )
              .length;
          final todayCount = events
              .where((e) => _dateOnly(e.startTime) == today)
              .length;
          final upcomingCount = events
              .where(
                (e) =>
                    !e.startTime.isBefore(today) &&
                    e.startTime.isBefore(today.add(const Duration(days: 7))),
              )
              .length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'This month',
                      value: '$thisMonthCount',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(label: 'Today', value: '$todayCount'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Next 7 days',
                      value: '$upcomingCount',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              UiToggleGroup<_CalendarView>(
                variant: UiToggleGroupVariant.segmented,
                expand: true,
                value: view,
                onChanged: (v) =>
                    ref.read(_calendarViewProvider.notifier).state = v,
                options: const [
                  UiToggleOption(
                    value: _CalendarView.month,
                    label: 'Month',
                    icon: Icons.calendar_view_month_rounded,
                  ),
                  UiToggleOption(
                    value: _CalendarView.agenda,
                    label: 'Agenda',
                    icon: Icons.view_agenda_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (view == _CalendarView.month)
                _MonthView(
                  events: events,
                  goalTitles: goalTitles,
                  onDelete: (e) => _confirmDelete(context, ref, e),
                )
              else
                _AgendaView(
                  events: events,
                  goalTitles: goalTitles,
                  onDelete: (e) => _confirmDelete(context, ref, e),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.uiText.caption),
          const SizedBox(height: 4),
          Text(value, style: context.uiText.heading),
        ],
      ),
    );
  }
}

class _MonthView extends ConsumerWidget {
  const _MonthView({
    required this.events,
    required this.goalTitles,
    required this.onDelete,
  });

  final List<CalendarEvent> events;
  final Map<String, String> goalTitles;
  final ValueChanged<CalendarEvent> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDay = ref.watch(_selectedDayProvider);
    final markedDates = events.map((e) => _dateOnly(e.startTime)).toSet();
    final dayEvents =
        events.where((e) => _dateOnly(e.startTime) == selectedDay).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiCalendar(
          selected: selectedDay,
          markedDates: markedDates,
          onDateSelected: (d) =>
              ref.read(_selectedDayProvider.notifier).state = _dateOnly(d),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(_dayHeading(selectedDay), style: context.uiText.bodyStrong),
            const Spacer(),
            if (dayEvents.isNotEmpty)
              Text(
                '${dayEvents.length} event${dayEvents.length == 1 ? '' : 's'}',
                style: context.uiText.caption,
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (dayEvents.isEmpty)
          UiCard(
            onTap: () => context.push(
              '/calendar/new?date=${selectedDay.toIso8601String()}',
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 18,
                  color: context.uiColors.foregroundMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  'Nothing scheduled — tap to add an event',
                  style: context.uiText.caption,
                ),
              ],
            ),
          )
        else
          ...dayEvents.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EventCard(
                event: e,
                goalTitle: e.linkedGoalId == null
                    ? null
                    : goalTitles[e.linkedGoalId],
                onTap: () => _openEvent(context, e),
                onDelete: () => onDelete(e),
              ),
            ),
          ),
      ],
    );
  }
}

class _AgendaView extends ConsumerWidget {
  const _AgendaView({
    required this.events,
    required this.goalTitles,
    required this.onDelete,
  });

  final List<CalendarEvent> events;
  final Map<String, String> goalTitles;
  final ValueChanged<CalendarEvent> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_calendarQueryProvider);
    final category = ref.watch(_calendarCategoryProvider);

    final q = query.trim().toLowerCase();
    final filtered = events.where((e) {
      if (q.isNotEmpty) {
        final matches =
            e.title.toLowerCase().contains(q) ||
            (e.description ?? '').toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (category != null && e.category != category) return false;
      return true;
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

    final today = _dateOnly(DateTime.now());
    final upcoming = filtered
        .where((e) => !_dateOnly(e.startTime).isBefore(today))
        .toList();
    final past = filtered
        .where((e) => _dateOnly(e.startTime).isBefore(today))
        .toList()
        .reversed
        .toList();

    final grouped = <DateTime, List<CalendarEvent>>{};
    for (final e in [...upcoming, ...past]) {
      grouped.putIfAbsent(_dateOnly(e.startTime), () => []).add(e);
    }
    final orderedDays = grouped.keys.toList()
      ..sort((a, b) {
        final aUp = !a.isBefore(today);
        final bUp = !b.isBefore(today);
        if (aUp != bUp) return aUp ? -1 : 1;
        return aUp ? a.compareTo(b) : b.compareTo(a);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiSearchField(
          hintText: 'Search events...',
          value: query,
          onChanged: (v) => ref.read(_calendarQueryProvider.notifier).state = v,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryChip(
                label: 'All',
                selected: category == null,
                color: context.uiColors.foreground,
                icon: Icons.apps_rounded,
                onTap: () =>
                    ref.read(_calendarCategoryProvider.notifier).state = null,
              ),
              ...categoryNames.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CategoryChip(
                    label: name,
                    selected: category == name,
                    color: categoryColor(context, name),
                    icon: categoryIcon(name),
                    onTap: () =>
                        ref.read(_calendarCategoryProvider.notifier).state =
                            name,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (orderedDays.isEmpty)
          UiEmptyState(
            title: 'No events found',
            message: q.isNotEmpty || category != null
                ? 'Nothing matches your search or filter.'
                : 'Your schedule is clear.',
            icon: Icons.event_busy_outlined,
          )
        else
          ...orderedDays.expand((day) {
            final dayEvents = grouped[day]!
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            return [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(_dayHeading(day), style: context.uiText.bodyStrong),
              ),
              ...dayEvents.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EventCard(
                    event: e,
                    goalTitle: e.linkedGoalId == null
                        ? null
                        : goalTitles[e.linkedGoalId],
                    onTap: () => _openEvent(context, e),
                    onDelete: () => onDelete(e),
                    faded: day.isBefore(today),
                  ),
                ),
              ),
            ];
          }),
      ],
    );
  }
}

void _openEvent(BuildContext context, CalendarEvent event) {
  // The unified calendar contains linked tasks, habits and goals too. Open
  // their owning flow instead of attempting to edit a synthetic calendar id.
  if (event.id.startsWith('task:')) {
    context.push('/todos/edit/${event.id.substring(5)}');
    return;
  }
  if (event.id.startsWith('habit:')) {
    context.push('/habits/${event.id.split(':')[1]}');
    return;
  }
  if (event.id.startsWith('goal:')) {
    context.push('/goals/edit/${event.id.substring(5)}');
    return;
  }
  context.push('/calendar/${event.id}');
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : c.foregroundMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.uiText.caption.copyWith(
                color: selected ? color : c.foregroundMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.goalTitle,
    required this.onTap,
    required this.onDelete,
    this.faded = false,
  });

  final CalendarEvent event;
  final String? goalTitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final tint = event.color != null
        ? Color(event.color!)
        : categoryColor(context, event.category);

    return UiCard(
      onTap: onTap,
      accentColor: tint,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Opacity(
        opacity: faded ? 0.55 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(categoryIcon(event.category), size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: context.uiText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.isAllDay
                        ? 'All day'
                        : '${DateFormat.jm().format(event.startTime)} - ${DateFormat.jm().format(event.endTime)}',
                    style: context.uiText.caption,
                  ),
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.description!,
                      style: context.uiText.caption.copyWith(
                        color: c.foregroundSubtle,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (event.category != null ||
                      event.recurrenceRule != null ||
                      goalTitle != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (event.category != null)
                          UiBadge(
                            label: event.category!,
                            intent: UiIntent.neutral,
                            size: UiSize.sm,
                          ),
                        if (event.recurrenceRule != null)
                          UiBadge(
                            label: _capitalize(event.recurrenceRule!),
                            icon: Icons.repeat_rounded,
                            intent: UiIntent.info,
                            size: UiSize.sm,
                          ),
                        if (goalTitle != null)
                          UiBadge(
                            label: goalTitle!,
                            icon: Icons.flag_outlined,
                            intent: UiIntent.primary,
                            size: UiSize.sm,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              size: UiSize.sm,
              tooltip: 'Delete event',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        UiCard(loading: true, loadingHeight: 320, child: SizedBox.shrink()),
        SizedBox(height: 16),
        UiCard(loading: true, loadingHeight: 72, child: SizedBox.shrink()),
        SizedBox(height: 10),
        UiCard(loading: true, loadingHeight: 72, child: SizedBox.shrink()),
      ],
    );
  }
}
