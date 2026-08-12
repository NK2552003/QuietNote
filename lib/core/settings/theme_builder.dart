import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';

/// Rebuilds the design-system theme for the user's chosen accent and text
/// size. The UI kit has no copyWith on [UiColors], so the accent-aware
/// colours are rebuilt field by field here — everything except the primary
/// pair stays exactly as the kit defines it.
UiTheme buildUiTheme({
  required Brightness brightness,
  required AppSettings settings,
}) {
  final UiColors base =
      brightness == Brightness.dark ? UiColors.dark() : UiColors.light();
  final Color? accent = settings.accent.color;
  final UiColors colors = accent == null
      ? base
      : _withPrimary(
          base,
          accent,
          _shade(accent, brightness == Brightness.dark ? 0.14 : -0.10),
        );

  final UiTypography typography =
      UiTypography.standard().scaled(settings.textSize.factor);

  return brightness == Brightness.dark
      ? UiTheme.dark(colors: colors, typography: typography)
      : UiTheme.light(colors: colors, typography: typography);
}

/// Lightens (positive amount) or darkens (negative amount) a colour.
Color _shade(Color color, double amount) {
  final HSLColor hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor();
}

UiColors _withPrimary(UiColors base, Color primary, Color primaryHover) =>
    UiColors(
      background: base.background,
      surface: base.surface,
      surfaceMuted: base.surfaceMuted,
      surfaceHover: base.surfaceHover,
      overlay: base.overlay,
      border: base.border,
      borderStrong: base.borderStrong,
      foreground: base.foreground,
      foregroundMuted: base.foregroundMuted,
      foregroundSubtle: base.foregroundSubtle,
      primary: primary,
      primaryHover: primaryHover,
      onPrimary: base.brightnessOnPrimary(primary),
      secondary: base.secondary,
      onSecondary: base.onSecondary,
      bullish: base.bullish,
      bearish: base.bearish,
      warning: base.warning,
      info: base.info,
      destructive: base.destructive,
      onDestructive: base.onDestructive,
      focusRing: primary,
      disabledBackground: base.disabledBackground,
      disabledForeground: base.disabledForeground,
      series: base.series,
    );

extension _OnPrimary on UiColors {
  /// Picks readable text for a custom accent background.
  Color brightnessOnPrimary(Color primary) =>
      primary.computeLuminance() > 0.5 ? const Color(0xFF16130F) : Colors.white;
}
