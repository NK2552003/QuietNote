import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Theme mode, accent colour and text size — applied app-wide the moment
/// they change.
class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.ui;
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    final SettingsController controller = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      title: 'Appearance',
      subtitle: 'How QuietNote looks while you study.',
      children: <Widget>[
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Preview', style: context.uiText.bodyStrong),
              SizedBox(height: context.sp(theme.spacing.md)),
              Container(
                padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
                decoration: BoxDecoration(
                  color: theme.colors.surfaceMuted,
                  borderRadius: context.radius(theme.radii.lg),
                  border: Border.all(color: theme.colors.border),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: context.sz(38),
                      height: context.sz(38),
                      decoration: BoxDecoration(
                        color: settings.accent.swatch,
                        borderRadius: context.radius(theme.radii.md),
                      ),
                      child: Icon(
                        Icons.check,
                        size: context.sz(theme.sizes.iconSm),
                        color: theme.colors.surface,
                      ),
                    ),
                    SizedBox(width: context.sp(theme.spacing.md)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Revise chapter 4',
                            style: context.uiText.bodyStrong.copyWith(
                              fontSize: context.uiText.bodyStrong.fontSize! *
                                  settings.textSize.factor,
                            ),
                          ),
                          Text(
                            'Due today · Physics',
                            style: context.uiText.caption.copyWith(
                              color: theme.colors.foregroundMuted,
                              fontSize: context.uiText.caption.fontSize! *
                                  settings.textSize.factor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    UiBadge(
                      label: settings.themeModeLabel,
                      intent: UiIntent.info,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'Theme',
          description: 'System follows your phone\'s light/dark setting.',
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
              child: UiToggleGroup<ThemeMode>(
                value: settings.themeMode,
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
                onChanged: (ThemeMode mode) => controller
                    .update((AppSettings s) => s.copyWith(themeMode: mode)),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Accent colour',
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
              child: Wrap(
                spacing: context.sp(theme.spacing.md),
                runSpacing: context.sp(theme.spacing.md),
                children: <Widget>[
                  for (final UiAccent accent in UiAccent.values)
                    _AccentSwatch(
                      accent: accent,
                      selected: settings.accent == accent,
                      onTap: () => controller.update(
                        (AppSettings s) => s.copyWith(accent: accent),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Text size',
          description: 'Bigger text for long revision sessions.',
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
              child: UiRadioGroup<UiTextSize>(
                value: settings.textSize,
                options: <UiOption<UiTextSize>>[
                  for (final UiTextSize size in UiTextSize.values)
                    UiOption<UiTextSize>(
                      value: size,
                      label: size.label,
                      trailingLabel:
                          '${(size.factor * 100).round()}%',
                    ),
                ],
                onChanged: (UiTextSize size) => controller
                    .update((AppSettings s) => s.copyWith(textSize: size)),
              ),
            ),
          ],
        ),
        UiButton(
          label: 'Reset appearance',
          variant: UiVariant.secondary,
          leadingIcon: Icons.restart_alt,
          onPressed: () async {
            await controller.update(
              (AppSettings s) => s.copyWith(
                themeMode: ThemeMode.system,
                accent: UiAccent.graphite,
                textSize: UiTextSize.standard,
              ),
            );
            if (context.mounted) {
              UiToast.show(
                context,
                title: 'Appearance reset',
                message: 'Back to the default look.',
                icon: Icons.restart_alt,
              );
            }
          },
        ),
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final UiAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: context.sz(44),
            height: context.sz(44),
            decoration: BoxDecoration(
              color: accent.swatch,
              borderRadius: context.radius(theme.radii.pill),
              border: Border.all(
                color: selected ? theme.colors.foreground : theme.colors.border,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    color: theme.colors.surface,
                    size: context.sz(theme.sizes.iconSm),
                  )
                : null,
          ),
          SizedBox(height: context.sp(theme.spacing.xs)),
          Text(
            accent.label,
            style: context.uiText.caption.copyWith(
              color: selected
                  ? theme.colors.foreground
                  : theme.colors.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
