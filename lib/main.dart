import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/flutter-ui/flutter_ui.dart';
import 'core/focus/floating_bubble_service.dart';
import 'core/navigation/app_routes.dart';
import 'core/security/app_lock_controller.dart';
import 'core/security/app_lock_gate.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/settings_repository.dart';
import 'core/settings/theme_builder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // By default Flutter shows a *blank grey box* (not the red debug screen)
  // for any widget that throws during build in profile/release mode, and
  // prints nothing useful for isolate-level failures (e.g. a database
  // connection that fails inside its background isolate). That is what
  // made the "blank screen on every tab" bug so hard to see: nothing ever
  // reached the console. This override makes build failures visible and
  // actionable everywhere, in every build mode, instead of invisible.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('QuietNote UI error: ${details.exceptionAsString()}');
    return Material(
      color: const Color(0xFFFFF4F4),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 40),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong loading this screen.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFFB3261E)),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A1F1A)),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() {
    runApp(const ProviderScope(child: HabitFlowApp()));
  }, (error, stack) {
    debugPrint('QuietNote uncaught error: $error\n$stack');
  });
}

class HabitFlowApp extends ConsumerStatefulWidget {
  const HabitFlowApp({super.key});

  @override
  ConsumerState<HabitFlowApp> createState() => _HabitFlowAppState();
}

class _HabitFlowAppState extends ConsumerState<HabitFlowApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        FloatingBubblePlatformService().notifyAppForeground();
        ref.read(appLockProvider.notifier).onAppResumed();
      },
      onInactive: () {
        ref.read(appLockProvider.notifier).onAppPaused();
      },
      onPause: () {
        FloatingBubblePlatformService().notifyAppBackground();
        ref.read(appLockProvider.notifier).onAppPaused();
      },
      onHide: () {
        FloatingBubblePlatformService().notifyAppBackground();
        ref.read(appLockProvider.notifier).onAppPaused();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Settings drive theme mode, accent colour and text size app-wide. Until
    // they load from the database we fall back to the defaults, so the very
    // first frame still renders.
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();

    final platformBrightness =
        MediaQuery.platformBrightnessOf(context);
    final Brightness brightness = switch (settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };

    return UiApp(
      theme: buildUiTheme(brightness: brightness, settings: settings),
      builder: (context) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'QuietNote',
        routerConfig: appRouter,
        theme: buildUiTheme(brightness: Brightness.light, settings: settings)
            .toThemeData(),
        darkTheme: buildUiTheme(brightness: Brightness.dark, settings: settings)
            .toThemeData(),
        themeMode: settings.themeMode,
        // AppLockGate protects the app whenever biometric lock is enabled.
        // UiToastScope allows toasts across all screens.
        builder: (context, child) => AppLockGate(
          child: UiToastScope(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

