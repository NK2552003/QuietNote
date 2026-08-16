import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_common.dart';
import 'ui_toast.dart';

/// Toast host. Wrap the app root once, then call `UiToast.show(...)`.
/// Features modern Sonner-style stacked toasts with top-origin slide-down entrance,
/// spring scale-fading overlays, and gesture-driven swipe dismissal.
class UiToastScope extends StatefulWidget {
  const UiToastScope({super.key, required this.child});

  final Widget child;

  @override
  State<UiToastScope> createState() => UiToastScopeState();

  static UiToastScopeState of(BuildContext context) {
    final UiToastScopeState? state =
        context.findAncestorStateOfType<UiToastScopeState>();
    assert(state != null, 'Wrap your app with UiToastScope');
    return state!;
  }
}

class UiToastData {
  UiToastData({
    required this.title,
    this.message,
    this.intent = UiIntent.neutral,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 4),
  }) : id = UniqueKey().toString();

  final String id;
  final String title;
  final String? message;
  final UiIntent intent;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UiToastData && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

class UiToastScopeState extends State<UiToastScope> {
  final List<UiToastData> _toasts = <UiToastData>[];
  final Map<String, Timer> _timers = <String, Timer>{};
  bool _isExpanded = false;

  void show(UiToastData toast) {
    HapticFeedback.lightImpact();
    setState(() {
      // Newest toast is placed at the front (index 0)
      _toasts.insert(0, toast);
      // Limit queue to at most 5 items
      if (_toasts.length > 5) {
        final removed = _toasts.removeLast();
        _timers[removed.id]?.cancel();
        _timers.remove(removed.id);
      }
    });

    _scheduleDismiss(toast);
  }

  void _scheduleDismiss(UiToastData toast) {
    _timers[toast.id]?.cancel();
    _timers[toast.id] = Timer(toast.duration, () {
      if (mounted) dismiss(toast);
    });
  }

  void dismiss(UiToastData toast) {
    _timers[toast.id]?.cancel();
    _timers.remove(toast.id);
    if (!mounted) return;
    setState(() {
      _toasts.remove(toast);
      if (_toasts.isEmpty) _isExpanded = false;
    });
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: <Widget>[
        widget.child,
        if (_toasts.isNotEmpty)
          Positioned(
            top: topPadding + 10,
            left: 16,
            right: 16,
            child: Material(
              type: MaterialType.transparency,
              child: _buildSonnerStack(context),
            ),
          ),
      ],
    );
  }

  Widget _buildSonnerStack(BuildContext context) {
    if (_isExpanded) {
      // Expanded view: full vertical list of active toasts
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < _toasts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _buildDismissibleToast(_toasts[i], i, isExpanded: true),
          ],
        ],
      );
    }

    // Stacked Sonner mode: top item on front, older items stacked behind with scale & offset
    final visibleCount = _toasts.length.clamp(1, 3);
    final displayedToasts = _toasts.take(visibleCount).toList();

    return GestureDetector(
      onTap: () {
        if (_toasts.length > 1) {
          setState(() => _isExpanded = !_isExpanded);
        }
      },
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 6) {
          if (_toasts.length > 1 && !_isExpanded) {
            setState(() => _isExpanded = true);
          }
        }
      },
      child: SizedBox(
        height: 72.0 + (displayedToasts.length - 1) * 10.0,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Render in reverse so newest (index 0) sits at the very top of Stack
            for (int index = displayedToasts.length - 1; index >= 0; index--) ...[
              _buildStackedToast(displayedToasts[index], index),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStackedToast(UiToastData toast, int index) {
    // Stacking physics parameters
    final double translateY = index * 10.0;
    final double scale = (1.0 - (index * 0.05)).clamp(0.80, 1.0);
    final double opacity = (1.0 - (index * 0.24)).clamp(0.0, 1.0);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      top: translateY,
      left: 0,
      right: 0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        scale: scale,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: opacity,
          child: index == 0
              ? _buildDismissibleToast(toast, index, isExpanded: false)
              : IgnorePointer(
                  child: UiToast(data: toast),
                ),
        ),
      ),
    );
  }

  Widget _buildDismissibleToast(UiToastData toast, int index, {required bool isExpanded}) {
    return Dismissible(
      key: ValueKey<String>(toast.id),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => dismiss(toast),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        tween: Tween<double>(begin: 0.0, end: 1.0),
        builder: (context, val, child) {
          return Transform.translate(
            offset: Offset(0, -18 * (1.0 - val)),
            child: Opacity(
              opacity: val.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: UiToast(
          data: toast,
          isExpanded: isExpanded,
          onDismiss: () => dismiss(toast),
        ),
      ),
    );
  }
}
