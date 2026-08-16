import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Theme mode, accent colour, text size, and navigation dock size & positioning.
class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.ui;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    final SettingsController controller = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      title: 'Appearance',
      subtitle: 'How QuietNote looks and feels while you study.',
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

        // ── Theme Section ──
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

        // ── Accent Colour Section ──
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

        // ── Navigation Dock Customization Section ──
        SettingsSection(
          title: 'Navigation Dock',
          description:
              'Customize the size and hand positioning of the floating bottom dock.',
          children: <Widget>[
            // Dock Live Interactive Preview
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.sp(theme.spacing.lg),
                context.sp(theme.spacing.md),
                context.sp(theme.spacing.lg),
                context.sp(theme.spacing.sm),
              ),
              child: _DockPreviewWidget(
                settings: settings,
                isDark: isDark,
                theme: theme,
              ),
            ),

            // Sizing Option
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.sp(theme.spacing.lg),
                vertical: context.sp(theme.spacing.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dock Sizing',
                    style: context.uiText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.foregroundMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  UiToggleGroup<UiDockSize>(
                    value: settings.dockSize,
                    options: const <UiToggleOption<UiDockSize>>[
                      UiToggleOption<UiDockSize>(
                        value: UiDockSize.compact,
                        label: 'Compact',
                        icon: Icons.compress_rounded,
                      ),
                      UiToggleOption<UiDockSize>(
                        value: UiDockSize.standard,
                        label: 'Standard',
                        icon: Icons.view_comfortable_rounded,
                      ),
                      UiToggleOption<UiDockSize>(
                        value: UiDockSize.spacious,
                        label: 'Spacious',
                        icon: Icons.expand_rounded,
                      ),
                    ],
                    onChanged: (UiDockSize size) => controller
                        .update((AppSettings s) => s.copyWith(dockSize: size)),
                  ),
                ],
              ),
            ),

            // Horizontal Alignment / Hand Position Option
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.sp(theme.spacing.lg),
                context.sp(theme.spacing.sm),
                context.sp(theme.spacing.lg),
                context.sp(theme.spacing.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dock Alignment',
                    style: context.uiText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.foregroundMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  UiToggleGroup<UiDockPosition>(
                    value: settings.dockPosition,
                    options: const <UiToggleOption<UiDockPosition>>[
                      UiToggleOption<UiDockPosition>(
                        value: UiDockPosition.left,
                        label: 'Left',
                        icon: Icons.align_horizontal_left_rounded,
                      ),
                      UiToggleOption<UiDockPosition>(
                        value: UiDockPosition.center,
                        label: 'Center',
                        icon: Icons.align_horizontal_center_rounded,
                      ),
                      UiToggleOption<UiDockPosition>(
                        value: UiDockPosition.right,
                        label: 'Right',
                        icon: Icons.align_horizontal_right_rounded,
                      ),
                    ],
                    onChanged: (UiDockPosition pos) => controller.update(
                        (AppSettings s) => s.copyWith(dockPosition: pos)),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── Text Size Section ──
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
                dockSize: UiDockSize.standard,
                dockPosition: UiDockPosition.center,
              ),
            );
            if (context.mounted) {
              UiToast.show(
                context,
                title: 'Appearance reset',
                message: 'Back to the default look and dock layout.',
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

class _DockPreviewWidget extends StatefulWidget {
  const _DockPreviewWidget({
    required this.settings,
    required this.isDark,
    required this.theme,
  });

  final AppSettings settings;
  final bool isDark;
  final UiTheme theme;

  @override
  State<_DockPreviewWidget> createState() => _DockPreviewWidgetState();
}

class _DockPreviewWidgetState extends State<_DockPreviewWidget> {
  int _previewActiveIndex = 0;

  IconData _getPreviewIcon(int index, bool isActive) {
    switch (index) {
      case 0:
        return isActive ? Icons.home_rounded : Icons.home_outlined;
      case 1:
        return isActive ? Icons.task_alt_rounded : Icons.checklist_outlined;
      case 2:
        return Icons.grid_view_rounded;
      case 3:
        return isActive ? Icons.sticky_note_2_rounded : Icons.notes_outlined;
      case 4:
        return isActive ? Icons.settings_rounded : Icons.settings_outlined;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dockSize = widget.settings.dockSize;
    final dockPosition = widget.settings.dockPosition;
    final isDark = widget.isDark;
    final theme = widget.theme;

    // Scale down for compact preview representation
    const double previewScale = 0.82;
    final double pWidth = dockSize.width * previewScale;
    final double pHeight = dockSize.height * previewScale;
    final double pRadius = dockSize.borderRadius * previewScale;
    final double pIconSize = dockSize.iconSize * previewScale;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141312) : const Color(0xFFF3F1ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Live Dock Preview',
                style: context.uiText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: theme.colors.foregroundMuted,
                ),
              ),
              UiBadge(
                label: '${dockSize.label} · ${dockPosition.label}',
                intent: UiIntent.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: dockPosition.alignment,
            child: Container(
              margin: EdgeInsets.only(
                left: dockPosition == UiDockPosition.left ? 8 : 0,
                right: dockPosition == UiDockPosition.right ? 8 : 0,
              ),
              width: pWidth,
              height: pHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(pRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(pRadius),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xEE1A1817)
                        : theme.colors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(pRadius),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.black.withValues(alpha: 0.10),
                      width: 1.0,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Active sliding bubble indicator matching current selection
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.fastOutSlowIn,
                        alignment:
                            Alignment(-1.0 + (_previewActiveIndex * 0.5), 0.0),
                        child: FractionallySizedBox(
                          widthFactor: 0.20,
                          heightFactor: 1.0,
                          child: Padding(
                            padding: const EdgeInsets.all(3.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.14)
                                    : widget.settings.accent.swatch
                                        .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  (pRadius - 3.0).clamp(6.0, 24.0),
                                ),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.22)
                                      : widget.settings.accent.swatch
                                          .withValues(alpha: 0.28),
                                  width: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 5 evenly distributed 20% width slots with centered icons
                      Row(
                        children: [
                          for (int i = 0; i < 5; i++)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _previewActiveIndex = i);
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Center(
                                  child: AnimatedScale(
                                    scale: _previewActiveIndex == i ? 1.15 : 1.0,
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    child: Icon(
                                      _getPreviewIcon(
                                          i, _previewActiveIndex == i),
                                      size: pIconSize,
                                      color: _previewActiveIndex == i
                                          ? (isDark
                                              ? Colors.white
                                              : widget.settings.accent.swatch)
                                          : (isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.45)
                                              : theme.colors.foregroundMuted),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
