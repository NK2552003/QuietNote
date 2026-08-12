import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/calendar/calendar_event_editor_screen.dart';

/// Calendar entries are read first. This avoids making a saved event editable
/// merely by opening it and mirrors the Note/Journal detail flow.
class CalendarEventPreviewScreen extends ConsumerWidget {
  const CalendarEventPreviewScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<CalendarEvent?>(
    future: ref.read(calendarRepositoryProvider).getEventById(eventId),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const UiPage(child: Center(child: CircularProgressIndicator()));
      }
      final event = snapshot.data;
      if (event == null) {
        return const UiPage(
          header: UiHeader(title: 'Event'),
          child: UiEmptyState(
            title: 'Event not found',
            message: 'It may have been deleted.',
            icon: Icons.event_busy_outlined,
          ),
        );
      }
      final tint = event.color == null
          ? categoryColor(context, event.category)
          : Color(event.color!);
      final date = event.isAllDay
          ? DateFormat('EEEE, MMMM d, y').format(event.startTime)
          : '${DateFormat('EEEE, MMM d').format(event.startTime)} · ${DateFormat.jm().format(event.startTime)} – ${DateFormat.jm().format(event.endTime)}';
      return UiPage(
        header: UiHeader(
          leading: UiIconButton(
            icon: Icons.arrow_back,
            variant: UiVariant.ghost,
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
          title: 'Event details',
          actions: [
            UiButton(
              label: 'Edit',
              leadingIcon: Icons.edit_outlined,
              onPressed: () => context.push('/calendar/edit/$eventId'),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiCard(
              accentColor: tint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: context.uiText.heading),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        event.isAllDay
                            ? Icons.today_outlined
                            : Icons.schedule_outlined,
                        size: 17,
                        color: context.uiColors.foregroundMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.isAllDay ? '$date · All day' : date,
                          style: context.uiText.body,
                        ),
                      ),
                    ],
                  ),
                  if ((event.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(event.description!, style: context.uiText.body),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            UiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Schedule', style: context.uiText.bodyStrong),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: categoryIcon(event.category),
                    label: 'Category',
                    value: event.category ?? 'Other',
                  ),
                  if (event.recurrenceRule != null)
                    _DetailRow(
                      icon: Icons.repeat_rounded,
                      label: 'Repeats',
                      value: event.recurrenceRule!.replaceFirst(
                        event.recurrenceRule![0],
                        event.recurrenceRule![0].toUpperCase(),
                      ),
                    ),
                  if (event.reminderOffset != null)
                    _DetailRow(
                      icon: Icons.notifications_outlined,
                      label: 'Reminder',
                      value: event.reminderOffset == 0
                          ? 'At start time'
                          : '${event.reminderOffset} minutes before',
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 17, color: context.uiColors.foregroundMuted),
        const SizedBox(width: 10),
        Text(label, style: context.uiText.caption),
        const Spacer(),
        Text(value, style: context.uiText.bodyStrong),
      ],
    ),
  );
}
