import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Platform bridge to the native Android floating system overlay bubble.
/// Manages displaying a draggable countdown and progress ring over other apps
/// and the home screen when a focus or break session is active.
class FloatingBubblePlatformService {
  FloatingBubblePlatformService._();
  static final FloatingBubblePlatformService _instance =
      FloatingBubblePlatformService._();
  factory FloatingBubblePlatformService() => _instance;

  static const MethodChannel _channel =
      MethodChannel('com.quietnote/floating_bubble');

  /// Displays the floating overlay bubble on Android screen.
  Future<bool> showBubble({
    required DateTime endsAt,
    required int totalSeconds,
    String phase = 'work',
    String label = 'Focus',
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('showBubble', <String, dynamic>{
        'endsAt': endsAt.millisecondsSinceEpoch,
        'totalSeconds': totalSeconds,
        'phase': phase,
        'label': label,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Updates the floating bubble with new end time or phase (e.g. work -> break).
  Future<bool> updateBubble({
    required DateTime endsAt,
    required int totalSeconds,
    String phase = 'work',
    String label = 'Focus',
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final res =
          await _channel.invokeMethod<bool>('updateBubble', <String, dynamic>{
        'endsAt': endsAt.millisecondsSinceEpoch,
        'totalSeconds': totalSeconds,
        'phase': phase,
        'label': label,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Hides and removes the floating bubble from screen.
  Future<bool> hideBubble() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('hideBubble');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if SYSTEM_ALERT_WINDOW permission is granted.
  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('checkPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Notifies the native overlay that the main app is open (so bubble is hidden).
  Future<bool> notifyAppForeground() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('notifyAppForeground');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Notifies the native overlay that the user left the app (so bubble reveals).
  Future<bool> notifyAppBackground() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('notifyAppBackground');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system settings screen to allow draw over other apps.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('requestPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
