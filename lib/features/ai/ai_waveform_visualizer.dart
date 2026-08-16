import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// An animated 5-bar audio frequency visualizer shown while voice capture is active.
class AiWaveformVisualizer extends StatefulWidget {
  const AiWaveformVisualizer({super.key, this.active = true, this.height = 24});

  final bool active;
  final double height;

  @override
  State<AiWaveformVisualizer> createState() => _AiWaveformVisualizerState();
}

class _AiWaveformVisualizerState extends State<AiWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AiWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    const barCount = 5;
    const minHeightRatio = 0.25;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (index) {
            final offset = index * 0.8;
            final wave = (math.sin(t + offset) + 1) / 2;
            final barHeight = widget.active
                ? widget.height * (minHeightRatio + (1 - minHeightRatio) * wave)
                : widget.height * minHeightRatio;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 3.5,
              height: barHeight.clamp(4.0, widget.height),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
