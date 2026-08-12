import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';

/// First frame of the app: an animated QuietNote mark while settings (and the
/// database behind them) load. Once both the minimum display time has elapsed
/// and settings resolve, it hands off to onboarding or to Home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  bool _minimumElapsed = false;
  bool _navigated = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _minimumElapsed = true);
      _maybeContinue();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _maybeContinue() {
    if (_navigated || !_minimumElapsed || !mounted) return;
    final AsyncValue<AppSettings> async = ref.read(settingsProvider);
    if (async.isLoading) return;
    final AppSettings settings = async.value ?? const AppSettings();
    _navigated = true;
    context.go(settings.onboardingComplete ? '/' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;

    // React the moment settings finish loading (they may already be ready).
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, __) {
      _maybeContinue();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeContinue());

    final Animation<double> fade = CurvedAnimation(
      parent: _intro,
      curve: Curves.easeOutCubic,
    );
    final Animation<double> rise = Tween<double>(
      begin: 18,
      end: 0,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              theme.colors.background,
              Color.alphaBlend(
                theme.colors.primary.withValues(alpha: 0.10),
                theme.colors.background,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_intro, _pulse]),
              builder: (BuildContext context, Widget? child) {
                return Opacity(
                  opacity: fade.value,
                  child: Transform.translate(
                    offset: Offset(0, rise.value),
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (BuildContext context, Widget? child) {
                      final double t = Curves.easeInOut.transform(_pulse.value);
                      return Container(
                        width: context.sz(104),
                        height: context.sz(104),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colors.primary.withValues(
                            alpha: 0.10 + 0.06 * t,
                          ),
                          borderRadius: context.radius(theme.radii.xl),
                          border: Border.all(
                            color: theme.colors.primary.withValues(
                              alpha: 0.18 + 0.14 * t,
                            ),
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: EdgeInsets.all(context.sz(14)),
                      child: const QuietNoteMark(size: 112),
                    ),
                  ),
                  SizedBox(height: context.sp(theme.spacing.xl)),
                  Text('QuietNote', style: context.uiText.display),
                  SizedBox(height: context.sp(theme.spacing.xs)),
                  Text(
                    'Study calm. Stay on track.',
                    style: context.uiText.body.copyWith(
                      color: theme.colors.foregroundMuted,
                    ),
                  ),
                  SizedBox(height: context.sp(theme.spacing.xxl)),
                  SizedBox(
                    width: context.sz(120),
                    child: LinearProgressIndicator(
                      minHeight: context.sz(3),
                      backgroundColor: theme.colors.border,
                      color: theme.colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
