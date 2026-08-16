import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders a widget that is **not** part of the visible UI and returns it as
/// PNG bytes.
///
/// Used by the PDF exporter for the handful of things a text-based PDF can't
/// express as text — ```mermaid``` flowcharts and ```chart``` blocks are
/// painted onto a canvas by their Flutter widgets, so the only faithful
/// representation of them in a document is a picture of that widget.
///
/// The widget is mounted into the app's [Overlay] positioned far off to the
/// left of the screen: it's genuinely laid out and painted (so
/// `RenderRepaintBoundary.toImage` has something to rasterize), but never
/// visible to the person. `Offstage` can't be used here — it skips painting
/// entirely, which yields a blank capture.
class OffscreenWidgetCapture {
  /// Mounts [child] at [width] logical pixels wide, waits for it to settle,
  /// captures it at [pixelRatio], then removes it again. Returns `null` if
  /// the overlay wasn't available or the capture failed.
  static Future<Uint8List?> capture(
    BuildContext context, {
    required Widget child,
    double width = 720,
    double pixelRatio = 3,
    Duration settle = const Duration(milliseconds: 700),
  }) async {
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;

    final GlobalKey boundaryKey = GlobalKey();
    final MediaQueryData media = MediaQuery.of(context);
    final ThemeData theme = Theme.of(context);

    final OverlayEntry entry = OverlayEntry(
      builder: (_) => Positioned(
        // Far off-screen: painted, never seen.
        left: -(width + 200),
        top: 0,
        child: MediaQuery(
          data: media.copyWith(textScaler: TextScaler.noScaling),
          child: Theme(
            data: theme,
            child: Directionality(
              textDirection: Directionality.of(context),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: width,
                  // Diagrams lay out at their own natural size, which makes a
                  // narrow flowchart capture as a small image floating in a
                  // wide frame. Fitting to the target width means every
                  // capture arrives at a consistent, predictable resolution
                  // for the page, with aspect ratio preserved.
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                ),
              ),

            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    try {
      // Two frames to lay out, then a settle window: mermaid parses and
      // measures its diagram asynchronously and only reaches its final size
      // a few frames in.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(settle);
      await WidgetsBinding.instance.endOfFrame;

      final RenderObject? renderObject =
          boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return null;
      if (renderObject.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }

      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      final ByteData? bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      entry.remove();
    }
  }
}
