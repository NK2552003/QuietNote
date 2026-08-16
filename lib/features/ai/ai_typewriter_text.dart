import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// Smooth streaming typewriter text widget for AI bubbles.
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.charDuration = const Duration(milliseconds: 14),
    this.onComplete,
    this.enableCursor = true,
  });

  final String text;
  final TextStyle? style;
  final Duration charDuration;
  final VoidCallback? onComplete;
  final bool enableCursor;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _charCount = 0;
  bool _isFinished = false;

  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _startTyping();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startTyping();
    }
  }

  void _startTyping() {
    _timer?.cancel();
    _charCount = 0;
    _isFinished = false;

    if (widget.text.isEmpty) {
      setState(() => _isFinished = true);
      widget.onComplete?.call();
      return;
    }

    _timer = Timer.periodic(widget.charDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_charCount < widget.text.length) {
        setState(() {
          _charCount = (_charCount + 1).clamp(0, widget.text.length);
        });
      } else {
        timer.cancel();
        setState(() => _isFinished = true);
        widget.onComplete?.call();
      }
    });
  }

  void _skipToEnd() {
    if (_isFinished) return;
    _timer?.cancel();
    setState(() {
      _charCount = widget.text.length;
      _isFinished = true;
    });
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final defaultStyle = context.uiText.body;
    final effectiveStyle = widget.style ?? defaultStyle;
    final visibleText = widget.text.substring(0, _charCount);

    return GestureDetector(
      onTap: _skipToEnd,
      child: RichText(
        text: TextSpan(
          style: effectiveStyle,
          children: [
            TextSpan(text: visibleText),
            if (widget.enableCursor && !_isFinished)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: FadeTransition(
                  opacity: _cursorController,
                  child: Container(
                    margin: const EdgeInsets.only(left: 2),
                    width: 2,
                    height: (effectiveStyle.fontSize ?? 14) * 1.1,
                    color: c.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
