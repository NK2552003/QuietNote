import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Exports whatever is painted inside a [RepaintBoundary] (identified by
/// [boundaryKey]) to a PDF, then offers it for sharing/saving.
///
/// This is deliberately a screenshot-based export rather than a "redraw the
/// markdown as PDF widgets" approach: it's the only way to guarantee the PDF
/// looks *exactly* like the on-screen preview, including rendered
/// ```mermaid``` diagrams — those are painted by `flutter_mermaid` as pixels
/// on a canvas, not expressed as vector text, so there is no independent PDF
/// representation of them to draw from note text alone. Capturing the
/// rendered widget tree keeps the PDF and the app view pixel-identical by
/// construction, and it also automatically covers everything else the
/// preview can render (images, tables, checklists) with zero extra code.
class MarkdownPdfExporter {
  /// Renders the boundary to a PDF file under the app's documents
  /// directory and returns it, or `null` if the boundary wasn't mounted /
  /// hadn't painted yet.
  static Future<File?> export({
    required GlobalKey boundaryKey,
    required String title,
    double pixelRatio = 2.5,
  }) async {
    // Let any pending frame finish painting before we capture it.
    await WidgetsBinding.instance.endOfFrame;

    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final ui.Image fullImage = await renderObject.toImage(
      pixelRatio: pixelRatio,
    );

    final pdf = pw.Document();
    const PdfPageFormat pageFormat = PdfPageFormat.a4;
    final double pageContentWidthPt = pageFormat.availableWidth;
    final double pxPerPt = fullImage.width / pageContentWidthPt;
    final double pageContentHeightPx = pageFormat.availableHeight * pxPerPt;

    final int totalHeightPx = fullImage.height;
    int offsetY = 0;
    while (offsetY < totalHeightPx) {
      final int sliceHeight = pageContentHeightPx
          .ceil()
          .clamp(1, totalHeightPx - offsetY);
      final Uint8List? sliceBytes = await _sliceToPng(
        fullImage,
        offsetY,
        sliceHeight,
      );
      offsetY += sliceHeight;
      if (sliceBytes == null) continue;
      final pw.MemoryImage image = pw.MemoryImage(sliceBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Image(image, fit: pw.BoxFit.fitWidth),
        ),
      );
    }

    final Directory dir = await getApplicationDocumentsDirectory();
    final String safeName = title.trim().isEmpty
        ? 'note'
        : title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String path = p.join(dir.path, 'exports', '$safeName.pdf');
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Crops a horizontal slice `[offsetY, offsetY + height)` out of [source]
  /// and re-encodes it as its own PNG, so a tall capture can be split
  /// across multiple same-size PDF pages instead of being squeezed or
  /// clipped onto one.
  static Future<Uint8List?> _sliceToPng(
    ui.Image source,
    int offsetY,
    int height,
  ) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Rect srcRect = Rect.fromLTWH(
      0,
      offsetY.toDouble(),
      source.width.toDouble(),
      height.toDouble(),
    );
    final Rect dstRect = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      height.toDouble(),
    );
    canvas.drawImageRect(source, srcRect, dstRect, Paint());
    final ui.Picture picture = recorder.endRecording();
    final ui.Image sliceImage = await picture.toImage(source.width, height);
    final ByteData? byteData = await sliceImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData?.buffer.asUint8List();
  }

  /// Convenience: export then immediately open the OS share sheet so the
  /// person can save it, print it, or send it somewhere.
  static Future<bool> exportAndShare({
    required GlobalKey boundaryKey,
    required String title,
  }) async {
    final File? file = await export(boundaryKey: boundaryKey, title: title);
    if (file == null) return false;
    await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      text: title,
    );
    return true;
  }
}
