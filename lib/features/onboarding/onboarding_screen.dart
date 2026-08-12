import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/core/notifications/notification_service.dart';

/// Five-step first-run flow: welcome, tour, name, focus + look, reminders.
/// Everything picked here is written straight into `app_settings`, so the
/// rest of the app (theme, greeting, reminders) reflects it immediately.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

const List<String> _focusOptions = <String>[
  'Exams',
  'Assignments',
  'Reading',
  'Revision',
  'Projects',
  'Wellbeing',
  'Fitness',
  'Sleep',
];

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController();

  int _index = 0;
  static const int _stepCount = 5;

  // Local draft — written to settings when the user finishes.
  final Set<String> _focus = <String>{'Exams', 'Revision'};
  ThemeMode _themeMode = ThemeMode.system;
  UiAccent _accent = UiAccent.indigo;
  bool _reminders = true;
  bool _quietHours = true;
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish({bool skipped = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final String name = _name.text.trim();
    // Persist and navigate before invoking OS permission UI. Some Android
    // alarm/notification panels don't resolve until manually closed, which
    // previously left the Start button looking permanently stuck.
    final notificationsAllowed = skipped ? false : _reminders;
    await ref
        .read(settingsProvider.notifier)
        .update(
          (AppSettings s) => s.copyWith(
            onboardingComplete: true,
            displayName: name.isEmpty ? s.displayName : name,
            focusAreas: skipped ? s.focusAreas : _focus.toList(),
            themeMode: skipped ? s.themeMode : _themeMode,
            accent: skipped ? s.accent : _accent,
            notificationsEnabled: skipped
                ? s.notificationsEnabled
                : notificationsAllowed,
            habitReminders: skipped ? s.habitReminders : notificationsAllowed,
            taskReminders: skipped ? s.taskReminders : notificationsAllowed,
            calendarReminders: skipped
                ? s.calendarReminders
                : notificationsAllowed,
            quietHoursEnabled: skipped ? s.quietHoursEnabled : _quietHours,
          ),
        );
    if (!mounted) return;
    UiToast.show(
      context,
      title: skipped ? 'Setup skipped' : 'You\'re all set',
      message: skipped
          ? 'You can finish setup any time from Settings.'
          : notificationsAllowed
          ? 'Everything is saved on this device.'
          : 'Setup is saved. You can enable reminders later from Settings.',
      intent: UiIntent.success,
    );
    context.go('/');
    if (!skipped && _reminders) {
      Future<void>.delayed(const Duration(milliseconds: 300), () async {
        await NotificationService().requestPermissions();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool isLast = _index == _stepCount - 1;

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              index: _index,
              stepCount: _stepCount,
              onSkip: _saving ? null : () => _finish(skipped: true),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (int i) => setState(() => _index = i),
                children: <Widget>[
                  _WelcomeStep(),
                  _TourStep(),
                  _NameStep(controller: _name),
                  _FocusStep(
                    focus: _focus,
                    onToggle: (String tag) => setState(() {
                      if (_focus.contains(tag)) {
                        _focus.remove(tag);
                      } else {
                        _focus.add(tag);
                      }
                    }),
                    themeMode: _themeMode,
                    onThemeMode: (ThemeMode m) =>
                        setState(() => _themeMode = m),
                    accent: _accent,
                    onAccent: (UiAccent a) => setState(() => _accent = a),
                  ),
                  _RemindersStep(
                    reminders: _reminders,
                    onReminders: (bool v) => setState(() => _reminders = v),
                    quietHours: _quietHours,
                    onQuietHours: (bool v) => setState(() => _quietHours = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
              child: Row(
                children: <Widget>[
                  if (_index > 0)
                    UiButton(
                      label: 'Back',
                      variant: UiVariant.ghost,
                      leadingIcon: Icons.arrow_back,
                      onPressed: _saving ? null : () => _goTo(_index - 1),
                    ),
                  const Spacer(),
                  UiButton(
                    label: isLast ? 'Start using QuietNote' : 'Continue',
                    trailingIcon: isLast ? Icons.check : Icons.arrow_forward,
                    loading: _saving,
                    onPressed: _saving
                        ? null
                        : () => isLast ? _finish() : _goTo(_index + 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.index,
    required this.stepCount,
    required this.onSkip,
  });

  final int index;
  final int stepCount;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.sp(theme.spacing.lg),
        context.sp(theme.spacing.lg),
        context.sp(theme.spacing.lg),
        context.sp(theme.spacing.sm),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: List<Widget>.generate(stepCount, (int i) {
                final bool active = i <= index;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    height: context.sz(4),
                    margin: EdgeInsets.only(
                      right: context.sp(theme.spacing.xs),
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? theme.colors.primary
                          : theme.colors.border,
                      borderRadius: context.radius(theme.radii.pill),
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(width: context.sp(theme.spacing.md)),
          UiButton(
            label: 'Skip',
            variant: UiVariant.ghost,
            size: UiSize.sm,
            onPressed: onSkip,
          ),
        ],
      ),
    );
  }
}

/// Shared page scaffold: eyebrow, title, subtitle and scrollable body.
class _Step extends StatelessWidget {
  const _Step({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: context.sp(theme.spacing.lg),
        vertical: context.sp(theme.spacing.md),
      ),
      children: <Widget>[
        Text(
          eyebrow.toUpperCase(),
          style: context.uiText.caption.copyWith(
            color: theme.colors.primary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.sm)),
        Text(title, style: context.uiText.display),
        SizedBox(height: context.sp(theme.spacing.sm)),
        Text(
          subtitle,
          style: context.uiText.body.copyWith(
            color: theme.colors.foregroundMuted,
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        ...children,
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return _Step(
      eyebrow: 'Welcome',
      title: 'Your quiet study companion',
      subtitle:
          'Notes, journal, habits, routines, goals and a study calendar — one '
          'offline app that keeps everything on your phone.',
      children: <Widget>[
        UiCard(
          variant: UiCardVariant.elevated,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: context.sz(44),
                    height: context.sz(44),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colors.primary.withValues(alpha: 0.12),
                      borderRadius: context.radius(theme.radii.lg),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: theme.colors.primary,
                    ),
                  ),
                  SizedBox(width: context.sp(theme.spacing.md)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Private by default',
                          style: context.uiText.bodyStrong,
                        ),
                        Text(
                          'No account, no sync server, no tracking.',
                          style: context.uiText.caption.copyWith(
                            color: theme.colors.foregroundMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.sp(theme.spacing.lg)),
              Text(
                'Setup takes about a minute. You can change anything later in '
                'Settings.',
                style: context.uiText.body,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TourStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    const List<(IconData, String, String)> items = <(IconData, String, String)>[
      (
        Icons.checklist_outlined,
        'To-dos',
        'Deadlines, priorities and subtasks.',
      ),
      (
        Icons.repeat_outlined,
        'Habits',
        'Streaks for the things you repeat daily.',
      ),
      (Icons.notes_outlined, 'Notes', 'Lecture notes, tagged and searchable.'),
      (
        Icons.menu_book_outlined,
        'Journal',
        'Track mood and reflect after study.',
      ),
      (
        Icons.calendar_month_outlined,
        'Calendar',
        'Classes, exams and study blocks.',
      ),
      (
        Icons.auto_awesome,
        'AI Capture',
        'Type a sentence, get a structured item.',
      ),
    ];

    return _Step(
      eyebrow: 'What\'s inside',
      title: 'Everything a student juggles',
      subtitle:
          'Each area has its own screen, and Analytics ties them together.',
      children: <Widget>[
        for (final (IconData icon, String title, String desc) in items)
          Padding(
            padding: EdgeInsets.only(bottom: context.sp(theme.spacing.md)),
            child: UiCard(
              child: Row(
                children: <Widget>[
                  Container(
                    width: context.sz(40),
                    height: context.sz(40),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colors.surfaceMuted,
                      borderRadius: context.radius(theme.radii.md),
                      border: Border.all(color: theme.colors.border),
                    ),
                    child: Icon(
                      icon,
                      size: context.sz(theme.sizes.iconSm),
                      color: theme.colors.primary,
                    ),
                  ),
                  SizedBox(width: context.sp(theme.spacing.md)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: context.uiText.bodyStrong),
                        Text(
                          desc,
                          style: context.uiText.caption.copyWith(
                            color: theme.colors.foregroundMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return _Step(
      eyebrow: 'Step 3',
      title: 'What should we call you?',
      subtitle:
          'Used for the greeting on Home. Leave it blank to stay "Student".',
      children: <Widget>[
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              UiInput(
                controller: controller,
                hintText: 'Your first name',
                leadingIcon: Icons.person_outline,
                textInputAction: TextInputAction.done,
                maxLength: 24,
              ),
              SizedBox(height: context.sp(theme.spacing.md)),
              Container(
                padding: EdgeInsets.all(context.sp(theme.spacing.md)),
                decoration: BoxDecoration(
                  color: theme.colors.surfaceMuted,
                  borderRadius: context.radius(theme.radii.lg),
                  border: Border.all(color: theme.colors.border),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.wb_twilight,
                      size: context.sz(theme.sizes.iconSm),
                      color: theme.colors.foregroundMuted,
                    ),
                    SizedBox(width: context.sp(theme.spacing.sm)),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (BuildContext context, TextEditingValue v, _) {
                          final String name = v.text.trim().isEmpty
                              ? 'Student'
                              : v.text.trim();
                          return Text(
                            'Good morning, $name',
                            style: context.uiText.bodyStrong,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FocusStep extends StatelessWidget {
  const _FocusStep({
    required this.focus,
    required this.onToggle,
    required this.themeMode,
    required this.onThemeMode,
    required this.accent,
    required this.onAccent,
  });

  final Set<String> focus;
  final ValueChanged<String> onToggle;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  final UiAccent accent;
  final ValueChanged<UiAccent> onAccent;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return _Step(
      eyebrow: 'Step 4',
      title: 'Focus and feel',
      subtitle: 'Pick what you\'re working on, then make the app yours.',
      children: <Widget>[
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'This term I\'m focused on',
                style: context.uiText.bodyStrong,
              ),
              SizedBox(height: context.sp(theme.spacing.md)),
              Wrap(
                spacing: context.sp(theme.spacing.sm),
                runSpacing: context.sp(theme.spacing.sm),
                children: <Widget>[
                  for (final String tag in _focusOptions)
                    _Chip(
                      label: tag,
                      selected: focus.contains(tag),
                      onTap: () => onToggle(tag),
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.lg)),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Theme', style: context.uiText.bodyStrong),
              SizedBox(height: context.sp(theme.spacing.md)),
              UiToggleGroup<ThemeMode>(
                value: themeMode,
                expand: true,
                options: const <UiToggleOption<ThemeMode>>[
                  UiToggleOption<ThemeMode>(
                    value: ThemeMode.system,
                    label: 'System',
                    icon: Icons.brightness_auto_outlined,
                  ),
                  UiToggleOption<ThemeMode>(
                    value: ThemeMode.light,
                    label: 'Light',
                    icon: Icons.light_mode_outlined,
                  ),
                  UiToggleOption<ThemeMode>(
                    value: ThemeMode.dark,
                    label: 'Dark',
                    icon: Icons.dark_mode_outlined,
                  ),
                ],
                onChanged: onThemeMode,
              ),
              SizedBox(height: context.sp(theme.spacing.lg)),
              Text('Accent colour', style: context.uiText.bodyStrong),
              SizedBox(height: context.sp(theme.spacing.md)),
              Wrap(
                spacing: context.sp(theme.spacing.md),
                runSpacing: context.sp(theme.spacing.md),
                children: <Widget>[
                  for (final UiAccent option in UiAccent.values)
                    GestureDetector(
                      onTap: () => onAccent(option),
                      child: Column(
                        children: <Widget>[
                          Container(
                            width: context.sz(40),
                            height: context.sz(40),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: option.swatch,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: option == accent
                                    ? theme.colors.foreground
                                    : theme.colors.border,
                                width: option == accent ? 2.5 : 1,
                              ),
                            ),
                            child: option == accent
                                ? Icon(
                                    Icons.check,
                                    size: context.sz(theme.sizes.iconSm),
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          SizedBox(height: context.sp(theme.spacing.xs)),
                          Text(option.label, style: context.uiText.caption),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RemindersStep extends StatelessWidget {
  const _RemindersStep({
    required this.reminders,
    required this.onReminders,
    required this.quietHours,
    required this.onQuietHours,
  });

  final bool reminders;
  final ValueChanged<bool> onReminders;
  final bool quietHours;
  final ValueChanged<bool> onQuietHours;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return _Step(
      eyebrow: 'Last step',
      title: 'Gentle nudges, on your terms',
      subtitle: 'Reminders stay on the device and never leave it.',
      children: <Widget>[
        UiCard(
          child: Column(
            children: <Widget>[
              _SwitchRow(
                icon: Icons.notifications_active_outlined,
                title: 'Habit, task and class reminders',
                description: 'Nudges before deadlines and daily habits.',
                value: reminders,
                onChanged: onReminders,
              ),
              Divider(
                height: context.sp(theme.spacing.xl),
                color: theme.colors.border,
              ),
              _SwitchRow(
                icon: Icons.bedtime_outlined,
                title: 'Quiet hours (10 PM – 7 AM)',
                description: 'Nothing buzzes while you sleep.',
                value: quietHours,
                enabled: reminders,
                onChanged: onQuietHours,
              ),
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.lg)),
        const UiCallout(
          title: 'You control everything',
          message:
              'Change reminders, theme and your name any time in Settings. '
              'Your data can be exported as a single backup file.',
          intent: UiIntent.info,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Row(
      children: <Widget>[
        Icon(
          icon,
          size: context.sz(theme.sizes.iconSm),
          color: enabled ? theme.colors.primary : theme.colors.foregroundSubtle,
        ),
        SizedBox(width: context.sp(theme.spacing.md)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: context.uiText.bodyStrong),
              Text(
                description,
                style: context.uiText.caption.copyWith(
                  color: theme.colors.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: context.sp(theme.spacing.sm)),
        UiSwitch(
          value: value && enabled,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: context.sp(theme.spacing.md),
          vertical: context.sp(theme.spacing.sm),
        ),
        decoration: BoxDecoration(
          color: selected
              ? theme.colors.primary.withValues(alpha: 0.12)
              : theme.colors.surfaceMuted,
          borderRadius: context.radius(theme.radii.pill),
          border: Border.all(
            color: selected ? theme.colors.primary : theme.colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected) ...<Widget>[
              Icon(
                Icons.check,
                size: context.sz(14),
                color: theme.colors.primary,
              ),
              SizedBox(width: context.sp(theme.spacing.xs)),
            ],
            Text(
              label,
              style: context.uiText.label.copyWith(
                color: selected
                    ? theme.colors.primary
                    : theme.colors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
