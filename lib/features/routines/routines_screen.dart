import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';

/// Time blocks a routine can be scheduled into, in day order.
const List<String> routineTimeBlocks = ['Morning', 'Afternoon', 'Evening', 'Night'];

const List<IconData> _routineTimeIcons = [
  Icons.wb_sunny_outlined,
  Icons.wb_cloudy_outlined,
  Icons.wb_twilight_rounded,
  Icons.nights_stay_outlined,
];

int routineTimeIndex(String? timeOfDay) {
  if (timeOfDay == null) return 0;
  final i = routineTimeBlocks.indexOf(timeOfDay);
  return i == -1 ? 0 : i;
}

IconData routineTimeIcon(String? timeOfDay) => _routineTimeIcons[routineTimeIndex(timeOfDay)];

Color routineTimeColor(BuildContext context, String? timeOfDay) {
  const series = UiPalette.series;
  return series[routineTimeIndex(timeOfDay) % series.length];
}

/// The time block the current wall-clock hour falls into, used to highlight
/// "what's up next" on the list screen.
String currentRoutineTimeBlock([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 21) return 'Evening';
  return 'Night';
}

/// A single step in a routine's checklist.
class RoutineStep {
  RoutineStep({required this.title, this.isCompleted = false});
  final String title;
  bool isCompleted;

  Map<String, dynamic> toJson() => {'title': title, 'isCompleted': isCompleted};
}

/// Parsed shape of a [Routine.description]: an optional freeform note plus an
/// ordered checklist of steps. Stored as a JSON string in the existing
/// `description` column — the same "structured data in a text column"
/// convention Goals uses for milestones — so no schema migration is needed.
class RoutineContent {
  RoutineContent({this.note = '', List<RoutineStep>? steps}) : steps = steps ?? [];
  final String note;
  final List<RoutineStep> steps;

  int get doneCount => steps.where((s) => s.isCompleted).length;
  double get progress => steps.isEmpty ? 0 : doneCount / steps.length;

  String encode() {
    if (note.trim().isEmpty && steps.isEmpty) return '';
    return jsonEncode({'note': note, 'steps': steps.map((s) => s.toJson()).toList()});
  }

  static RoutineContent parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return RoutineContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final steps = (decoded['steps'] as List? ?? [])
            .map((e) => RoutineStep(
                  title: (e as Map)['title']?.toString() ?? '',
                  isCompleted: e['isCompleted'] == true,
                ))
            .toList();
        return RoutineContent(note: decoded['note']?.toString() ?? '', steps: steps);
      }
    } catch (_) {
      // Legacy plain-text description written before this redesign — show
      // it as the note with no steps rather than losing it.
      return RoutineContent(note: raw);
    }
    return RoutineContent(note: raw);
  }
}

enum _RoutineFilter { all, active, paused }

final _routineQueryProvider = StateProvider<String>((ref) => '');
final _routineFilterProvider = StateProvider<_RoutineFilter>((ref) => _RoutineFilter.all);
final _routineBlockFilterProvider = StateProvider<String?>((ref) => null);

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Routine r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete routine?'),
        content: Text('This removes "${r.title}" and its steps. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: context.uiColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(routineRepositoryProvider).deleteRoutine(r.id);
    }
  }

  Future<void> _duplicate(WidgetRef ref, Routine r) async {
    await ref.read(routineRepositoryProvider).addRoutine(
          '${r.title} (copy)',
          r.timeOfDay,
          description: r.description,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(routinesStreamProvider);
    final query = ref.watch(_routineQueryProvider);
    final filter = ref.watch(_routineFilterProvider);
    final blockFilter = ref.watch(_routineBlockFilterProvider);
    final c = context.uiColors;
    final nowBlock = currentRoutineTimeBlock();

    return UiPage(
      header: const UiHeader(
        title: 'Routines',
        subtitle: 'Build consistent daily rhythms that guide seamless productivity.',
      ),
      floatingActionButton: UiFab(
        tooltip: 'New routine',
        onPressed: () => context.push('/routines/new'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          routinesAsync.when(
            data: (routines) {
              if (routines.isEmpty) {
                return const UiEmptyState(
                  title: 'No routines established',
                  message: 'Create your first routine to structure your day.',
                  icon: Icons.schedule,
                );
              }

              final active = routines.where((r) => r.isActive).toList();
              final contents = {for (final r in routines) r.id: RoutineContent.parse(r.description)};
              final activeWithSteps = active.where((r) => contents[r.id]!.steps.isNotEmpty);
              final totalSteps = activeWithSteps.fold<int>(0, (a, r) => a + contents[r.id]!.steps.length);
              final doneSteps = activeWithSteps.fold<int>(0, (a, r) => a + contents[r.id]!.doneCount);
              final dueNow = active.where((r) => r.timeOfDay == nowBlock).length;

              final q = query.trim().toLowerCase();
              final filtered = routines.where((r) {
                if (filter == _RoutineFilter.active && !r.isActive) return false;
                if (filter == _RoutineFilter.paused && r.isActive) return false;
                if (blockFilter != null && r.timeOfDay != blockFilter) return false;
                if (q.isEmpty) return true;
                return r.title.toLowerCase().contains(q) || contents[r.id]!.note.toLowerCase().contains(q);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _StatCard(label: 'Total routines', value: '${routines.length}')),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(label: 'Active', value: '${active.length}')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: "Today's steps",
                          value: totalSteps == 0 ? '—' : '$doneSteps/$totalSteps',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Today\u2019s flow', style: context.uiText.bodyStrong),
                  const SizedBox(height: 4),
                  Text(
                    dueNow == 0
                        ? 'Nothing scheduled for right now.'
                        : '$dueNow routine${dueNow == 1 ? '' : 's'} in your current block.',
                    style: context.uiText.caption,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: routineTimeBlocks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (ctx, i) {
                        final block = routineTimeBlocks[i];
                        final blockRoutines = routines.where((r) => r.timeOfDay == block).toList();
                        final blockColor = routineTimeColor(context, block);
                        final isNow = block == nowBlock;
                        final selected = blockFilter == block;
                        return _TimeBlockChip(
                          label: block,
                          icon: _routineTimeIcons[i],
                          color: blockColor,
                          count: blockRoutines.length,
                          isNow: isNow,
                          selected: selected,
                          onTap: () => ref.read(_routineBlockFilterProvider.notifier).state =
                              selected ? null : block,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  UiSearchField(
                    hintText: 'Search routines...',
                    value: query,
                    onChanged: (v) => ref.read(_routineQueryProvider.notifier).state = v,
                  ),
                  const SizedBox(height: 12),
                  UiToggleGroup<_RoutineFilter>(
                    variant: UiToggleGroupVariant.segmented,
                    size: UiSize.sm,
                    expand: true,
                    value: filter,
                    onChanged: (v) => ref.read(_routineFilterProvider.notifier).state = v,
                    options: const [
                      UiToggleOption(value: _RoutineFilter.all, label: 'All'),
                      UiToggleOption(value: _RoutineFilter.active, label: 'Active'),
                      UiToggleOption(value: _RoutineFilter.paused, label: 'Paused'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    UiEmptyState(
                      title: 'Nothing here',
                      message: q.isNotEmpty
                          ? 'Nothing found for "$query".'
                          : 'No routines match this filter.',
                      icon: Icons.search_off_rounded,
                    )
                  else
                    ...routineTimeBlocks.where((block) => filtered.any((r) => r.timeOfDay == block)).expand<Widget>(
                      (block) {
                        final blockRoutines = filtered.where((r) => r.timeOfDay == block).toList();
                        final blockColor = routineTimeColor(context, block);
                        return [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, top: 4),
                            child: Row(
                              children: [
                                Icon(routineTimeIcon(block), size: 15, color: blockColor),
                                const SizedBox(width: 6),
                                Text(block, style: context.uiText.bodyStrong.copyWith(color: blockColor)),
                                const SizedBox(width: 6),
                                Text('${blockRoutines.length}', style: context.uiText.caption),
                              ],
                            ),
                          ),
                          ...blockRoutines.map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _RoutineCard(
                                  routine: r,
                                  content: contents[r.id]!,
                                  onEdit: () => context.push('/routines/edit/${r.id}'),
                                  onDelete: () => _confirmDelete(context, ref, r),
                                  onDuplicate: () => _duplicate(ref, r),
                                ),
                              )),
                          const SizedBox(height: 8),
                        ];
                      },
                    ),
                ],
              );
            },
            loading: () => Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: UiCard(loading: true, loadingHeight: 120, child: SizedBox.shrink()),
                ),
              ),
            ),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Could not load routines: $err', style: context.uiText.caption.copyWith(color: c.destructive)),
            ),
          ),
        ],
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
          Text(label, style: context.uiText.caption, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value, style: context.uiText.heading),
        ],
      ),
    );
  }
}

class _TimeBlockChip extends StatelessWidget {
  const _TimeBlockChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.isNow,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool isNow;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : c.border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const Spacer(),
                if (isNow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                    child: const Text('NOW', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(label, style: context.uiText.caption.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              count == 1 ? '1 routine' : '$count routines',
              style: context.uiText.caption.copyWith(color: c.foregroundMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends ConsumerWidget {
  const _RoutineCard({
    required this.routine,
    required this.content,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
  });

  final Routine routine;
  final RoutineContent content;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.uiColors;
    final color = routineTimeColor(context, routine.timeOfDay);
    final hasSteps = content.steps.isNotEmpty;

    return UiCard(
      onTap: onEdit,
      accentColor: routine.isActive ? color : c.border,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: routine.isActive ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(routineTimeIcon(routine.timeOfDay), size: 20, color: routine.isActive ? color : c.foregroundMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style: context.uiText.bodyStrong.copyWith(
                        color: routine.isActive ? null : c.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        UiBadge(label: routine.timeOfDay, intent: UiIntent.neutral, size: UiSize.sm),
                        if (hasSteps)
                          UiBadge(
                            label: '${content.doneCount}/${content.steps.length} steps',
                            intent: content.progress >= 1 ? UiIntent.success : UiIntent.info,
                            size: UiSize.sm,
                          ),
                        if (!routine.isActive)
                          const UiBadge(label: 'Paused', intent: UiIntent.warning, size: UiSize.sm),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              UiSwitch(
                value: routine.isActive,
                onChanged: (val) => ref.read(routineRepositoryProvider).toggleRoutineActive(routine.id, val),
              ),
            ],
          ),
          if (content.note.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              content.note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.uiText.body.copyWith(color: c.foregroundMuted),
            ),
          ],
          if (hasSteps) ...[
            const SizedBox(height: 12),
            UiProgressBar(value: content.progress, showValue: false, intent: content.progress >= 1 ? UiIntent.success : UiIntent.primary),
            const SizedBox(height: 8),
            ...content.steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: UiCheckbox(
                  value: step.isCompleted,
                  size: UiSize.sm,
                  label: step.title,
                  onChanged: (_) {
                    final updated = content.steps
                        .map((s) => RoutineStep(title: s.title, isCompleted: s.isCompleted))
                        .toList();
                    updated[index].isCompleted = !step.isCompleted;
                    final next = RoutineContent(note: content.note, steps: updated);
                    ref.read(routineRepositoryProvider).updateRoutineDescription(routine.id, next.encode());
                  },
                ),
              );
            }),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              UiIconButton(
                icon: Icons.copy_all_outlined,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                tooltip: 'Duplicate routine',
                onPressed: onDuplicate,
              ),
              UiIconButton(
                icon: Icons.edit_outlined,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                tooltip: 'Edit routine',
                onPressed: onEdit,
              ),
              UiIconButton(
                icon: Icons.delete_outline,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                tooltip: 'Delete routine',
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
