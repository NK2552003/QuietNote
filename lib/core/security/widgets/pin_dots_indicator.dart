import 'dart:math';
import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// Animated PIN dots indicator with smooth fill, glow, and error shake animation.
class PinDotsIndicator extends StatefulWidget {
  const PinDotsIndicator({
    super.key,
    required this.pinLength,
    required this.enteredLength,
    required this.accentColor,
    this.hasError = false,
    this.obscure = true,
  });

  final int pinLength;
  final int enteredLength;
  final Color accentColor;
  final bool hasError;
  final bool obscure;

  @override
  State<PinDotsIndicator> createState() => PinDotsIndicatorState();
}

class PinDotsIndicatorState extends State<PinDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant PinDotsIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      shake();
    }
  }

  void shake() {
    _shakeController.forward(from: 0);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // Sine wave shake offset: -16px to +16px
        final double offset = sin(_shakeAnimation.value * pi * 4) *
            16 *
            (1 - _shakeAnimation.value);
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.pinLength, (index) {
          final bool isFilled = index < widget.enteredLength;
          final bool isCurrent = index == widget.enteredLength - 1;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: isFilled ? 18 : 16,
            height: isFilled ? 18 : 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.hasError
                  ? theme.colors.destructive
                  : isFilled
                      ? widget.accentColor
                      : Colors.transparent,
              border: Border.all(
                color: widget.hasError
                    ? theme.colors.destructive
                    : isFilled
                        ? widget.accentColor
                        : isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.25),
                width: isFilled ? 0 : 2,
              ),
              boxShadow: isFilled
                  ? [
                      BoxShadow(
                        color: (widget.hasError
                                ? theme.colors.destructive
                                : widget.accentColor)
                            .withValues(alpha: isCurrent ? 0.45 : 0.25),
                        blurRadius: isCurrent ? 12 : 6,
                        spreadRadius: isCurrent ? 2 : 0,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }
}
