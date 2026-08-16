import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/core/settings/theme_builder.dart';
import 'package:quietnote/features/settings/settings_appearance_screen.dart';

class FakeSettingsController extends SettingsController {
  FakeSettingsController(this._initialSettings);

  final AppSettings _initialSettings;

  @override
  Future<AppSettings> build() async => _initialSettings;

  @override
  Future<AppSettings> update(
    FutureOr<AppSettings> Function(AppSettings current) cb, {
    FutureOr<AppSettings> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final AppSettings current = state.value ?? _initialSettings;
    final AppSettings next = await cb(current);
    state = AsyncData<AppSettings>(next);
    return next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiDockSize & UiDockPosition Unit Tests', () {
    test('UiDockSize metrics have valid professional proportions', () {
      expect(UiDockSize.compact.height, 48.0);
      expect(UiDockSize.compact.width, 260.0);
      expect(UiDockSize.compact.iconSize, 20.0);

      expect(UiDockSize.standard.height, 54.0);
      expect(UiDockSize.standard.width, 296.0);
      expect(UiDockSize.standard.iconSize, 22.0);

      expect(UiDockSize.spacious.height, 60.0);
      expect(UiDockSize.spacious.width, 336.0);
      expect(UiDockSize.spacious.iconSize, 24.0);
    });

    test('UiDockPosition alignments map accurately', () {
      expect(UiDockPosition.left.alignment, Alignment.bottomLeft);
      expect(UiDockPosition.center.alignment, Alignment.bottomCenter);
      expect(UiDockPosition.right.alignment, Alignment.bottomRight);
    });

    test('AppSettings serializes and restores dockSize and dockPosition', () {
      const settings = AppSettings(
        dockSize: UiDockSize.spacious,
        dockPosition: UiDockPosition.left,
      );

      final map = settings.toMap();
      expect(map['dockSize'], 'spacious');
      expect(map['dockPosition'], 'left');

      final restored = AppSettings.fromMap(map);
      expect(restored.dockSize, UiDockSize.spacious);
      expect(restored.dockPosition, UiDockPosition.left);
    });
  });

  group('UiNavShell & Settings Appearance Widget Tests', () {
    final testItems = [
      const UiTabItem(label: 'Home', icon: Icons.home_outlined),
      const UiTabItem(label: 'Todos', icon: Icons.checklist_outlined),
      const UiTabItem(label: 'Notes', icon: Icons.notes_outlined),
      const UiTabItem(label: 'Settings', icon: Icons.settings_outlined),
    ];

    testWidgets('UiNavShell builds and renders dock with selected size and alignment',
        (WidgetTester tester) async {
      const settings = AppSettings(
        dockSize: UiDockSize.compact,
        dockPosition: UiDockPosition.right,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsController(settings),
            ),
          ],
          child: UiApp(
            theme: buildUiTheme(
              brightness: Brightness.light,
              settings: settings,
            ),
            builder: (context) => MaterialApp(
              home: UiNavShell(
                items: testItems,
                selectedIndex: 0,
                onChanged: (_) {},
                body: const Center(child: Text('Shell Body Content')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Shell Body Content'), findsOneWidget);
      expect(find.byType(UiNavShell), findsOneWidget);
    });

    testWidgets('SettingsAppearanceScreen displays Navigation Dock controls and live preview',
        (WidgetTester tester) async {
      const settings = AppSettings(
        dockSize: UiDockSize.standard,
        dockPosition: UiDockPosition.center,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsController(settings),
            ),
          ],
          child: UiApp(
            theme: buildUiTheme(
              brightness: Brightness.light,
              settings: settings,
            ),
            builder: (context) => const MaterialApp(
              home: Scaffold(
                body: SettingsAppearanceScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('NAVIGATION DOCK'), findsOneWidget);
      expect(find.text('Live Dock Preview'), findsOneWidget);
      expect(find.text('Dock Sizing'), findsOneWidget);
      expect(find.text('Dock Alignment'), findsOneWidget);
      expect(find.text('Compact'), findsWidgets);
      expect(find.text('Standard'), findsWidgets);
      expect(find.text('Spacious'), findsWidgets);
    });
  });
}
