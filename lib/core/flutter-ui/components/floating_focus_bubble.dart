import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/focus/focus_timer_service.dart';
import 'package:quietnote/core/navigation/app_routes.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/clock/zen_focus_screen.dart';

/// Interactive draggable floating focus overlay bubble.
/// Displays live timer countdown, animated circular progress ring, and ambient glow.
/// Users can drag and shift its position to any screen location with magnetic edge snapping.
class FloatingFocusOverlay extends ConsumerStatefulWidget {
  const FloatingFocusOverlay({super.key});

  @override
  ConsumerState<FloatingFocusOverlay> createState() => _FloatingFocusOverlayState();
}

class _FloatingFocusOverlayState extends ConsumerState<FloatingFocusOverlay>
    with SingleTickerProviderStateMixin {
  late DateTime _now;
  Timer? _ticker;
  Offset _position = const Offset(16, 120);
  bool _isDragging = false;
  bool _hasCustomPosition = false;
  bool _showTimeOnBubble = false;

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _now = now);

      final currentSettings = ref.read(settingsProvider).value;
      final currentEnd = currentSettings?.focusSessionEndsAt;
      if (currentEnd != null && !currentEnd.isAfter(now)) {
        FocusTimerService().handleTimerExpiry(ref, context: context);
      }
    });

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _snapToClosestEdge(Size screenSize, EdgeInsets padding) {
    const double bubbleSize = 60.0;
    const double leftEdge = 16.0;
    final double rightEdge = screenSize.width - bubbleSize - 16.0;
    final double minTop = padding.top + 50.0;
    final double maxTop = screenSize.height - padding.bottom - bubbleSize - 80.0;

    final double targetX = (_position.dx < screenSize.width / 2) ? leftEdge : rightEdge;
    final double clampedY = _position.dy.clamp(minTop, maxTop);

    setState(() {
      _position = Offset(targetX, clampedY);
      _hasCustomPosition = true;
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final focusEnd = settings?.focusSessionEndsAt;

    if (focusEnd == null || settings?.floatingFocusBubbleEnabled == false) {
      return const SizedBox.shrink();
    }

    final activeSession = ref.watch(activeFocusSessionProvider).value;
    String currentPath = '';
    try {
      currentPath = appRouter.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {}

    // Don't duplicate bubble when already inside the full clock screen
    if (currentPath == '/clock') {
      return const SizedBox.shrink();
    }

    final isBreak = (settings?.focusSessionPhase ?? 'work') == 'break';
    final Color accentColor =
        isBreak ? const Color(0xFFF59E0B) : const Color(0xFF6366F1);
    final Color ringColor =
        isBreak ? const Color(0xFFFBBF24) : const Color(0xFF818CF8);
    final IconData icon =
        isBreak ? Icons.local_cafe_outlined : Icons.auto_awesome;

    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Initialize default position on top left if not yet set
    if (!_hasCustomPosition) {
      _position = Offset(16, padding.top + 60);
    }

    final diff = focusEnd.difference(_now).inSeconds.clamp(0, 24 * 60 * 60);
    final min = diff ~/ 60;
    final sec = diff % 60;
    final timeStr =
        '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

    final effectiveStart = settings?.focusSessionStartedAt ??
        activeSession?.startedAt ??
        focusEnd.subtract(Duration(
            minutes: settings?.focusSessionIntervalMinutes ?? 25));
    final sessionTotalSec = focusEnd.difference(effectiveStart).inSeconds;
    final elapsedSec = _now.difference(effectiveStart).inSeconds;
    final progress = sessionTotalSec > 0
        ? (elapsedSec / sessionTotalSec).clamp(0.0, 1.0)
        : 0.0;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final pulse = _pulseCtrl.value;

          return GestureDetector(
            onPanStart: (_) {
              setState(() => _isDragging = true);
              HapticFeedback.selectionClick();
            },
            onPanUpdate: (details) {
              setState(() {
                _position = Offset(
                  _position.dx + details.delta.dx,
                  _position.dy + details.delta.dy,
                );
              });
            },
            onPanEnd: (_) => _snapToClosestEdge(screenSize, padding),
            onTap: () {
              HapticFeedback.lightImpact();
              ZenFocusScreen.open(
                context,
                ref,
                end: focusEnd,
                startedAt: effectiveStart,
                phase: settings?.focusSessionPhase,
              );
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              setState(() => _showTimeOnBubble = !_showTimeOnBubble);
            },
            child: AnimatedContainer(
              duration: _isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              width: _showTimeOnBubble ? 94 : 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.25 + 0.15 * pulse),
                    blurRadius: 18 + 6 * pulse,
                    spreadRadius: 1 + 2 * pulse,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? (isBreak
                              ? const Color(0xE61F1A12)
                              : const Color(0xE6141324))
                          : const Color(0xF2FFFFFF),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: ringColor.withValues(alpha: 0.45 + 0.35 * pulse),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Progress ring around perimeter
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3.2,
                            strokeCap: StrokeCap.round,
                            backgroundColor:
                                accentColor.withValues(alpha: 0.18),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              ringColor,
                            ),
                          ),
                        ),
                        // Inner Content
                        if (_showTimeOnBubble)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: ringColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : Colors.black87,
                                  letterSpacing: -0.5,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 18,
                                color: ringColor,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                isBreak ? 'Break' : '${min}m',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
