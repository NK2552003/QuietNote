import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Exports whatever is painted inside a [RepaintBoundary] (identified by
/// [boundaryKey]) to a PNG file, then offers it for sharing/saving. Used to
/// let a diagram (mermaid flowchart, chart) be downloaded/shared as an
/// image independent of the rest of the note.
class PngExporter {
  static Future<File?> export({
    required GlobalKey boundaryKey,
    required String filename,
    double pixelRatio = 3,
  }) async {
    await WidgetsBinding.instance.endOfFrame;

    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final Directory dir = await getApplicationDocumentsDirectory();
    final String safeName = filename.trim().isEmpty
        ? 'diagram'
        : filename.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String path = p.join(dir.path, 'exports', '$safeName.png');
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  static Future<bool> exportAndShare({
    required GlobalKey boundaryKey,
    required String filename,
  }) async {
    final File? file = await export(boundaryKey: boundaryKey, filename: filename);
    if (file == null) return false;
    await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'image/png')],
      text: filename,
    );
    return true;
  }
}
