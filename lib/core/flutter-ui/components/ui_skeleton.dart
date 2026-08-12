import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

/// Shimmer-free skeleton placeholder for loading states.
class UiSkeleton extends StatefulWidget {
  const UiSkeleton({
    super.key,
    this.width,
    this.height,
    this.circle = false,
  });

  final double? width;
  final double? height;
  final bool circle;

  @override
  State<UiSkeleton> createState() => _UiSkeletonState();
}

class _UiSkeletonState extends State<UiSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext ctx, Widget? _) => Container(
        width: widget.width,
        height: ctx.sz(widget.height ?? 14),
        decoration: BoxDecoration(
          color: Color.lerp(
            theme.colors.surfaceMuted,
            theme.colors.border,
            _controller.value,
          ),
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius:
              widget.circle ? null : ctx.radius(theme.radii.sm),
        ),
      ),
    );
  }
}
