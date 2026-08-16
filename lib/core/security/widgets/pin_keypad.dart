import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Professional, tactile numeric keypad with clean, centered digits and haptic feedback.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onBackspacePressed,
    this.onBackspaceLongPressed,
    this.leftAccessory,
    this.rightAccessory,
    this.enabled = true,
  });

  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspacePressed;
  final VoidCallback? onBackspaceLongPressed;
  final Widget? leftAccessory;
  final Widget? rightAccessory;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<List<String>> matrix = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['left', '0', 'backspace'],
    ];

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: matrix.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                if (key == 'left') {
                  return leftAccessory != null
                      ? SizedBox(
                          width: 72,
                          height: 72,
                          child: Center(child: leftAccessory),
                        )
                      : const SizedBox(width: 72, height: 72);
                }

                if (key == 'backspace') {
                  if (rightAccessory != null) {
                    return SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(child: rightAccessory),
                    );
                  }
                  return _KeypadBackspaceButton(
                    isDark: isDark,
                    enabled: enabled,
                    onPressed: onBackspacePressed,
                    onLongPressed: onBackspaceLongPressed,
                  );
                }

                return _KeypadDigitButton(
                  digit: key,
                  isDark: isDark,
                  enabled: enabled,
                  onTap: () => onDigitPressed(key),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _KeypadDigitButton extends StatefulWidget {
  const _KeypadDigitButton({
    required this.digit,
    required this.isDark,
    required this.enabled,
    required this.onTap,
  });

  final String digit;
  final bool isDark;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_KeypadDigitButton> createState() => _KeypadDigitButtonState();
}

class _KeypadDigitButtonState extends State<_KeypadDigitButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark
        ? (_isPressed
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.07))
        : (_isPressed
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.04));

    final borderColor = widget.isDark
        ? (_isPressed
            ? Colors.white.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.09))
        : (_isPressed
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.06));

    final textColor = widget.isDark ? Colors.white : const Color(0xFF1C1B1F);

    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) {
              setState(() => _isPressed = true);
              HapticFeedback.selectionClick();
            }
          : null,
      onTapUp: (_) {
        if (_isPressed) setState(() => _isPressed = false);
      },
      onTapCancel: () {
        if (_isPressed) setState(() => _isPressed = false);
      },
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: widget.isDark
                        ? Colors.black.withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            widget.digit,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: textColor,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _KeypadBackspaceButton extends StatefulWidget {
  const _KeypadBackspaceButton({
    required this.isDark,
    required this.enabled,
    required this.onPressed,
    this.onLongPressed,
  });

  final bool isDark;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback? onLongPressed;

  @override
  State<_KeypadBackspaceButton> createState() => _KeypadBackspaceButtonState();
}

class _KeypadBackspaceButtonState extends State<_KeypadBackspaceButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark
        ? (_isPressed
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent)
        : (_isPressed
            ? Colors.black.withValues(alpha: 0.08)
            : Colors.transparent);

    final iconColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.8)
        : Colors.black.withValues(alpha: 0.7);

    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) {
              setState(() => _isPressed = true);
              HapticFeedback.selectionClick();
            }
          : null,
      onTapUp: (_) {
        if (_isPressed) setState(() => _isPressed = false);
      },
      onTapCancel: () {
        if (_isPressed) setState(() => _isPressed = false);
      },
      onTap: widget.enabled ? widget.onPressed : null,
      onLongPress: widget.enabled && widget.onLongPressed != null
          ? () {
              HapticFeedback.mediumImpact();
              widget.onLongPressed!();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.backspace_outlined,
            color: iconColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}
