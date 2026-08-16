import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/security/app_lock_controller.dart';
import 'package:quietnote/core/security/pin_setup_sheet.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Screen to configure biometric app lock, lock timeouts, and fallback PIN.
class SettingsSecurityScreen extends ConsumerStatefulWidget {
  const SettingsSecurityScreen({super.key});

  @override
  ConsumerState<SettingsSecurityScreen> createState() =>
      _SettingsSecurityScreenState();
}

class _SettingsSecurityScreenState
    extends ConsumerState<SettingsSecurityScreen> {
  bool _isBiometricsEnrolled = false;
  String _hardwareStatus = 'Checking hardware…';

  @override
  void initState() {
    super.initState();
    _checkHardware();
  }

  Future<void> _checkHardware() async {
    final service = ref.read(biometricServiceProvider);
    final supported = await service.isDeviceSupported();
    final biometrics = await service.getAvailableBiometrics();
    final enrolled = await service.isBiometricsEnrolled();
    final label = await service.getBiometricLabel();

    if (!mounted) return;
    setState(() {
      _isBiometricsEnrolled = supported && enrolled && biometrics.isNotEmpty;
      if (!supported) {
        _hardwareStatus = 'Biometrics not supported on this device';
      } else if (biometrics.isEmpty || !enrolled) {
        _hardwareStatus =
            'Sensor available ($label) · No credentials enrolled in OS settings';
      } else {
        _hardwareStatus = 'Supported & Enrolled ($label)';
      }
    });
  }

  Future<void> _toggleAppLock(bool value) async {
    if (!value) {
      ref.read(settingsProvider.notifier).update(
            (AppSettings s) => s.copyWith(appLockEnabled: false),
          );
      ref.read(appLockProvider.notifier).unlock();
      if (mounted) {
        UiToast.show(
          context,
          title: 'App Lock Disabled',
          message: 'Authentication is no longer required to open QuietNote.',
          intent: UiIntent.info,
          icon: Icons.lock_open_rounded,
        );
      }
      return;
    }

    // When enabling App Lock:
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final service = ref.read(biometricServiceProvider);
    final supported = await service.isDeviceSupported();
    final biometrics = await service.getAvailableBiometrics();
    final enrolled = await service.isBiometricsEnrolled();
    final bool canUseBiometrics = supported && enrolled && biometrics.isNotEmpty;
    final String existingPin = settings.appLockCustomPin.trim();

    if (canUseBiometrics) {
      // Prompt biometric confirmation to test sensor
      final result = await service.authenticateDetailed(
        localizedReason: 'Confirm biometrics to enable App Lock',
      );

      if (result.success) {
        ref.read(settingsProvider.notifier).update(
              (AppSettings s) => s.copyWith(
                appLockEnabled: true,
                appLockBiometricsEnabled: true,
              ),
            );
        ref.read(appLockProvider.notifier).unlock();
        if (mounted) {
          UiToast.show(
            context,
            title: 'App Lock Enabled',
            message: 'QuietNote is now secured with biometrics.',
            intent: UiIntent.success,
            icon: Icons.lock_outline,
          );
        }
        return;
      } else if (result.userCanceled) {
        if (mounted) {
          UiToast.show(
            context,
            title: 'Setup Canceled',
            message: 'App lock was not enabled.',
            intent: UiIntent.info,
          );
        }
        return;
      }

      // If biometrics had an error or user preferred PIN:
      if (existingPin.isNotEmpty) {
        ref.read(settingsProvider.notifier).update(
              (AppSettings s) => s.copyWith(appLockEnabled: true),
            );
        ref.read(appLockProvider.notifier).unlock();
        if (mounted) {
          UiToast.show(
            context,
            title: 'App Lock Enabled',
            message: 'QuietNote is secured with your custom PIN.',
            intent: UiIntent.success,
            icon: Icons.lock_outline,
          );
        }
        return;
      }
    }

    // If device does not have biometrics enrolled (or biometrics not supported):
    if (existingPin.isNotEmpty) {
      ref.read(settingsProvider.notifier).update(
            (AppSettings s) => s.copyWith(
              appLockEnabled: true,
              appLockBiometricsEnabled: false,
            ),
          );
      ref.read(appLockProvider.notifier).unlock();
      if (mounted) {
        UiToast.show(
          context,
          title: 'App Lock Enabled',
          message: 'QuietNote is secured with your passcode PIN.',
          intent: UiIntent.success,
          icon: Icons.lock_outline,
        );
      }
    } else {
      // Prompt user to set up a 4-digit PIN first via PinSetupSheet
      if (mounted) {
        final String? savedPin =
            await _showPinSheet('', settings.accent.swatch);
        if (savedPin != null && savedPin.isNotEmpty) {
          ref.read(settingsProvider.notifier).update(
                (AppSettings s) => s.copyWith(
                  appLockEnabled: true,
                  appLockBiometricsEnabled: false,
                  appLockCustomPin: savedPin,
                ),
              );
          ref.read(appLockProvider.notifier).unlock();
          if (mounted) {
            UiToast.show(
              context,
              title: 'App Lock Enabled',
              message: 'QuietNote is secured with your 4-digit PIN.',
              intent: UiIntent.success,
              icon: Icons.lock_outline,
            );
          }
        } else {
          if (mounted) {
            UiToast.show(
              context,
              title: 'PIN Required',
              message:
                  'A 4-digit PIN is required to enable App Lock without biometrics.',
              intent: UiIntent.info,
            );
          }
        }
      }
    }
  }

  Future<void> _showTimeoutPicker(int currentSec) async {
    final options = <int, String>{
      0: 'Immediately (when leaving app)',
      60: 'After 1 minute in background',
      300: 'After 5 minutes in background',
      900: 'After 15 minutes in background',
    };

    final int? selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.uiColors;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Lock Timeout',
                style: ctx.uiText.subheading.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...options.entries.map((e) {
                final isSelected = e.key == currentSec;
                return ListTile(
                  title: Text(e.value, style: ctx.uiText.body),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded,
                          color: c.primary, size: 20)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.of(ctx).pop(e.key),
                );
              }),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      ref.read(settingsProvider.notifier).update(
            (AppSettings s) => s.copyWith(appLockTimeoutSeconds: selected),
          );
    }
  }

  Future<String?> _showPinSheet(String currentPin, Color accentColor) async {
    final String? newPin = await PinSetupSheet.show(
      context,
      currentPin: currentPin,
      accentColor: accentColor,
    );

    if (newPin != null && mounted) {
      ref.read(settingsProvider.notifier).update(
            (AppSettings s) => s.copyWith(appLockCustomPin: newPin),
          );
      UiToast.show(
        context,
        title: newPin.isEmpty ? 'PIN Removed' : 'PIN Saved',
        message: newPin.isEmpty
            ? 'Passcode PIN has been cleared.'
            : 'Your 4-digit PIN has been configured.',
        intent: UiIntent.success,
      );
    }
    return newPin;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    final String timeoutLabel = switch (settings.appLockTimeoutSeconds) {
      0 => 'Immediately',
      60 => '1 minute',
      300 => '5 minutes',
      900 => '15 minutes',
      _ => '${settings.appLockTimeoutSeconds}s',
    };

    return SettingsSubPage(
      title: 'Security & App Lock',
      subtitle: 'Protect your notes, journal, and study progress.',
      children: <Widget>[
        // ── Main App Lock Switch ──
        SettingsSection(
          title: 'Authentication',
          children: <Widget>[
            SettingsSwitchTile(
              icon: Icons.security_rounded,
              title: 'Require App Lock',
              description: _isBiometricsEnrolled
                  ? 'Unlock with biometrics or PIN passcode'
                  : 'Unlock with 4-digit PIN passcode',
              value: settings.appLockEnabled,
              onChanged: _toggleAppLock,
            ),
            if (settings.appLockEnabled) ...[
              SettingsTile(
                icon: Icons.timer_outlined,
                title: 'Lock Timeout',
                description: 'How quickly the app locks when left in background',
                value: timeoutLabel,
                onTap: () =>
                    _showTimeoutPicker(settings.appLockTimeoutSeconds),
              ),
              if (_isBiometricsEnrolled)
                SettingsSwitchTile(
                  icon: Icons.fingerprint_rounded,
                  title: 'Biometric Unlock',
                  description: 'Allow Face ID, fingerprint, or device credentials',
                  value: settings.appLockBiometricsEnabled,
                  onChanged: (v) {
                    ref.read(settingsProvider.notifier).update(
                          (AppSettings s) =>
                              s.copyWith(appLockBiometricsEnabled: v),
                        );
                  },
                ),
              SettingsTile(
                icon: Icons.pin_outlined,
                title: 'Passcode PIN',
                description: settings.appLockCustomPin.isEmpty
                    ? 'None set (4-digit numeric passcode)'
                    : '4-digit PIN configured',
                value: settings.appLockCustomPin.isEmpty ? 'Set' : 'Edit',
                onTap: () => _showPinSheet(
                  settings.appLockCustomPin,
                  settings.accent.swatch,
                ),
              ),
            ],
          ],
        ),

        // ── Device Biometric Status ──
        SettingsSection(
          title: 'Device Hardware',
          children: <Widget>[
            SettingsTile(
              icon: Icons.perm_device_information_rounded,
              title: 'Biometric Sensor Status',
              description: _hardwareStatus,
              showChevron: false,
            ),
          ],
        ),

        // ── Privacy Assurance ──
        const SettingsSection(
          title: 'Privacy & Security Guard',
          children: <Widget>[
            SettingsTile(
              icon: Icons.shield_outlined,
              title: '100% On-Device Protection',
              description:
                  'Biometric authentication and PIN encryption are handled on-device. QuietNote never transmits or stores raw biometrics.',
              showChevron: false,
            ),
          ],
        ),
      ],
    );
  }
}
