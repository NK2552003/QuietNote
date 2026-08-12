import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// A titled block of settings rows, rendered as one card with hairline
/// dividers — the account-style layout used across every Settings page.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            left: context.sp(theme.spacing.xs),
            bottom: context.sp(theme.spacing.sm),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title.toUpperCase(),
                      style: context.uiText.caption.copyWith(
                        color: theme.colors.foregroundMuted,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (description != null) ...<Widget>[
                      SizedBox(height: context.sp(theme.spacing.xxs)),
                      Text(
                        description!,
                        style: context.uiText.caption.copyWith(
                          color: theme.colors.foregroundSubtle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        UiCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: theme.colors.border),
                children[i],
              ],
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
      ],
    );
  }
}

/// One tappable settings row: icon chip, title, optional description, and a
/// right-hand value / custom trailing widget.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.value,
    this.onTap,
    this.trailing,
    this.intent = UiIntent.neutral,
    this.showChevron = true,
    this.enabled = true,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final UiIntent intent;
  final bool showChevron;
  final bool enabled;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color accent = intent.color(context);
    final bool interactive = enabled && onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: interactive ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.sp(theme.spacing.lg),
              vertical: context.sp(theme.spacing.md),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: EdgeInsets.all(context.sp(theme.spacing.sm)),
                  decoration: BoxDecoration(
                    color: intent == UiIntent.neutral
                        ? theme.colors.surfaceMuted
                        : intent.surface(context),
                    borderRadius: context.radius(theme.radii.md),
                  ),
                  child: Icon(
                    icon,
                    size: context.sz(theme.sizes.iconMd),
                    color: intent == UiIntent.neutral
                        ? theme.colors.foregroundMuted
                        : accent,
                  ),
                ),
                SizedBox(width: context.sp(theme.spacing.md)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              style: context.uiText.bodyStrong.copyWith(
                                color: intent == UiIntent.danger
                                    ? theme.colors.destructive
                                    : theme.colors.foreground,
                              ),
                            ),
                          ),
                          if (badge != null) ...<Widget>[
                            SizedBox(width: context.sp(theme.spacing.xs)),
                            badge!,
                          ],
                        ],
                      ),
                      if (description != null) ...<Widget>[
                        SizedBox(height: context.sp(theme.spacing.xxs)),
                        Text(
                          description!,
                          style: context.uiText.caption.copyWith(
                            color: theme.colors.foregroundMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...<Widget>[
                  SizedBox(width: context.sp(theme.spacing.sm)),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: context.sz(140)),
                    child: Text(
                      value!,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.uiText.caption.copyWith(
                        color: theme.colors.foregroundMuted,
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...<Widget>[
                  SizedBox(width: context.sp(theme.spacing.sm)),
                  trailing!,
                ],
                if (interactive && showChevron && trailing == null) ...<Widget>[
                  SizedBox(width: context.sp(theme.spacing.xs)),
                  Icon(
                    Icons.chevron_right,
                    size: context.sz(theme.sizes.iconMd),
                    color: theme.colors.foregroundSubtle,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row whose trailing control is a switch.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      description: description,
      enabled: enabled,
      showChevron: false,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: UiSwitch(
        value: value,
        enabled: enabled,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// Sub-page scaffold: shared back header + page padding so every Settings
/// detail screen looks identical.
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return UiPage(
      header: UiHeader(
        title: title,
        subtitle: subtitle,
        leading: UiIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Formats minutes-since-midnight as a friendly 12-hour clock string.
String formatMinutes(int minutes) {
  final int h24 = (minutes ~/ 60) % 24;
  final int m = minutes % 60;
  final String suffix = h24 >= 12 ? 'PM' : 'AM';
  final int h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $suffix';
}
