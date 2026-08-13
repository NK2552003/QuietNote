import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


/// SINGLE SOURCE OF TRUTH FOR THE DESIGN SYSTEM
///
/// Change values here only. No component file contains a hardcoded color,
/// radius, font size, spacing or duration.
/// ---------------------------------------------------------------------------

/// Raw brand palette. Only referenced by [UiColors] factories below.
///
/// Tuned to a Lovable-style register: warm-neutral greys (a touch of red in
/// the hue so surfaces never read cold/blue), near-black rather than pure
/// black, and low-chroma accents that sit quietly against the neutrals.
class UiPalette {
  const UiPalette._();

  // Neutrals — warm-tinted, Lovable-style
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color gray50 = Color(0xFFFAFAF9);
  static const Color gray100 = Color(0xFFF5F5F4);
  static const Color gray150 = Color(0xFFEFEEEC);
  static const Color gray200 = Color(0xFFE7E5E4);
  static const Color gray300 = Color(0xFFD6D3D1);
  static const Color gray400 = Color(0xFFA8A29E);
  static const Color gray500 = Color(0xFF78716C);
  static const Color gray600 = Color(0xFF57534E);
  static const Color gray700 = Color(0xFF3A3734);
  static const Color gray800 = Color(0xFF232120);
  static const Color gray850 = Color(0xFF1B1918);
  static const Color gray900 = Color(0xFF151312);
  static const Color gray950 = Color(0xFF0D0C0B);

  // Brand — muted ink-blue, deliberately low chroma
  static const Color brand400 = Color(0xFF8B9FE8);
  static const Color brand500 = Color(0xFF6B7FD7);
  static const Color brand600 = Color(0xFF4F63C4);
  static const Color brand700 = Color(0xFF3E4FA3);

  // Market semantics — desaturated so charts stay calm
  static const Color bullish500 = Color(0xFF3F9A6B);
  static const Color bullish400 = Color(0xFF4EB57F);
  static const Color bearish500 = Color(0xFFC0564E);
  static const Color bearish400 = Color(0xFFD9695F);
  static const Color warning500 = Color(0xFFC98A2E);
  static const Color info500 = Color(0xFF4A8FA8);

  // Chart series — muted, evenly spaced hues
  static const List<Color> series = <Color>[
    brand500,
    Color(0xFF4FA39B),
    Color(0xFFC98A2E),
    Color(0xFFC4738F),
    Color(0xFF8F7BC4),
    Color(0xFF4EB57F),
    Color(0xFFCF8455),
    Color(0xFF5C9CB8),
  ];
}


/// Semantic colors consumed by every component.
@immutable
class UiColors {
  const UiColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.overlay,
    required this.border,
    required this.borderStrong,
    required this.foreground,
    required this.foregroundMuted,
    required this.foregroundSubtle,
    required this.primary,
    required this.primaryHover,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.bullish,
    required this.bearish,
    required this.warning,
    required this.info,
    required this.destructive,
    required this.onDestructive,
    required this.focusRing,
    required this.disabledBackground,
    required this.disabledForeground,
    required this.series,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceHover;
  final Color overlay;
  final Color border;
  final Color borderStrong;
  final Color foreground;
  final Color foregroundMuted;
  final Color foregroundSubtle;
  final Color primary;
  final Color primaryHover;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color bullish;
  final Color bearish;
  final Color warning;
  final Color info;
  final Color destructive;
  final Color onDestructive;
  final Color focusRing;
  final Color disabledBackground;
  final Color disabledForeground;
  final List<Color> series;

  factory UiColors.light() => const UiColors(
        background: UiPalette.gray50,
        surface: UiPalette.white,
        surfaceMuted: UiPalette.gray100,
        surfaceHover: UiPalette.gray150,
        overlay: Color(0x99151312),
        border: UiPalette.gray200,
        borderStrong: UiPalette.gray300,
        foreground: UiPalette.gray900,
        foregroundMuted: UiPalette.gray500,
        foregroundSubtle: UiPalette.gray400,
        primary: UiPalette.gray900,
        primaryHover: UiPalette.gray800,
        onPrimary: UiPalette.gray50,
        secondary: UiPalette.gray100,
        onSecondary: UiPalette.gray900,
        bullish: UiPalette.bullish500,
        bearish: UiPalette.bearish500,
        warning: UiPalette.warning500,
        info: UiPalette.info500,
        destructive: UiPalette.bearish500,
        onDestructive: UiPalette.white,
        focusRing: UiPalette.brand500,
        disabledBackground: UiPalette.gray100,
        disabledForeground: UiPalette.gray400,
        series: UiPalette.series,
      );

  factory UiColors.dark() => const UiColors(
        background: UiPalette.gray950,
        surface: UiPalette.gray900,
        surfaceMuted: UiPalette.gray850,
        surfaceHover: UiPalette.gray800,
        overlay: Color(0xCC0D0C0B),
        border: Color(0xFF262322),
        borderStrong: UiPalette.gray700,
        foreground: UiPalette.gray50,
        foregroundMuted: UiPalette.gray400,
        foregroundSubtle: UiPalette.gray500,
        primary: UiPalette.gray50,
        primaryHover: UiPalette.white,
        onPrimary: UiPalette.gray950,
        secondary: UiPalette.gray800,
        onSecondary: UiPalette.gray50,
        bullish: UiPalette.bullish400,
        bearish: UiPalette.bearish400,
        warning: UiPalette.warning500,
        info: UiPalette.info500,
        destructive: UiPalette.bearish400,
        onDestructive: UiPalette.white,
        focusRing: UiPalette.brand400,
        disabledBackground: UiPalette.gray800,
        disabledForeground: UiPalette.gray600,
        series: UiPalette.series,
      );


  UiColors lerpTo(UiColors other, double t) => UiColors(
        background: Color.lerp(background, other.background, t)!,
        surface: Color.lerp(surface, other.surface, t)!,
        surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
        surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
        overlay: Color.lerp(overlay, other.overlay, t)!,
        border: Color.lerp(border, other.border, t)!,
        borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
        foreground: Color.lerp(foreground, other.foreground, t)!,
        foregroundMuted: Color.lerp(foregroundMuted, other.foregroundMuted, t)!,
        foregroundSubtle:
            Color.lerp(foregroundSubtle, other.foregroundSubtle, t)!,
        primary: Color.lerp(primary, other.primary, t)!,
        primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
        onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
        secondary: Color.lerp(secondary, other.secondary, t)!,
        onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
        bullish: Color.lerp(bullish, other.bullish, t)!,
        bearish: Color.lerp(bearish, other.bearish, t)!,
        warning: Color.lerp(warning, other.warning, t)!,
        info: Color.lerp(info, other.info, t)!,
        destructive: Color.lerp(destructive, other.destructive, t)!,
        onDestructive: Color.lerp(onDestructive, other.onDestructive, t)!,
        focusRing: Color.lerp(focusRing, other.focusRing, t)!,
        disabledBackground:
            Color.lerp(disabledBackground, other.disabledBackground, t)!,
        disabledForeground:
            Color.lerp(disabledForeground, other.disabledForeground, t)!,
        series: t < 0.5 ? series : other.series,
      );
}

/// Spacing scale (logical px, later scaled by device).
@immutable
class UiSpacing {
  const UiSpacing({
    this.none = 0,
    this.xxs = 2,
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
    this.xxl = 32,
    this.xxxl = 48,
  });

  final double none;
  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;
}

@immutable
class UiRadii {
  const UiRadii({
    this.none = 0,
    this.sm = 6,
    this.md = 8,
    this.lg = 12,
    this.xl = 16,
    this.xxl = 24,
    this.pill = 999,
  });

  final double none;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double pill;
}

@immutable
class UiBorders {
  const UiBorders({this.hairline = 1, this.thick = 1.5, this.focus = 2});

  final double hairline;
  final double thick;
  final double focus;
}

@immutable
class UiTypography {
  const UiTypography({
    required this.fontFamily,
    required this.monoFontFamily,
    required this.display,
    required this.title,
    required this.heading,
    required this.subheading,
    required this.body,
    required this.bodyStrong,
    required this.label,
    required this.caption,
    required this.numeric,
  });

  final String? fontFamily;
  final String? monoFontFamily;
  final TextStyle display;
  final TextStyle title;
  final TextStyle heading;
  final TextStyle subheading;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle numeric;

  factory UiTypography.standard({
    String? fontFamily,
    String? monoFontFamily,
  }) {
    fontFamily ??= GoogleFonts.inter().fontFamily;
    monoFontFamily ??= GoogleFonts.jetBrainsMono().fontFamily;
    // Optical tracking: large text tightens, small text opens up slightly.
    TextStyle base(
      double size,
      FontWeight weight,
      double height, [
      double tracking = 0,
    ]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: tracking,
        );
    return UiTypography(
      fontFamily: fontFamily,
      monoFontFamily: monoFontFamily,
      display: base(34, FontWeight.w700, 1.1, -0.8),
      title: base(22, FontWeight.w600, 1.2, -0.5),
      heading: base(18, FontWeight.w600, 1.25, -0.3),
      subheading: base(16, FontWeight.w600, 1.3, -0.1),
      body: base(16, FontWeight.w400, 1.5),
      bodyStrong: base(16, FontWeight.w500, 1.5),
      label: base(13, FontWeight.w500, 1.2, 0.1),
      caption: base(12, FontWeight.w400, 1.3, 0.2),

      numeric: TextStyle(
        fontFamily: monoFontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }

  UiTypography scaled(double factor) => UiTypography(
        fontFamily: fontFamily,
        monoFontFamily: monoFontFamily,
        display: _s(display, factor),
        title: _s(title, factor),
        heading: _s(heading, factor),
        subheading: _s(subheading, factor),
        body: _s(body, factor),
        bodyStrong: _s(bodyStrong, factor),
        label: _s(label, factor),
        caption: _s(caption, factor),
        numeric: _s(numeric, factor),
      );

  static TextStyle _s(TextStyle style, double f) =>
      style.copyWith(fontSize: (style.fontSize ?? 14) * f);
}

/// Elevation. Lovable-style: shadows are almost invisible — depth comes from
/// the hairline border, not from a drop shadow. Only floating surfaces
/// (menus, dialogs, toasts) get anything perceptible.
@immutable
class UiShadows {
  const UiShadows({required this.sm, required this.md, required this.lg});

  final List<BoxShadow> sm;
  final List<BoxShadow> md;
  final List<BoxShadow> lg;

  factory UiShadows.light() => const UiShadows(
        sm: <BoxShadow>[
          BoxShadow(color: Color(0x0A1A1512), blurRadius: 2, offset: Offset(0, 1)),
        ],
        md: <BoxShadow>[
          BoxShadow(color: Color(0x0F1A1512), blurRadius: 10, offset: Offset(0, 3)),
          BoxShadow(color: Color(0x0A1A1512), blurRadius: 2, offset: Offset(0, 1)),
        ],
        lg: <BoxShadow>[
          BoxShadow(color: Color(0x1A1A1512), blurRadius: 32, offset: Offset(0, 16)),
          BoxShadow(color: Color(0x0D1A1512), blurRadius: 6, offset: Offset(0, 2)),
        ],
      );

  factory UiShadows.dark() => const UiShadows(
        sm: <BoxShadow>[
          BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
        md: <BoxShadow>[
          BoxShadow(color: Color(0x47000000), blurRadius: 12, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x2E000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
        lg: <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 36, offset: Offset(0, 18)),
          BoxShadow(color: Color(0x3D000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      );
}

@immutable
class UiMotion {
  const UiMotion({
    this.fast = const Duration(milliseconds: 110),
    this.normal = const Duration(milliseconds: 180),
    this.slow = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
  });

  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Curve curve;
}

/// Control metrics: every interactive component derives its size from here.
/// Compact by default — Lovable-style chrome is tight, content is generous.
@immutable
class UiSizes {
  const UiSizes({
    this.controlHeightXs = 22,
    this.controlHeightSm = 28,
    this.controlHeightMd = 36,
    this.controlHeightLg = 44,
    this.controlHeightXl = 54,
    this.iconXs = 12,
    this.iconSm = 14,
    this.iconMd = 16,
    this.iconLg = 20,
    this.iconXl = 24,
    this.avatarXs = 18,
    this.avatarSm = 24,
    this.avatarMd = 32,
    this.avatarLg = 48,
    this.avatarXl = 72,
    this.checkbox = 16,
    this.radio = 16,
    this.switchWidth = 36,
    this.switchHeight = 20,
    this.trackThickness = 6,
    this.chartHeight = 240,
    this.sparkHeight = 44,
    this.minTapTarget = 44,
    this.maxContentWidth = 1180,
  });


  final double controlHeightXs;
  final double controlHeightSm;
  final double controlHeightMd;
  final double controlHeightLg;
  final double controlHeightXl;
  final double iconXs;
  final double iconSm;
  final double iconMd;
  final double iconLg;
  final double iconXl;
  final double avatarXs;
  final double avatarSm;
  final double avatarMd;
  final double avatarLg;
  final double avatarXl;
  final double checkbox;
  final double radio;
  final double switchWidth;
  final double switchHeight;
  final double trackThickness;
  final double chartHeight;
  final double sparkHeight;
  final double minTapTarget;
  final double maxContentWidth;
}
