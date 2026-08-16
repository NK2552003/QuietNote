import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/audio/ambient_audio_service.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/focus/focus_timer_service.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/clock/focus_preset.dart';

class ZenFocusScreen extends ConsumerStatefulWidget {
  const ZenFocusScreen({
    super.key,
    required this.end,
    this.startedAt,
    this.phase = 'work',
    this.presetLabel,
    this.linkedTitle,
    required this.onCancel,
    required this.onExtend,
  });

  final DateTime end;
  final DateTime? startedAt;
  final String phase;
  final String? presetLabel;
  final String? linkedTitle;
  final VoidCallback onCancel;
  final ValueChanged<int> onExtend;

  static void open(
    BuildContext context,
    WidgetRef ref, {
    DateTime? end,
    DateTime? startedAt,
    String? phase,
    String? presetLabel,
    String? linkedTitle,
  }) {
    final settings = ref.read(settingsProvider).value;
    final activeEnd = end ?? settings?.focusSessionEndsAt;
    if (activeEnd == null) return;

    final activeSession = ref.read(activeFocusSessionProvider).value;
    final effectiveStart = startedAt ?? settings?.focusSessionStartedAt ?? activeSession?.startedAt;
    final effectivePresetLabel =
        presetLabel ?? focusPresetFromId(activeSession?.presetId)?.chipLabel;
    final effectivePhase = phase ?? settings?.focusSessionPhase ?? 'work';

    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => ZenFocusScreen(
          end: activeEnd,
          startedAt: effectiveStart,
          phase: effectivePhase,
          presetLabel: effectivePresetLabel,
          linkedTitle: linkedTitle,
          onCancel: () async {
            HapticFeedback.lightImpact();
            await FocusTimerService().finishSession(ref);
            if (ctx.mounted) Navigator.of(ctx).maybePop();
          },
          onExtend: (int extraMinutes) async {
            await FocusTimerService().extendSession(ref, extraMinutes: extraMinutes, context: ctx);
          },
        ),
      ),
    );
  }

  @override
  ConsumerState<ZenFocusScreen> createState() => _ZenFocusScreenState();
}

class _ZenFocusScreenState extends ConsumerState<ZenFocusScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _now;
  late DateTime _currentEnd;
  late DateTime _baseStart;
  Timer? _ticker;
  String _ambientSound = 'none';

  static const List<String> _quotes = [
    '“Focus is a muscle. The more you practice, the stronger it gets.”',
    '“Deep work produces rare and valuable outcomes.”',
    '“Small daily improvements over time lead to stunning results.”',
    '“Do one thing at a time, and do it with full presence.”',
    '“Action is the foundational key to all success.”',
    '“Silence the noise. Protect your sacred focus time.”',
  ];
  late final String _currentQuote;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _currentEnd = widget.end;
    _baseStart = widget.startedAt ?? _now;
    _currentQuote = _quotes[Random().nextInt(_quotes.length)];
    _ambientSound = AmbientAudioService().currentSound;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _now = now);

      final currentSettings = ref.read(settingsProvider).value;
      if (currentSettings?.focusSessionEndsAt == null) {
        Navigator.of(context).maybePop();
        return;
      }

      final currentEnd = currentSettings?.focusSessionEndsAt ?? _currentEnd;
      if (!currentEnd.isAfter(now)) {
        FocusTimerService().handleTimerExpiry(ref, context: context);
      }
    });
  }

  @override
  void didUpdateWidget(ZenFocusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.end.isAfter(_currentEnd)) {
      _currentEnd = widget.end;
    }
    if (widget.startedAt != null && widget.startedAt != _baseStart) {
      _baseStart = widget.startedAt!;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _setAmbient(String sound) async {
    HapticFeedback.selectionClick();
    setState(() => _ambientSound = sound);
    await AmbientAudioService().setSound(sound);
  }

  void _handleExtend(int mins) {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentEnd = _currentEnd.add(Duration(minutes: mins));
    });
    widget.onExtend(mins);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final currentPhase = settings?.focusSessionPhase ?? widget.phase;
    final isBreak = currentPhase == 'break';
    final settingsEnd = settings?.focusSessionEndsAt;
    final activeEnd = (settingsEnd != null && settingsEnd.isAfter(_currentEnd))
        ? settingsEnd
        : _currentEnd;

    final totalSec =
        activeEnd.difference(_now).inSeconds.clamp(0, 24 * 60 * 60);
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;

    final effectiveStart = settings?.focusSessionStartedAt ?? widget.startedAt ?? _baseStart;
    final sessionTotalSec =
        activeEnd.difference(effectiveStart).inSeconds;
    final elapsedSec = _now.difference(effectiveStart).inSeconds;
    final progress = sessionTotalSec > 0
        ? (elapsedSec / sessionTotalSec).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.2,
            colors: [
              isBreak
                  ? Colors.amber.withValues(alpha: 0.12)
                  : const Color(0xFF4F46E5).withValues(alpha: 0.15),
              const Color(0xFF070B14),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Bar
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isBreak
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : const Color(0xFF6366F1)
                                        .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isBreak
                                      ? Colors.amber.withValues(alpha: 0.35)
                                      : const Color(0xFF6366F1)
                                          .withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isBreak
                                        ? Icons.local_cafe_outlined
                                        : Icons.timer_outlined,
                                    size: 15,
                                    color: isBreak
                                        ? Colors.amber
                                        : const Color(0xFF818CF8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isBreak
                                        ? 'Break Time'
                                        : (widget.presetLabel ?? 'Deep Focus'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isBreak
                                          ? Colors.amber
                                          : const Color(0xFF818CF8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.linkedTitle != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    widget.linkedTitle!,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit,
                                  color: Colors.white70, size: 24),
                              tooltip: 'Exit Zen Mode',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Center Timer Ring with Determinate Circular Progress
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 224,
                                height: 224,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 220,
                                      height: 220,
                                      child: CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 6.0,
                                        strokeCap: StrokeCap.round,
                                        backgroundColor: isBreak
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : const Color(0xFF6366F1)
                                                .withValues(alpha: 0.15),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          isBreak
                                              ? Colors.amber
                                              : const Color(0xFF818CF8),
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            fontSize: 54,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -2,
                                            color: Colors.white,
                                            fontFeatures: [
                                              FontFeature.tabularFigures()
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${(progress * 100).toInt()}% completed',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isBreak
                                                ? Colors.amber
                                                : const Color(0xFF818CF8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                isBreak
                                    ? 'Rest, breathe and re-energize'
                                    : 'Stay in the zone · Deep Work active',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  _currentQuote,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white.withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Bottom Ambient + Controls
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _ZenSoundChip(
                                    label: 'Off',
                                    icon: Icons.volume_off_outlined,
                                    active: _ambientSound == 'none',
                                    onTap: () => _setAmbient('none'),
                                  ),
                                  const SizedBox(width: 8),
                                  _ZenSoundChip(
                                    label: 'Rain',
                                    icon: Icons.water_drop_outlined,
                                    active: _ambientSound == 'rain',
                                    onTap: () => _setAmbient('rain'),
                                  ),
                                  const SizedBox(width: 8),
                                  _ZenSoundChip(
                                    label: 'Waves',
                                    icon: Icons.waves,
                                    active: _ambientSound == 'waves',
                                    onTap: () => _setAmbient('waves'),
                                  ),
                                  const SizedBox(width: 8),
                                  _ZenSoundChip(
                                    label: 'White Noise',
                                    icon: Icons.graphic_eq,
                                    active: _ambientSound == 'whitenoise',
                                    onTap: () => _setAmbient('whitenoise'),
                                  ),
                                  const SizedBox(width: 8),
                                  _ZenSoundChip(
                                    label: 'Cafe',
                                    icon: Icons.local_cafe_outlined,
                                    active: _ambientSound == 'cafe',
                                    onTap: () => _setAmbient('cafe'),
                                  ),
                                  const SizedBox(width: 8),
                                  _ZenSoundChip(
                                    label: 'Synth',
                                    icon: Icons.music_note_outlined,
                                    active: _ambientSound == 'synth',
                                    onTap: () => _setAmbient('synth'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.25)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.more_time_rounded, size: 16),
                                  label: Text(isBreak ? '+5m Break' : '+5 Min'),
                                  onPressed: () => _handleExtend(5),
                                ),
                                const SizedBox(width: 14),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isBreak
                                        ? const Color(0xFF6366F1)
                                        : Colors.redAccent.withValues(alpha: 0.85),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  icon: Icon(
                                      isBreak ? Icons.play_arrow_rounded : Icons.stop_circle_outlined,
                                      size: 18),
                                  label: Text(isBreak ? 'Resume Focus' : 'End Focus'),
                                  onPressed: () async {
                                    HapticFeedback.mediumImpact();
                                    if (isBreak) {
                                      await FocusTimerService().skipBreakAndStartWork(ref, context: context);
                                    } else {
                                      widget.onCancel();
                                    }
                                  },
                                ),
                                if (isBreak) ...[
                                  const SizedBox(width: 10),
                                  IconButton(
                                    tooltip: 'End focus session',
                                    icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70),
                                    onPressed: () {
                                      HapticFeedback.mediumImpact();
                                      widget.onCancel();
                                    },
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ZenSoundChip extends StatelessWidget {
  const _ZenSoundChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : Colors.white70,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
