import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/clock/focus_preset.dart';

/// Focus history screen built on QuietNote's core design system (UiPage, UiHeader, UiCard, UiBadge).
class FocusHistoryScreen extends ConsumerStatefulWidget {
  const FocusHistoryScreen({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => const FocusHistoryScreen(),
      ),
    );
  }

  @override
  ConsumerState<FocusHistoryScreen> createState() => _FocusHistoryScreenState();
}

class _FocusHistoryScreenState extends ConsumerState<FocusHistoryScreen> {
  String _filter = 'all'; // all, completed, cancelled

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(recentFocusSessionsProvider).value ?? const <FocusSession>[];
    final courses = ref.watch(coursesStreamProvider).value ?? const <Course>[];
    final tasks = ref.watch(tasksStreamProvider).value ?? const <Task>[];

    final completedList = history.where((s) => s.status == 'completed').toList();
    final totalFocusMinutes = completedList.fold<int>(
      0,
      (sum, s) => sum + s.durationMinutes,
    );
    final totalCycles = history.fold<int>(
      0,
      (sum, s) => sum + s.cyclesCompleted,
    );
    final completionRate = history.isEmpty
        ? 0
        : ((completedList.length / history.length) * 100).round();

    final filtered = history.where((s) {
      if (_filter == 'completed') return s.status == 'completed';
      if (_filter == 'cancelled') return s.status == 'cancelled';
      return true;
    }).toList();

    return Scaffold(
      body: UiPage(
        reserveDockSpace: false,
        header: UiHeader(
          title: 'Focus History',
          subtitle: 'Review your deep work sessions, cycle completions and reflections.',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 4-Card Analytics Metric Grid
            Row(
              children: [
                Expanded(
                  child: UiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: context.uiColors.primary,
                            ),
                            const Spacer(),
                            const UiBadge(label: 'Total', size: UiSize.xs, intent: UiIntent.primary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          totalFocusMinutes >= 60
                              ? '${(totalFocusMinutes / 60).toStringAsFixed(1)} hrs'
                              : '$totalFocusMinutes min',
                          style: context.uiText.heading,
                        ),
                        const SizedBox(height: 2),
                        Text('Total focus time', style: context.uiText.caption),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 16,
                              color: context.uiColors.bullish,
                            ),
                            const Spacer(),
                            UiBadge(
                              label: '$completionRate%',
                              size: UiSize.xs,
                              intent: UiIntent.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${completedList.length}',
                          style: context.uiText.heading,
                        ),
                        const SizedBox(height: 2),
                        Text('Sessions completed', style: context.uiText.caption),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: UiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.repeat_rounded,
                              size: 16,
                              color: context.uiColors.warning,
                            ),
                            const Spacer(),
                            const UiBadge(label: 'Pomodoro', size: UiSize.xs, intent: UiIntent.warning),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$totalCycles',
                          style: context.uiText.heading,
                        ),
                        const SizedBox(height: 2),
                        Text('Cycles completed', style: context.uiText.caption),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history_toggle_off_rounded,
                              size: 16,
                              color: context.uiColors.foregroundMuted,
                            ),
                            const Spacer(),
                            UiBadge(
                              label: '${history.length}',
                              size: UiSize.xs,
                              intent: UiIntent.neutral,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${history.length}',
                          style: context.uiText.heading,
                        ),
                        const SizedBox(height: 2),
                        Text('Total attempts', style: context.uiText.caption),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Segmented Filter
            UiToggleGroup<String>(
              value: _filter,
              expand: true,
              scrollableOnMobile: false,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                setState(() => _filter = val);
              },
              options: [
                UiToggleOption(value: 'all', label: 'All (${history.length})'),
                UiToggleOption(value: 'completed', label: 'Completed (${completedList.length})'),
                UiToggleOption(
                  value: 'cancelled',
                  label: 'Cancelled (${history.where((s) => s.status == 'cancelled').length})',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Session List
            if (filtered.isEmpty) ...[
              const SizedBox(height: 40),
              UiEmptyState(
                title: 'No focus sessions found',
                message: _filter == 'all'
                    ? 'Start a focus session from the Clock tab to track deep work.'
                    : 'No $_filter sessions recorded yet.',
                icon: Icons.timer_outlined,
              ),
            ] else ...[
              ...filtered.map((s) {
                final course = courses.where((c) => c.id == s.courseId).firstOrNull;
                final task = tasks.where((t) => t.id == s.taskId).firstOrNull;
                final preset = focusPresetFromId(s.presetId);
                final isCompleted = s.status == 'completed';
                final isActive = s.status == 'active';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: UiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isActive
                                  ? Icons.hourglass_top_rounded
                                  : isCompleted
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_outlined,
                              color: isActive
                                  ? context.uiColors.primary
                                  : isCompleted
                                      ? context.uiColors.bullish
                                      : context.uiColors.foregroundMuted,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${s.durationMinutes} min ${preset?.chipLabel ?? "Focus"}',
                                style: context.uiText.bodyStrong,
                              ),
                            ),
                            UiBadge(
                              label: isActive
                                  ? 'In Progress'
                                  : isCompleted
                                      ? 'Completed'
                                      : 'Cancelled',
                              intent: isActive
                                  ? UiIntent.primary
                                  : isCompleted
                                      ? UiIntent.success
                                      : UiIntent.neutral,
                              size: UiSize.xs,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: context.uiColors.foregroundMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat.yMMMd().add_jm().format(s.startedAt),
                              style: context.uiText.caption.copyWith(
                                color: context.uiColors.foregroundMuted,
                              ),
                            ),
                            if (s.cyclesCompleted > 0) ...[
                              const SizedBox(width: 14),
                              Icon(
                                Icons.repeat_rounded,
                                size: 13,
                                color: context.uiColors.warning,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${s.cyclesCompleted} ${s.cyclesCompleted == 1 ? "cycle" : "cycles"}',
                                style: context.uiText.caption.copyWith(
                                  color: context.uiColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (course != null || task != null) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (course != null)
                                UiBadge(
                                  label: 'Subject: ${course.code ?? course.name}',
                                  intent: UiIntent.primary,
                                  size: UiSize.xs,
                                ),
                              if (task != null)
                                UiBadge(
                                  label: 'Task: ${task.title}',
                                  intent: UiIntent.info,
                                  size: UiSize.xs,
                                ),
                            ],
                          ),
                        ],
                        if (s.reflection != null && s.reflection!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.uiColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: context.uiColors.border),
                            ),
                            child: Text(
                              '"${s.reflection}"',
                              style: context.uiText.caption.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
