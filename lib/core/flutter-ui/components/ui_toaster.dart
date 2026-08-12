import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_toast.dart';

/// Toast host. Wrap the app body once, then call `UiToast.show(...)`.
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
  const UiToastData({
    required this.title,
    this.message,
    this.intent = UiIntent.neutral,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 4),
  });

  final String title;
  final String? message;
  final UiIntent intent;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
}

class UiToastScopeState extends State<UiToastScope> {
  final List<UiToastData> _queue = <UiToastData>[];

  void show(UiToastData toast) {
    setState(() => _queue.add(toast));
    Future<void>.delayed(toast.duration, () {
      if (mounted && _queue.contains(toast)) {
        setState(() => _queue.remove(toast));
      }
    });
  }

  void dismiss(UiToastData toast) => setState(() => _queue.remove(toast));

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool mobile = context.uiRes.isMobile;
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          left: mobile ? context.sp(theme.spacing.lg) : null,
          right: context.sp(theme.spacing.lg),
          bottom: context.sp(theme.spacing.xl),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final UiToastData t in _queue)
                  Padding(
                    padding: EdgeInsets.only(top: context.sp(theme.spacing.sm)),
                    child: UiToast(data: t, onDismiss: () => dismiss(t)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
