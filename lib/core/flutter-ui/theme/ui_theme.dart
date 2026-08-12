import 'package:flutter/material.dart';

import 'ui_responsive.dart';
import 'ui_tokens.dart';

/// The theme object every component reads from. Injected once via
/// [UiThemeScope] (or as a Material [ThemeExtension]).
@immutable
class UiTheme extends ThemeExtension<UiTheme> {
  const UiTheme({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.radii,
    required this.borders,
    required this.shadows,
    required this.motion,
    required this.sizes,
    required this.breakpoints,
    required this.scaleConfig,
    required this.brightness,
  });

  final UiColors colors;
  final UiTypography typography;
  final UiSpacing spacing;
  final UiRadii radii;
  final UiBorders borders;
  final UiShadows shadows;
  final UiMotion motion;
  final UiSizes sizes;
  final UiBreakpoints breakpoints;
  final UiScaleConfig scaleConfig;
  final Brightness brightness;

  static UiTheme light({
    UiColors? colors,
    UiTypography? typography,
    UiSpacing spacing = const UiSpacing(),
    UiRadii radii = const UiRadii(),
    UiBorders borders = const UiBorders(),
    UiShadows? shadows,
    UiMotion motion = const UiMotion(),
    UiSizes sizes = const UiSizes(),
    UiBreakpoints breakpoints = const UiBreakpoints(),
    UiScaleConfig scaleConfig = const UiScaleConfig(),
  }) =>
      UiTheme(
        colors: colors ?? UiColors.light(),
        typography: typography ?? UiTypography.standard(),
        spacing: spacing,
        radii: radii,
        borders: borders,
        shadows: shadows ?? UiShadows.light(),
        motion: motion,
        sizes: sizes,
        breakpoints: breakpoints,
        scaleConfig: scaleConfig,
        brightness: Brightness.light,
      );

  static UiTheme dark({
    UiColors? colors,
    UiTypography? typography,
    UiSpacing spacing = const UiSpacing(),
    UiRadii radii = const UiRadii(),
    UiBorders borders = const UiBorders(),
    UiShadows? shadows,
    UiMotion motion = const UiMotion(),
    UiSizes sizes = const UiSizes(),
    UiBreakpoints breakpoints = const UiBreakpoints(),
    UiScaleConfig scaleConfig = const UiScaleConfig(),
  }) =>
      UiTheme(
        colors: colors ?? UiColors.dark(),
        typography: typography ?? UiTypography.standard(),
        spacing: spacing,
        radii: radii,
        borders: borders,
        shadows: shadows ?? UiShadows.dark(),
        motion: motion,
        sizes: sizes,
        breakpoints: breakpoints,
        scaleConfig: scaleConfig,
        brightness: Brightness.dark,
      );

  /// Builds a Material [ThemeData] that carries this design system, so plain
  /// Material widgets match the custom components.
  ThemeData toThemeData() {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.secondary,
      onSecondary: colors.onSecondary,
      error: colors.destructive,
      onError: colors.onDestructive,
      surface: colors.surface,
      onSurface: colors.foreground,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      fontFamily: typography.fontFamily,
      dividerColor: colors.border,
      // No Material ripple: interaction reads as a quiet background/border
      // shift, matching the rest of the system.
      splashFactory: NoSplash.splashFactory,
      splashColor: const Color(0x00000000),
      highlightColor: const Color(0x00000000),
      hoverColor: colors.surfaceHover,
      focusColor: colors.surfaceHover,
      textTheme: TextTheme(
        displayLarge: typography.display.copyWith(color: colors.foreground, fontSize: 42),
        displayMedium: typography.display.copyWith(color: colors.foreground, fontSize: 36),
        displaySmall: typography.display.copyWith(color: colors.foreground),
        headlineLarge: typography.title.copyWith(color: colors.foreground, fontSize: 28),
        headlineMedium: typography.title.copyWith(color: colors.foreground, fontSize: 24),
        headlineSmall: typography.title.copyWith(color: colors.foreground),
        titleLarge: typography.heading.copyWith(color: colors.foreground),
        titleMedium: typography.subheading.copyWith(color: colors.foreground),
        titleSmall: typography.bodyStrong.copyWith(color: colors.foreground),
        bodyLarge: typography.body.copyWith(color: colors.foreground, fontSize: 16),
        bodyMedium: typography.body.copyWith(color: colors.foreground),
        bodySmall: typography.caption.copyWith(color: colors.foreground),
        labelLarge: typography.label.copyWith(color: colors.foreground),
        labelMedium: typography.label.copyWith(color: colors.foreground, fontSize: 11),
        labelSmall: typography.caption.copyWith(color: colors.foregroundMuted, fontSize: 10),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: typography.bodyStrong.copyWith(color: colors.foreground),
        subtitleTextStyle: typography.caption.copyWith(color: colors.foregroundMuted),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: typography.label.copyWith(color: colors.foreground),
        unselectedLabelStyle: typography.label.copyWith(color: colors.foregroundMuted),
      ),

      extensions: <ThemeExtension<dynamic>>[this],
    );
  }

  @override
  UiTheme copyWith({
    UiColors? colors,
    UiTypography? typography,
    UiSpacing? spacing,
    UiRadii? radii,
    UiBorders? borders,
    UiShadows? shadows,
    UiMotion? motion,
    UiSizes? sizes,
    UiBreakpoints? breakpoints,
    UiScaleConfig? scaleConfig,
    Brightness? brightness,
  }) =>
      UiTheme(
        colors: colors ?? this.colors,
        typography: typography ?? this.typography,
        spacing: spacing ?? this.spacing,
        radii: radii ?? this.radii,
        borders: borders ?? this.borders,
        shadows: shadows ?? this.shadows,
        motion: motion ?? this.motion,
        sizes: sizes ?? this.sizes,
        breakpoints: breakpoints ?? this.breakpoints,
        scaleConfig: scaleConfig ?? this.scaleConfig,
        brightness: brightness ?? this.brightness,
      );

  @override
  UiTheme lerp(ThemeExtension<UiTheme>? other, double t) {
    if (other is! UiTheme) return this;
    return copyWith(
      colors: colors.lerpTo(other.colors, t),
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

/// Provides [UiTheme] to the widget tree.
class UiThemeScope extends InheritedWidget {
  const UiThemeScope({super.key, required this.theme, required super.child});

  final UiTheme theme;

  static UiTheme of(BuildContext context) {
    final UiThemeScope? scope =
        context.dependOnInheritedWidgetOfExactType<UiThemeScope>();
    if (scope != null) return scope.theme;
    final UiTheme? ext = Theme.of(context).extension<UiTheme>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? UiTheme.dark()
        : UiTheme.light();
  }

  @override
  bool updateShouldNotify(UiThemeScope oldWidget) => oldWidget.theme != theme;
}

/// One-stop app wrapper: theme + responsive metrics + Material theme sync.
class UiApp extends StatelessWidget {
  const UiApp({
    super.key,
    required this.theme,
    required this.builder,
  });

  final UiTheme theme;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => UiThemeScope(
        theme: theme,
        child: Theme(data: theme.toThemeData(), child: Builder(builder: builder)),
      );
}

/// Ergonomic access to tokens + responsive helpers from any widget.
extension UiThemeContext on BuildContext {
  UiTheme get ui => UiThemeScope.of(this);
  UiColors get uiColors => ui.colors;
  UiSpacing get uiSpace => ui.spacing;
  UiRadii get uiRadii => ui.radii;
  UiSizes get uiSizes => ui.sizes;
  UiMotion get uiMotion => ui.motion;
  UiShadows get uiShadows => ui.shadows;

  UiResponsive get uiRes => UiResponsive.of(
        this,
        breakpoints: ui.breakpoints,
        scaleConfig: ui.scaleConfig,
      );

  /// Device-scaled typography.
  UiTypography get uiText => ui.typography.scaled(
        uiRes.scale.text * uiRes.textScaleFactor,
      );

  double sp(double v) => uiRes.sp(v);
  double sz(double v) => uiRes.sz(v);
  BorderRadius radius(double v) => BorderRadius.circular(sz(v));
}
