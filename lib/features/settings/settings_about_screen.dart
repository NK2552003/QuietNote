import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// App identity, privacy promise and credits.
class SettingsAboutScreen extends ConsumerWidget {
  const SettingsAboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.ui;
    return SettingsSubPage(
      title: 'About',
      subtitle: 'A quiet, offline study companion.',
      children: <Widget>[
        UiCard(
          variant: UiCardVariant.elevated,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: context.sz(48),
                    height: context.sz(48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colors.primary.withValues(alpha: 0.12),
                      borderRadius: context.radius(theme.radii.lg),
                    ),
                    child: Icon(
                      Icons.nights_stay_outlined,
                      color: theme.colors.primary,
                      size: context.sz(theme.sizes.iconLg),
                    ),
                  ),
                  SizedBox(width: context.sp(theme.spacing.md)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('QuietNote', style: context.uiText.title),
                      Text(
                        'Version 1.0.0 · offline build',
                        style: context.uiText.caption
                            .copyWith(color: theme.colors.foregroundMuted),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: context.sp(theme.spacing.lg)),
              Text(
                'Notes, journal, habits, routines, goals and a study calendar — '
                'all in one place, all stored on your phone.',
                style: context.uiText.body,
              ),
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        const SettingsSection(
          title: 'Privacy',
          children: <Widget>[
            SettingsTile(
              icon: Icons.wifi_off_outlined,
              title: 'Works offline',
              description: 'No account, no sync server, no tracking.',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.phone_iphone,
              title: 'Data stays local',
              description: 'Your database never leaves the device unless you export it.',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.psychology_outlined,
              title: 'On-device AI',
              description: 'AI Capture runs the model locally, with no uploads.',
              showChevron: false,
            ),
          ],
        ),
        const SettingsSection(
          title: 'Built with',
          children: <Widget>[
            SettingsTile(
              icon: Icons.flutter_dash,
              title: 'Flutter & Riverpod',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.storage_outlined,
              title: 'Drift + SQLite',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.palette_outlined,
              title: 'QuietNote UI kit',
              showChevron: false,
            ),
          ],
        ),
        SettingsSection(
          title: 'Setup',
          children: <Widget>[
            SettingsTile(
              icon: Icons.restart_alt,
              title: 'Replay onboarding',
              description: 'Walk through the welcome flow again.',
              onTap: () async {
                await ref.read(settingsProvider.notifier).update(
                      (AppSettings s) => s.copyWith(onboardingComplete: false),
                    );
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ],
        ),
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}
