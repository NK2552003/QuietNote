import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/clock/focus_history_screen.dart';

final globalSearchQueryProvider = StateProvider<String>((ref) => '');
final globalSearchCategoryProvider = StateProvider<String>((ref) => 'all');
final recentSearchesProvider = StateProvider<List<String>>((ref) => <String>[]);

/// Comprehensive search results model spanning all 11 core QuietNote features.
class ComprehensiveSearchResults {
  const ComprehensiveSearchResults({
    required this.notes,
    required this.journal,
    required this.tasks,
    required this.habits,
    required this.courses,
    required this.goals,
    required this.decks,
    required this.routines,
    required this.calendarEvents,
    required this.focusSessions,
  });

  static const empty = ComprehensiveSearchResults(
    notes: <Note>[],
    journal: <JournalData>[],
    tasks: <Task>[],
    habits: <Habit>[],
    courses: <Course>[],
    goals: <Goal>[],
    decks: <FlashcardDeck>[],
    routines: <Routine>[],
    calendarEvents: <CalendarEvent>[],
    focusSessions: <FocusSession>[],
  );

  final List<Note> notes;
  final List<JournalData> journal;
  final List<Task> tasks;
  final List<Habit> habits;
  final List<Course> courses;
  final List<Goal> goals;
  final List<FlashcardDeck> decks;
  final List<Routine> routines;
  final List<CalendarEvent> calendarEvents;
  final List<FocusSession> focusSessions;

  int get totalCount =>
      notes.length +
      journal.length +
      tasks.length +
      habits.length +
      courses.length +
      goals.length +
      decks.length +
      routines.length +
      calendarEvents.length +
      focusSessions.length;

  bool get isEmpty => totalCount == 0;
}

final comprehensiveSearchResultsProvider =
    Provider<ComprehensiveSearchResults>((ref) {
  final q = ref.watch(globalSearchQueryProvider).trim().toLowerCase();
  if (q.isEmpty) return ComprehensiveSearchResults.empty;

  final notes = ref.watch(notesStreamProvider).valueOrNull ?? const <Note>[];
  final journal =
      ref.watch(journalStreamProvider).valueOrNull ?? const <JournalData>[];
  final tasks = ref.watch(tasksStreamProvider).valueOrNull ?? const <Task>[];
  final habits = ref.watch(habitsStreamProvider).valueOrNull ?? const <Habit>[];
  final courses =
      ref.watch(coursesStreamProvider).valueOrNull ?? const <Course>[];
  final goals = ref.watch(goalsStreamProvider).valueOrNull ?? const <Goal>[];
  final decks =
      ref.watch(flashcardDecksStreamProvider).valueOrNull ?? const <FlashcardDeck>[];
  final routines =
      ref.watch(routinesStreamProvider).valueOrNull ?? const <Routine>[];
  final calendar =
      ref.watch(calendarEventsStreamProvider).valueOrNull ?? const <CalendarEvent>[];
  final focus =
      ref.watch(recentFocusSessionsProvider).valueOrNull ?? const <FocusSession>[];

  return ComprehensiveSearchResults(
    notes: notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q) ||
              (n.tags != null && n.tags!.toLowerCase().contains(q)),
        )
        .toList(),
    journal: journal
        .where(
          (j) =>
              j.title.toLowerCase().contains(q) ||
              j.entry.toLowerCase().contains(q) ||
              (j.mood != null && j.mood!.toLowerCase().contains(q)) ||
              (j.tags != null && j.tags!.toLowerCase().contains(q)),
        )
        .toList(),
    tasks: tasks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.subtitle.toLowerCase().contains(q) ||
              (t.details ?? '').toLowerCase().contains(q),
        )
        .toList(),
    habits: habits
        .where(
          (h) =>
              h.title.toLowerCase().contains(q) ||
              h.subtitle.toLowerCase().contains(q) ||
              (h.category != null && h.category!.toLowerCase().contains(q)) ||
              (h.notes != null && h.notes!.toLowerCase().contains(q)),
        )
        .toList(),
    courses: courses
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.code != null && c.code!.toLowerCase().contains(q)) ||
              (c.instructor != null && c.instructor!.toLowerCase().contains(q)) ||
              (c.room != null && c.room!.toLowerCase().contains(q)),
        )
        .toList(),
    goals: goals
        .where(
          (g) =>
              g.title.toLowerCase().contains(q) ||
              (g.category != null && g.category!.toLowerCase().contains(q)),
        )
        .toList(),
    decks: decks
        .where(
          (d) =>
              d.title.toLowerCase().contains(q) ||
              (d.description != null && d.description!.toLowerCase().contains(q)) ||
              (d.subject != null && d.subject!.toLowerCase().contains(q)),
        )
        .toList(),
    routines: routines
        .where(
          (r) =>
              r.title.toLowerCase().contains(q) ||
              (r.description != null && r.description!.toLowerCase().contains(q)) ||
              r.timeOfDay.toLowerCase().contains(q),
        )
        .toList(),
    calendarEvents: calendar
        .where(
          (e) =>
              e.title.toLowerCase().contains(q) ||
              (e.description != null && e.description!.toLowerCase().contains(q)) ||
              (e.category != null && e.category!.toLowerCase().contains(q)),
        )
        .toList(),
    focusSessions: focus
        .where(
          (s) =>
              (s.presetId != null && s.presetId!.toLowerCase().contains(q)) ||
              (s.reflection != null && s.reflection!.toLowerCase().contains(q)) ||
              s.status.toLowerCase().contains(q),
        )
        .toList(),
  );
});

String _plainPreview(String content) {
  final text = content
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
      .replaceAll(RegExp(r'^\s*[-*]\s\[[ xX]\]\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*|__|~~|`'), '')
      .replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^>\s?', multiLine: true), '');
  return text.trim();
}

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(globalSearchQueryProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final history = ref.read(recentSearchesProvider);
    if (!history.contains(trimmed)) {
      ref.read(recentSearchesProvider.notifier).state = [
        trimmed,
        ...history.take(7),
      ];
    }
  }

  void _applyQuery(String q) {
    _searchCtrl.text = q;
    ref.read(globalSearchQueryProvider.notifier).state = q;
    _submitSearch(q);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(globalSearchQueryProvider);
    final selectedCategory = ref.watch(globalSearchCategoryProvider);
    final results = ref.watch(comprehensiveSearchResultsProvider);
    final recentSearches = ref.watch(recentSearchesProvider);
    final hasQuery = query.trim().isNotEmpty;

    return UiPage(
      header: const UiHeader(
        title: 'Omni Search',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Unified real-time search across all 11 features.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dynamic Search Bar
          UiCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: hasQuery
                      ? context.uiColors.primary
                      : context.uiColors.foregroundMuted,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: false,
                    style: context.uiText.body,
                    decoration: InputDecoration(
                      hintText: 'Search notes, tasks, courses, habits, goals...',
                      hintStyle: context.uiText.caption.copyWith(
                        color: context.uiColors.foregroundMuted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) {
                      ref.read(globalSearchQueryProvider.notifier).state = v;
                    },
                    onSubmitted: _submitSearch,
                  ),
                ),
                if (hasQuery)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchCtrl.clear();
                      ref.read(globalSearchQueryProvider.notifier).state = '';
                    },
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: context.uiColors.primary,
                    ),
                    tooltip: 'Ask AI',
                    onPressed: () => context.push('/ai'),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Horizontal Category Filter Pills with Live Badges
          if (hasQuery && !results.isEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryChip(
                    label: 'All',
                    count: results.totalCount,
                    selected: selectedCategory == 'all',
                    onTap: () => ref
                        .read(globalSearchCategoryProvider.notifier)
                        .state = 'all',
                  ),
                  if (results.notes.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Notes',
                      count: results.notes.length,
                      icon: Icons.notes_rounded,
                      selected: selectedCategory == 'notes',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'notes',
                    ),
                  ],
                  if (results.tasks.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Tasks',
                      count: results.tasks.length,
                      icon: Icons.checklist_rounded,
                      selected: selectedCategory == 'tasks',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'tasks',
                    ),
                  ],
                  if (results.journal.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Journal',
                      count: results.journal.length,
                      icon: Icons.menu_book_outlined,
                      selected: selectedCategory == 'journal',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'journal',
                    ),
                  ],
                  if (results.courses.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Courses',
                      count: results.courses.length,
                      icon: Icons.school_outlined,
                      selected: selectedCategory == 'courses',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'courses',
                    ),
                  ],
                  if (results.habits.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Habits',
                      count: results.habits.length,
                      icon: Icons.repeat_rounded,
                      selected: selectedCategory == 'habits',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'habits',
                    ),
                  ],
                  if (results.goals.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Goals',
                      count: results.goals.length,
                      icon: Icons.flag_outlined,
                      selected: selectedCategory == 'goals',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'goals',
                    ),
                  ],
                  if (results.decks.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Flashcards',
                      count: results.decks.length,
                      icon: Icons.style_outlined,
                      selected: selectedCategory == 'decks',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'decks',
                    ),
                  ],
                  if (results.calendarEvents.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Calendar',
                      count: results.calendarEvents.length,
                      icon: Icons.calendar_today_outlined,
                      selected: selectedCategory == 'calendar',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'calendar',
                    ),
                  ],
                  if (results.routines.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Routines',
                      count: results.routines.length,
                      icon: Icons.wb_sunny_outlined,
                      selected: selectedCategory == 'routines',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'routines',
                    ),
                  ],
                  if (results.focusSessions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Focus',
                      count: results.focusSessions.length,
                      icon: Icons.timer_outlined,
                      selected: selectedCategory == 'focus',
                      onTap: () => ref
                          .read(globalSearchCategoryProvider.notifier)
                          .state = 'focus',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Content States
          if (!hasQuery) ...[
            // -------------------------------------------------------------
            // DISCOVER & QUICK ACTIONS HUB
            // -------------------------------------------------------------
            if (recentSearches.isNotEmpty) ...[
              Row(
                children: [
                  Text('Recent Searches', style: context.uiText.bodyStrong),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ref.read(recentSearchesProvider.notifier).state = const [];
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recentSearches.map((s) {
                  return ActionChip(
                    avatar: const Icon(Icons.history_rounded, size: 14),
                    label: Text(s),
                    onPressed: () => _applyQuery(s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            Text('Quick Creation', style: context.uiText.bodyStrong),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _QuickActionCard(
                  icon: Icons.edit_note_rounded,
                  label: 'New Note',
                  color: const Color(0xFF6366F1),
                  onTap: () => context.push('/notes/new'),
                ),
                _QuickActionCard(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Add Task',
                  color: const Color(0xFF10B981),
                  onTap: () => context.push('/todos/new'),
                ),
                _QuickActionCard(
                  icon: Icons.menu_book_outlined,
                  label: 'Journal',
                  color: const Color(0xFFF59E0B),
                  onTap: () => context.push('/journal/new'),
                ),
                _QuickActionCard(
                  icon: Icons.timer_outlined,
                  label: 'Start Focus',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => context.push('/clock'),
                ),
                _QuickActionCard(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Ask AI',
                  color: const Color(0xFFEC4899),
                  onTap: () => context.push('/ai'),
                ),
                _QuickActionCard(
                  icon: Icons.calendar_month_outlined,
                  label: 'Calendar',
                  color: const Color(0xFF3B82F6),
                  onTap: () => context.push('/calendar'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Text('Browse All Features', style: context.uiText.bodyStrong),
            const SizedBox(height: 10),
            _FeatureRow(
              icon: Icons.school_outlined,
              title: 'Academics & Courses',
              subtitle: 'Subjects, grades, assessments, and study schedules',
              onTap: () => context.push('/courses'),
            ),
            const SizedBox(height: 8),
            _FeatureRow(
              icon: Icons.style_outlined,
              title: 'Flashcard Decks',
              subtitle: 'Spaced repetition decks with SM-2 mastery review',
              onTap: () => context.push('/flashcards'),
            ),
            const SizedBox(height: 8),
            _FeatureRow(
              icon: Icons.repeat_rounded,
              title: 'Habit Tracker',
              subtitle: 'Daily streaks, completion calendars, and analytics',
              onTap: () => context.push('/habits'),
            ),
            const SizedBox(height: 8),
            _FeatureRow(
              icon: Icons.wb_sunny_outlined,
              title: 'Morning & Evening Routines',
              subtitle: 'Structured daily checklists for optimal focus',
              onTap: () => context.push('/routines'),
            ),
            const SizedBox(height: 8),
            _FeatureRow(
              icon: Icons.flag_outlined,
              title: 'Goals & Milestones',
              subtitle: 'Long-term aspirations with progress checkpoints',
              onTap: () => context.push('/goals'),
            ),
          ] else if (results.isEmpty) ...[
            // -------------------------------------------------------------
            // NO MATCHES STATE + ASK AI ACTION
            // -------------------------------------------------------------
            const SizedBox(height: 32),
            UiEmptyState(
              title: 'No results found',
              message: 'Nothing matched "$query" across your local workspace.',
              icon: Icons.search_off_rounded,
            ),
            const SizedBox(height: 20),
            Center(
              child: UiButton(
                label: 'Ask AI about "$query"',
                leadingIcon: Icons.auto_awesome_rounded,
                variant: UiVariant.primary,
                onPressed: () => context.push('/ai'),
              ),
            ),
          ] else ...[
            // -------------------------------------------------------------
            // COMPREHENSIVE SEARCH RESULTS LIST
            // -------------------------------------------------------------
            Row(
              children: [
                Text(
                  'Found ${results.totalCount} matches',
                  style: context.uiText.bodyStrong,
                ),
                const Spacer(),
                if (selectedCategory != 'all')
                  TextButton(
                    onPressed: () => ref
                        .read(globalSearchCategoryProvider.notifier)
                        .state = 'all',
                    child: const Text('Show All'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Notes Section
            if ((selectedCategory == 'all' || selectedCategory == 'notes') &&
                results.notes.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.notes_rounded,
                title: 'Notes',
                count: results.notes.length,
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(height: 8),
              ...results.notes.map(
                (n) => _ResultItemCard(
                  icon: Icons.notes_rounded,
                  badgeLabel: 'Note',
                  badgeIntent: UiIntent.primary,
                  title: n.title.isEmpty ? 'Untitled Note' : n.title,
                  subtitle: _plainPreview(n.content),
                  timestamp: n.createdAt,
                  onTap: () => context.push('/notes/${n.id}'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Tasks Section
            if ((selectedCategory == 'all' || selectedCategory == 'tasks') &&
                results.tasks.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.checklist_rounded,
                title: 'Tasks',
                count: results.tasks.length,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(height: 8),
              ...results.tasks.map(
                (t) => _ResultItemCard(
                  icon: Icons.checklist_rounded,
                  badgeLabel: t.isCompleted ? 'Done' : 'Task',
                  badgeIntent:
                      t.isCompleted ? UiIntent.success : UiIntent.warning,
                  title: t.title,
                  subtitle: t.subtitle.isNotEmpty
                      ? t.subtitle
                      : (t.details ?? 'No additional details'),
                  onTap: () => context.push('/todos/edit/${t.id}'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Journal Section
            if ((selectedCategory == 'all' || selectedCategory == 'journal') &&
                results.journal.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.menu_book_outlined,
                title: 'Journal Entries',
                count: results.journal.length,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 8),
              ...results.journal.map(
                (j) => _ResultItemCard(
                  icon: Icons.menu_book_outlined,
                  badgeLabel: j.mood ?? 'Journal',
                  badgeIntent: UiIntent.info,
                  title: j.title.isEmpty ? 'Untitled Entry' : j.title,
                  subtitle: _plainPreview(j.entry),
                  timestamp: j.createdAt,
                  onTap: () => context.push('/journal/${j.id}'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Courses Section
            if ((selectedCategory == 'all' || selectedCategory == 'courses') &&
                results.courses.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.school_outlined,
                title: 'Academics & Courses',
                count: results.courses.length,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 8),
              ...results.courses.map(
                (c) => _ResultItemCard(
                  icon: Icons.school_outlined,
                  badgeLabel: c.code ?? 'Course',
                  badgeIntent: UiIntent.primary,
                  title: c.name,
                  subtitle:
                      'Instructor: ${c.instructor ?? "N/A"} · ${c.room ?? ""}',
                  onTap: () => context.push('/courses'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Flashcards Section
            if ((selectedCategory == 'all' || selectedCategory == 'decks') &&
                results.decks.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.style_outlined,
                title: 'Flashcard Decks',
                count: results.decks.length,
                color: const Color(0xFFEC4899),
              ),
              const SizedBox(height: 8),
              ...results.decks.map(
                (d) => _ResultItemCard(
                  icon: Icons.style_outlined,
                  badgeLabel: 'Deck',
                  badgeIntent: UiIntent.warning,
                  title: d.title,
                  subtitle: d.description ?? 'Tap to study cards',
                  onTap: () => context.push('/flashcards/${d.id}'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Habits Section
            if ((selectedCategory == 'all' || selectedCategory == 'habits') &&
                results.habits.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.repeat_rounded,
                title: 'Habits',
                count: results.habits.length,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(height: 8),
              ...results.habits.map(
                (h) => _ResultItemCard(
                  icon: Icons.repeat_rounded,
                  badgeLabel: h.category ?? 'Habit',
                  badgeIntent: UiIntent.success,
                  title: h.title,
                  subtitle: h.subtitle.isNotEmpty
                      ? h.subtitle
                      : (h.notes ?? 'Track daily consistency'),
                  onTap: () => context.push('/habits'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Goals Section
            if ((selectedCategory == 'all' || selectedCategory == 'goals') &&
                results.goals.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.flag_outlined,
                title: 'Goals',
                count: results.goals.length,
                color: const Color(0xFF3B82F6),
              ),
              const SizedBox(height: 8),
              ...results.goals.map(
                (g) => _ResultItemCard(
                  icon: Icons.flag_outlined,
                  badgeLabel: 'Goal',
                  badgeIntent: UiIntent.bullish,
                  title: g.title,
                  subtitle: 'Target: ${g.deadline != null ? DateFormat.yMMMd().format(g.deadline!) : "Ongoing"} · ${g.progressPercent}%',
                  onTap: () => context.push('/goals'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Calendar Section
            if ((selectedCategory == 'all' || selectedCategory == 'calendar') &&
                results.calendarEvents.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.calendar_today_outlined,
                title: 'Calendar Events',
                count: results.calendarEvents.length,
                color: const Color(0xFF06B6D4),
              ),
              const SizedBox(height: 8),
              ...results.calendarEvents.map(
                (e) => _ResultItemCard(
                  icon: Icons.calendar_today_outlined,
                  badgeLabel: DateFormat.jm().format(e.startTime),
                  badgeIntent: UiIntent.info,
                  title: e.title,
                  subtitle:
                      '${DateFormat.yMMMd().format(e.startTime)} · ${e.category ?? "Event"}',
                  onTap: () => context.push('/calendar'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Routines Section
            if ((selectedCategory == 'all' || selectedCategory == 'routines') &&
                results.routines.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.wb_sunny_outlined,
                title: 'Routines',
                count: results.routines.length,
                color: const Color(0xFFF97316),
              ),
              const SizedBox(height: 8),
              ...results.routines.map(
                (r) => _ResultItemCard(
                  icon: Icons.wb_sunny_outlined,
                  badgeLabel: r.timeOfDay,
                  badgeIntent: UiIntent.neutral,
                  title: r.title,
                  subtitle: r.description ?? 'Daily checklist steps',
                  onTap: () => context.push('/routines'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Focus Sessions Section
            if ((selectedCategory == 'all' || selectedCategory == 'focus') &&
                results.focusSessions.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.timer_outlined,
                title: 'Focus Sessions',
                count: results.focusSessions.length,
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(height: 8),
              ...results.focusSessions.map(
                (f) => _ResultItemCard(
                  icon: Icons.timer_outlined,
                  badgeLabel: '${f.durationMinutes}m',
                  badgeIntent: f.status == 'completed'
                      ? UiIntent.success
                      : UiIntent.neutral,
                  title: '${f.durationMinutes} min focus session',
                  subtitle: f.reflection != null && f.reflection!.isNotEmpty
                      ? '"${f.reflection}"'
                      : 'Started ${DateFormat.yMMMd().add_jm().format(f.startedAt)}',
                  onTap: () => FocusHistoryScreen.show(context),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.count,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? context.uiColors.primary
              : context.uiColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? context.uiColors.primary
                : context.uiColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected
                    ? context.uiColors.onPrimary
                    : context.uiColors.foregroundMuted,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? context.uiColors.onPrimary
                    : context.uiColors.foreground,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? context.uiColors.onPrimary.withValues(alpha: 0.18)
                    : context.uiColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? context.uiColors.onPrimary
                      : context.uiColors.foregroundMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: context.uiColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.uiColors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: UiCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.uiColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: context.uiColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.uiText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.uiText.caption),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.uiColors.foregroundMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(title, style: context.uiText.bodyStrong),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultItemCard extends StatelessWidget {
  const _ResultItemCard({
    required this.icon,
    required this.badgeLabel,
    required this.badgeIntent,
    required this.title,
    required this.subtitle,
    this.timestamp,
    required this.onTap,
  });

  final IconData icon;
  final String badgeLabel;
  final UiIntent badgeIntent;
  final String title;
  final String subtitle;
  final DateTime? timestamp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: UiCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: badgeIntent.color(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: badgeIntent.color(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: context.uiText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        UiBadge(
                          label: badgeLabel,
                          intent: badgeIntent,
                          size: UiSize.xs,
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.uiText.caption.copyWith(
                          color: context.uiColors.foregroundMuted,
                        ),
                      ),
                    ],
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().format(timestamp!),
                        style: context.uiText.caption.copyWith(
                          fontSize: 10,
                          color: context.uiColors.foregroundMuted.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: context.uiColors.foregroundMuted.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
