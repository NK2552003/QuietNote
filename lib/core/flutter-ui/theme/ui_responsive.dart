import 'package:flutter/material.dart';

/// Device classes used for every responsive decision in the library.
enum UiDeviceType { mobile, tablet, desktop, largeDesktop }

@immutable
class UiBreakpoints {
  const UiBreakpoints({
    this.mobile = 600,
    this.tablet = 905,
    this.desktop = 1440,
  });

  /// width < mobile  -> mobile
  /// width < tablet  -> tablet
  /// width < desktop -> desktop
  /// else            -> largeDesktop
  final double mobile;
  final double tablet;
  final double desktop;

  UiDeviceType typeForWidth(double width) {
    if (width < mobile) return UiDeviceType.mobile;
    if (width < tablet) return UiDeviceType.tablet;
    if (width < desktop) return UiDeviceType.desktop;
    return UiDeviceType.largeDesktop;
  }
}

/// Per-device-type multipliers. Every size/space/font in the library is
/// multiplied by these, so one edit rescales the entire app.
@immutable
class UiScaleConfig {
  const UiScaleConfig({
    this.mobile = const UiScale(space: 1.0, text: 1.0, size: 1.0),
    this.tablet = const UiScale(space: 1.1, text: 1.05, size: 1.05),
    this.desktop = const UiScale(space: 1.2, text: 1.1, size: 1.1),
    this.largeDesktop = const UiScale(space: 1.3, text: 1.15, size: 1.15),
    this.minTextScale = 0.85,
    this.maxTextScale = 1.4,
  });

  final UiScale mobile;
  final UiScale tablet;
  final UiScale desktop;
  final UiScale largeDesktop;
  final double minTextScale;
  final double maxTextScale;

  UiScale forType(UiDeviceType type) {
    switch (type) {
      case UiDeviceType.mobile:
        return mobile;
      case UiDeviceType.tablet:
        return tablet;
      case UiDeviceType.desktop:
        return desktop;
      case UiDeviceType.largeDesktop:
        return largeDesktop;
    }
  }
}

@immutable
class UiScale {
  const UiScale({required this.space, required this.text, required this.size});

  final double space;
  final double text;
  final double size;
}

/// Runtime responsive metrics resolved from the current [BuildContext].
@immutable
class UiResponsive {
  const UiResponsive({
    required this.width,
    required this.height,
    required this.deviceType,
    required this.scale,
    required this.orientation,
    required this.textScaleFactor,
  });

  final double width;
  final double height;
  final UiDeviceType deviceType;
  final UiScale scale;
  final Orientation orientation;
  final double textScaleFactor;

  bool get isMobile => deviceType == UiDeviceType.mobile;
  bool get isTablet => deviceType == UiDeviceType.tablet;
  bool get isDesktop =>
      deviceType == UiDeviceType.desktop ||
      deviceType == UiDeviceType.largeDesktop;
  bool get isCompact => isMobile;
  bool get isLandscape => orientation == Orientation.landscape;

  /// Scale a spacing value.
  double sp(double value) => value * scale.space;

  /// Scale a size (icon, height, radius-independent dimension).
  double sz(double value) => value * scale.size;

  /// Scale a font size.
  double fs(double value) => value * scale.text * textScaleFactor;

  /// Pick a value per device type, falling back to the closest smaller one.
  T pick<T>({required T mobile, T? tablet, T? desktop, T? largeDesktop}) {
    switch (deviceType) {
      case UiDeviceType.mobile:
        return mobile;
      case UiDeviceType.tablet:
        return tablet ?? mobile;
      case UiDeviceType.desktop:
        return desktop ?? tablet ?? mobile;
      case UiDeviceType.largeDesktop:
        return largeDesktop ?? desktop ?? tablet ?? mobile;
    }
  }

  /// Responsive grid column count helper used by grids/lists.
  int columns({int mobile = 1, int tablet = 2, int desktop = 3, int large = 4}) =>
      pick(
        mobile: mobile,
        tablet: tablet,
        desktop: desktop,
        largeDesktop: large,
      );

  static UiResponsive of(
    BuildContext context, {
    UiBreakpoints breakpoints = const UiBreakpoints(),
    UiScaleConfig scaleConfig = const UiScaleConfig(),
  }) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double width = mq.size.width;
    final UiDeviceType type = breakpoints.typeForWidth(width);
    final double raw = mq.textScaler.scale(1);
    return UiResponsive(
      width: width,
      height: mq.size.height,
      deviceType: type,
      scale: scaleConfig.forType(type),
      orientation: mq.orientation,
      textScaleFactor:
          raw.clamp(scaleConfig.minTextScale, scaleConfig.maxTextScale),
    );
  }
}

/// Renders a different subtree per device class without duplicating logic.
class UiResponsiveBuilder extends StatelessWidget {
  const UiResponsiveBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, UiResponsive r) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints _) =>
            builder(ctx, UiResponsive.of(ctx)),
      );
}

/// Responsive layout switch.
class UiResponsiveLayout extends StatelessWidget {
  const UiResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.largeDesktop,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;
  final WidgetBuilder? largeDesktop;

  @override
  Widget build(BuildContext context) => UiResponsiveBuilder(
        builder: (BuildContext ctx, UiResponsive r) => r.pick<WidgetBuilder>(
          mobile: mobile,
          tablet: tablet,
          desktop: desktop,
          largeDesktop: largeDesktop,
        )(ctx),
      );
}
