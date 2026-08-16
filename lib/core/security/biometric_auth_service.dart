import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

/// Result status of a biometric or device credential authentication attempt.
class BiometricAuthResult {
  const BiometricAuthResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.notEnrolled = false,
    this.notAvailable = false,
    this.userCanceled = false,
  });

  final bool success;
  final String? errorCode;
  final String? errorMessage;
  final bool notEnrolled;
  final bool notAvailable;
  final bool userCanceled;

  static const BiometricAuthResult succeeded =
      BiometricAuthResult(success: true);
}

/// Device biometric & native screen lock query and authentication service.
class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;
  bool _isAuthRunning = false;

  /// Whether an authentication prompt is currently open.
  bool get isAuthRunning => _isAuthRunning;

  /// Whether the device hardware supports biometrics or device passcode.
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Whether the device has biometric sensors and enrolled credentials.
  Future<bool> canCheckBiometrics() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool supported = await _auth.isDeviceSupported();
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  /// Lists enrolled biometric types (e.g. fingerprint, face, iris).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const <BiometricType>[];
    }
  }

  /// Checks if any biometric hardware is actively enrolled.
  Future<bool> isBiometricsEnrolled() async {
    try {
      final list = await getAvailableBiometrics();
      if (list.isNotEmpty) return true;
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether any authentication method (biometric or device PIN/pattern/password)
  /// is supported and configured on this device.
  Future<bool> canAuthenticate() async {
    try {
      final bool isSupported = await _auth.isDeviceSupported();
      final bool canCheck = await _auth.canCheckBiometrics;
      return isSupported || canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Human-readable label for available biometrics on this device.
  Future<String> getBiometricLabel() async {
    final List<BiometricType> types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'Face Unlock / Biometrics';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'Fingerprint / Biometrics';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris Scanner';
    } else if (types.isNotEmpty) {
      return 'Biometrics';
    }
    return 'Device Screen Lock / Passcode';
  }

  /// Authenticates using biometrics or native device screen lock (PIN/Pattern/Password).
  Future<bool> authenticate({
    String localizedReason = 'Authenticate to access QuietNote',
    bool biometricOnly = false,
  }) async {
    final result = await authenticateDetailed(
      localizedReason: localizedReason,
      biometricOnly: biometricOnly,
    );
    return result.success;
  }

  /// Authenticates with a granular [BiometricAuthResult] for detailed error handling.
  /// Prevents concurrent or overlapping authentication dialogs.
  Future<BiometricAuthResult> authenticateDetailed({
    String localizedReason = 'Unlock QuietNote with biometrics or screen lock',
    bool biometricOnly = false,
  }) async {
    if (_isAuthRunning) {
      return const BiometricAuthResult(
        success: false,
        errorMessage: 'Authentication is already in progress.',
      );
    }

    _isAuthRunning = true;
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();

      if (!canCheck && !isSupported) {
        return const BiometricAuthResult(
          success: false,
          notAvailable: true,
          errorMessage: 'Device authentication is not available on this device.',
        );
      }

      final bool authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );

      if (authenticated) {
        return BiometricAuthResult.succeeded;
      } else {
        return const BiometricAuthResult(
          success: false,
          userCanceled: true,
          errorMessage: 'Authentication canceled.',
        );
      }
    } on PlatformException catch (e) {
      final String code = e.code;
      final bool notEnrolled = code == auth_error.notEnrolled ||
          code == auth_error.passcodeNotSet ||
          code.toLowerCase().contains('notenrolled');
      final bool notAvailable = code == auth_error.notAvailable ||
          code.toLowerCase().contains('notavailable');
      final bool canceled = code == auth_error.permanentlyLockedOut ||
          code.toLowerCase().contains('cancel') ||
          code.toLowerCase().contains('usercancel') ||
          code.toLowerCase().contains('auth_in_progress');

      return BiometricAuthResult(
        success: false,
        errorCode: code,
        errorMessage: e.message ?? 'Biometric error ($code)',
        notEnrolled: notEnrolled,
        notAvailable: notAvailable,
        userCanceled: canceled,
      );
    } catch (e) {
      return BiometricAuthResult(
        success: false,
        errorMessage: 'Biometric error: $e',
      );
    } finally {
      _isAuthRunning = false;
    }
  }

  /// Cancels active authentication if currently pending.
  Future<bool> stopAuthentication() async {
    try {
      _isAuthRunning = false;
      return await _auth.stopAuthentication();
    } catch (_) {
      return false;
    }
  }
}
