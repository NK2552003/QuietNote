import 'package:flutter/material.dart';

/// A full-screen, blocking "working on it" overlay for exports.
///
/// PDF export is a multi-second job: diagrams are rendered off-screen (which
/// otherwise visibly flashes over the preview), pages are laid out, then the
/// share sheet opens. Without feedback the screen looks frozen and a second
/// tap starts a duplicate export. This mounts an opaque scrim with a spinner,
/// a title and a live step label into the root [Overlay] for the duration of
/// [task], swallowing all pointer input, and always removes it again — on
/// success, on error, and on cancel.
///
/// Returns the task's result, or `null` when an export is already running.
Future<T?> runWithProgressOverlay<T>(
  BuildContext context, {
  required Future<T> Function(void Function(String step) setStep) task,
  String title = 'Preparing PDF…',
  String initialStep = 'Rendering diagrams',
}) async {
  if (_overlayActive) return null;

  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    // No overlay to attach to (very early in startup) — never block the work.
    return task((_) {});
  }

  final ValueNotifier<String> step = ValueNotifier<String>(initialStep);
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext ctx) => _ProgressScrim(title: title, step: step),
  );

  _overlayActive = true;
  overlay.insert(entry);
  try {
    return await task((String next) {
      if (entry.mounted) step.value = next;
    });
  } finally {
    entry.remove();
    step.dispose();
    _overlayActive = false;
  }
}

bool _overlayActive = false;

class _ProgressScrim extends StatelessWidget {
  const _ProgressScrim({required this.title, required this.step});

  final String title;
  final ValueNotifier<String> step;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Positioned.fill(
      // `absorbing` blocks every tap underneath, so the off-screen diagram
      // render can't be interrupted and the export can't be started twice.
      child: AbsorbPointer(
        child: ColoredBox(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ValueListenableBuilder<String>(
                  valueListenable: step,
                  builder: (_, String value, __) => Text(
                    value,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
