import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/ai/local_ai_engine.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Settings hub: a student-account style header plus grouped section cards
/// that each open a focused sub-page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.ui;
    final AsyncValue<AppSettings> async = ref.watch(settingsProvider);
    final AppSettings settings = async.value ?? const AppSettings();
    final AiEngineState aiState = ref.watch(aiEngineProvider);

    final String aiSummary = switch (aiState) {
      AiEngineState.ready => 'Ready',
      AiEngineState.importing => 'Importing…',
      AiEngineState.failed => 'Needs attention',
      AiEngineState.missingModel => 'Not installed',
    };

    final String backupSummary = settings.lastBackupAt == null
        ? 'Never backed up'
        : 'Last ${_relative(settings.lastBackupAt!)}';

    return UiPage(
      header: const UiHeader(
        title: 'Settings',
        subtitle: 'Your study space, tuned to you.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ProfileCard(
            settings: settings,
            onTap: () => context.push('/settings/profile'),
          ),
          SizedBox(height: context.sp(theme.spacing.xl)),
          SettingsSection(
            title: 'Personalise',
            children: <Widget>[
              SettingsTile(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                description: 'Theme, accent colour and text size',
                value: '${settings.themeModeLabel} · ${settings.accent.label}',
                onTap: () => context.push('/settings/appearance'),
              ),
              SettingsTile(
                icon: Icons.notifications_none,
                title: 'Notifications',
                description: 'Reminders and quiet hours',
                value: settings.notificationsEnabled
                    ? '${settings.activeReminderCount} on'
                    : 'Off',
                onTap: () => context.push('/settings/notifications'),
              ),
            ],
          ),
          SettingsSection(
            title: 'Intelligence',
            children: <Widget>[
              SettingsTile(
                icon: Icons.auto_awesome,
                title: 'AI Capture',
                description: 'Local model and capture defaults',
                value: aiSummary,
                intent: aiState == AiEngineState.ready
                    ? UiIntent.success
                    : aiState == AiEngineState.failed
                    ? UiIntent.danger
                    : UiIntent.warning,
                onTap: () => context.push('/settings/ai'),
              ),
            ],
          ),
          SettingsSection(
            title: 'Your data',
            description: 'Everything stays on this device.',
            children: <Widget>[
              SettingsTile(
                icon: Icons.backup_outlined,
                title: 'Data & backup',
                description: 'Export, merge a backup, storage usage',
                value: backupSummary,
                onTap: () => context.push('/settings/data'),
              ),
            ],
          ),
          SettingsSection(
            title: 'About',
            children: <Widget>[
              SettingsTile(
                icon: Icons.info_outline,
                title: 'About QuietNote',
                description: 'Version, privacy and licences',
                onTap: () => context.push('/settings/about'),
              ),
            ],
          ),
          Center(
            child: Text(
              'QuietNote · offline-first study companion',
              style: context.uiText.caption.copyWith(
                color: theme.colors.foregroundSubtle,
              ),
            ),
          ),
          SizedBox(height: context.sp(theme.spacing.xxl)),
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final Duration diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.yMMMd().format(when);
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.settings, required this.onTap});

  final AppSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.ui;
    final String initials = settings.displayName.trim().isEmpty
        ? 'S'
        : settings.displayName.trim()[0].toUpperCase();
    final ImageProvider? profileImage =
        settings.profileImagePath.isNotEmpty &&
            File(settings.profileImagePath).existsSync()
        ? FileImage(File(settings.profileImagePath))
        : null;

    return UiCard(
      variant: UiCardVariant.elevated,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: context.sz(56),
            height: context.sz(56),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              image: profileImage == null
                  ? null
                  : DecorationImage(image: profileImage, fit: BoxFit.cover),
              color: settings.accent.swatch.withValues(alpha: 0.14),
              borderRadius: context.radius(theme.radii.pill),
              border: Border.all(
                color: settings.accent.swatch.withValues(alpha: 0.35),
              ),
            ),
            child: profileImage == null
                ? Text(
                    initials,
                    style: context.uiText.title.copyWith(
                      color: settings.accent.swatch,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          SizedBox(width: context.sp(theme.spacing.md)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  settings.displayName,
                  style: context.uiText.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.foreground,
                  ),
                ),
                if (settings.profileEmail.isNotEmpty) ...[
                  SizedBox(height: context.sp(theme.spacing.xxs)),
                  Text(
                    settings.profileEmail,
                    style: context.uiText.caption.copyWith(
                      color: theme.colors.foregroundMuted,
                    ),
                  ),
                ],
                SizedBox(height: context.sp(theme.spacing.xxs)),
                Wrap(
                  spacing: context.sp(theme.spacing.xs),
                  runSpacing: context.sp(theme.spacing.xs),
                  children: const <Widget>[
                    UiBadge(
                      label: 'Offline-first',
                      icon: Icons.wifi_off,
                      intent: UiIntent.info,
                    ),
                    UiBadge(
                      label: 'No account needed',
                      icon: Icons.lock_outline,
                    ),
                  ],
                ),
              ],
            ),
          ),
          UiIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit profile',
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}
