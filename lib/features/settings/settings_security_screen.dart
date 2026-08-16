import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/security/app_lock_controller.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Screen to configure biometric & device screen lock protection and timeouts.
class SettingsSecurityScreen extends ConsumerStatefulWidget {
  const SettingsSecurityScreen({super.key});

  @override
  ConsumerState<SettingsSecurityScreen> createState() =>
      _SettingsSecurityScreenState();
}

class _SettingsSecurityScreenState
    extends ConsumerState<SettingsSecurityScreen> {
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
      if (!supported && biometrics.isEmpty) {
        _hardwareStatus = 'Device security / biometrics not supported';
      } else if (biometrics.isNotEmpty && enrolled) {
        _hardwareStatus = 'Biometrics enrolled ($label)';
      } else {
        _hardwareStatus = 'Device Screen Lock / Passcode supported';
      }
    });
  }

  Future<void> _toggleAppLock(bool value) async {
    final service = ref.read(biometricServiceProvider);

    if (!value) {
      // Require verification to disable app lock
      final result = await service.authenticateDetailed(
        localizedReason: 'Authenticate to disable App Lock',
      );

      if (result.success) {
        ref.read(settingsProvider.notifier).update(
              (AppSettings s) => s.copyWith(
                appLockEnabled: false,
                appLockBiometricsEnabled: true,
              ),
            );
        ref.read(appLockProvider.notifier).unlock();
        if (mounted) {
          UiToast.show(
            context,
            title: 'App Lock Disabled',
            message: 'QuietNote is no longer protected by App Lock.',
            intent: UiIntent.info,
            icon: Icons.lock_open_rounded,
          );
        }
      } else if (result.userCanceled) {
        if (mounted) {
          UiToast.show(
            context,
            title: 'Canceled',
            message: 'App lock remains enabled.',
            intent: UiIntent.info,
          );
        }
      }
      return;
    }

    // When enabling App Lock: verify with native device authentication
    final result = await service.authenticateDetailed(
      localizedReason: 'Authenticate to enable App Lock for QuietNote',
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
          message: 'QuietNote is secured with your device biometric & screen lock.',
          intent: UiIntent.success,
          icon: Icons.lock_outline,
        );
      }
    } else if (result.userCanceled) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'Setup Canceled',
          message: 'App lock was not enabled.',
          intent: UiIntent.info,
        );
      }
    } else {
      if (mounted) {
        UiToast.show(
          context,
          title: 'Authentication Required',
          message: result.errorMessage ??
              'Please set up a screen lock (PIN, Pattern, or Fingerprint) in device settings.',
          intent: UiIntent.danger,
        );
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
              description:
                  'Protect QuietNote with device fingerprint, face unlock, or screen lock',
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
            ],
          ],
        ),

        // ── Device Biometric Status ──
        SettingsSection(
          title: 'Device Hardware & Security',
          children: <Widget>[
            SettingsTile(
              icon: Icons.perm_device_information_rounded,
              title: 'Security Status',
              description: _hardwareStatus,
              showChevron: false,
            ),
          ],
        ),

        // ── Privacy Assurance ──
        const SettingsSection(
          title: 'Privacy & Hardware Security',
          children: <Widget>[
            SettingsTile(
              icon: Icons.shield_outlined,
              title: '100% On-Device Protection',
              description:
                  'QuietNote leverages your device’s secure hardware (BiometricPrompt / Secure Enclave). Authentication is always verified locally by the operating system.',
              showChevron: false,
            ),
          ],
        ),
      ],
    );
  }
}
