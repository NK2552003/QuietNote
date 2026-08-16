import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quietnote/core/security/app_lock_controller.dart';
import 'package:quietnote/core/security/app_lock_gate.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';

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

  group('AppLockGate & AppLockController Tests', () {
    test('AppLockState defaults and copyWith work properly', () {
      const state = AppLockState(isLocked: true);
      expect(state.isLocked, isTrue);
      expect(state.hasUnlockedThisSession, isFalse);
      expect(state.isAuthenticating, isFalse);

      final unlocked = state.copyWith(
        isLocked: false,
        hasUnlockedThisSession: true,
      );
      expect(unlocked.isLocked, isFalse);
      expect(unlocked.hasUnlockedThisSession, isTrue);
    });

    testWidgets('AppLockGate renders child directly when app lock is disabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsController(
                const AppSettings(appLockEnabled: false),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppLockGate(
              child: Scaffold(
                body: Text('Secret Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Secret Content'), findsOneWidget);
      expect(find.byType(AppLockScreen), findsNothing);
    });

    testWidgets('AppLockGate shows AppLockScreen when app lock is enabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsController(
                const AppSettings(appLockEnabled: true),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppLockGate(
              child: Scaffold(
                body: Text('Secret Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('QuietNote is Protected'), findsOneWidget);
      expect(find.text('Unlock QuietNote'), findsOneWidget);
    });
  });
}
