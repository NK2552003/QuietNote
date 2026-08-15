import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart'
    show BuildContext, Color, ColoredBox, EdgeInsets, Padding;
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quietnote/core/markdown_kit/chart_block.dart';
import 'package:quietnote/core/markdown_kit/flowchart/flowchart_view.dart';
import 'package:quietnote/core/markdown_kit/markdown_preview.dart';
import 'package:quietnote/core/markdown_kit/math_syntax.dart';
import 'package:quietnote/core/utils/pdf_export_options.dart';
import 'package:quietnote/core/utils/widget_capture.dart';
import 'package:share_plus/share_plus.dart';

/// Generates a **real, text-based PDF** from a note's markdown — not a
/// screenshot of the on-screen preview.
///
/// The markdown is parsed with exactly the same parser and extension set the
/// preview uses, then the resulting document tree is re-emitted as native PDF
/// widgets: embedded TrueType fonts at 12pt, headings, ordered/unordered and
/// task lists, block quotes, tables, fenced code blocks, links, images, rules,
/// page margins and a "Page x of y" footer. Text in the output is selectable,
/// searchable and prints at full resolution at any zoom level.
///
/// The only things captured as pictures are the two block types that have no
/// textual representation at all — ```mermaid``` flowcharts and ```chart```
/// blocks, which are painted onto a canvas by their Flutter widgets. Those are
/// rendered off-screen at high resolution and embedded as figures in place.
class MarkdownPdfExporter {
  /// Writes the PDF under the app's documents directory and returns the file.
  ///
  /// [context] is only needed to render mermaid/chart figures; without it
  /// those blocks fall back to their source text in a code box and everything
  /// else exports normally.
  static Future<File?> export({
    required String markdown,
    required String title,
    String? subtitle,
    BuildContext? context,
    Future<Uint8List?> Function(Uri uri)? imageResolver,
    PdfExportOptions options = const PdfExportOptions(),
    void Function(String step)? onStep,
  }) async {
    try {
      debugPrint('MarkdownPdfExporter: loading fonts');
      final _PdfFonts fonts = await _PdfFonts.load();
      debugPrint('MarkdownPdfExporter: parsing markdown');
      final List<md.Node> nodes = _parse(markdown);

      final Map<String, Uint8List> figures = <String, Uint8List>{};
      if (options.includeDiagrams && context != null && context.mounted) {
        onStep?.call('Rendering diagrams');
        debugPrint('MarkdownPdfExporter: capturing figures');
        await _captureFigures(context, nodes, figures, options);
      }

      final Map<String, Uint8List> images = <String, Uint8List>{};
      if (imageResolver != null) {
        debugPrint('MarkdownPdfExporter: resolving images');
        await _resolveImages(nodes, imageResolver, images);
      }

      onStep?.call('Building pages');
      debugPrint('MarkdownPdfExporter: building pages');
      final _PdfMarkdownBuilder builder = _PdfMarkdownBuilder(
        fonts: fonts,
        figures: figures,
        images: images,
      );
      final List<pw.Widget> body = builder.buildBlocks(nodes);

      final pw.Document doc = pw.Document(
        title: title,
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.italic,
          boldItalic: fonts.boldItalic,
        ),
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: options.paperSize == PdfPaperSize.letter
              ? PdfPageFormat.letter
              : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(56, 54, 56, 54),
          header: (pw.Context ctx) {
            if (ctx.pageNumber == 1) return pw.SizedBox();
            return pw.Container(
              alignment: pw.Alignment.centerLeft,
              margin: const pw.EdgeInsets.only(bottom: 16),
              padding: const pw.EdgeInsets.only(bottom: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: _PdfPalette.hairline,
                    width: 0.6,
                  ),
                ),
              ),
              child: pw.Text(
                title,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: _PdfPalette.muted,
                ),
              ),
            );
          },
          footer: options.includePageNumbers
              ? (pw.Context ctx) => pw.Container(
                  alignment: pw.Alignment.centerRight,
                  margin: const pw.EdgeInsets.only(top: 14),
                  child: pw.Text(
                    'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 9,
                      color: _PdfPalette.muted,
                    ),
                  ),
                )
              : null,
          build: (pw.Context ctx) => <pw.Widget>[
            if (options.includeTitle)
              ..._titleBlock(
                fonts,
                title,
                options.includeSubtitle ? subtitle : null,
              ),
            ...body,
          ],
        ),
      );

      final Directory dir = await getApplicationDocumentsDirectory();
      final String safeName = title.trim().isEmpty
          ? 'note'
          : title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final File file = File(p.join(dir.path, 'exports', '$safeName.pdf'));
      await file.parent.create(recursive: true);
      debugPrint('MarkdownPdfExporter: saving to ${file.path}');
      await file.writeAsBytes(await doc.save());
      debugPrint('MarkdownPdfExporter: export succeeded');
      return file;
    } catch (error, stackTrace) {
      // The caller only ever sees a generic "couldn't export" toast (export
      // failures are common enough — an odd character, a huge table, a
      // flaky off-screen render — that surfacing raw exceptions in the UI
      // would be more confusing than helpful). But swallowing the error
      // silently made every failure equally invisible to us too, so it's
      // printed here: reproduce the failed export with `flutter run`
      // attached and this line will show up right in that same terminal —
      // look for "MarkdownPdfExporter: PDF export failed".
      debugPrint('MarkdownPdfExporter: PDF export failed — $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// Convenience: export then immediately open the OS share sheet so the
  /// person can save it, print it, or send it somewhere.
  static Future<bool> exportAndShare({
    required String markdown,
    required String title,
    String? subtitle,
    BuildContext? context,
    Future<Uint8List?> Function(Uri uri)? imageResolver,
    PdfExportOptions options = const PdfExportOptions(),
    void Function(String step)? onStep,
  }) async {
    final File? file = await export(
      markdown: markdown,
      title: title,
      subtitle: subtitle,
      context: context,
      imageResolver: imageResolver,
      options: options,
      onStep: onStep,
    );
    if (file == null) return false;
    onStep?.call('Opening share sheet');
    await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      text: title,
    );
    return true;
  }

  static List<pw.Widget> _titleBlock(
    _PdfFonts fonts,
    String title,
    String? subtitle,
  ) {
    return <pw.Widget>[
      pw.Text(
        title.trim().isEmpty ? 'Untitled' : title.trim(),
        style: pw.TextStyle(
          font: fonts.bold,
          fontWeight: pw.FontWeight.bold,
          fontSize: 22,
          color: _PdfPalette.text,
        ),
      ),
      if (subtitle != null && subtitle.trim().isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            subtitle.trim(),
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 10.5,
              color: _PdfPalette.muted,
            ),
          ),
        ),
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 18),
        height: 0.8,
        color: _PdfPalette.hairline,
      ),
    ];
  }

  static List<md.Node> _parse(String markdown) {
    final md.Document document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: <md.InlineSyntax>[
        MathBlockSyntax(),
        MathInlineSyntax(),
        HighlightMarkSyntax(),
      ],
      encodeHtml: false,
    );
    final String source = normalizeHeadingBoundaries(markdown);
    return document.parseLines(source.split('\n'));
  }

  /// Renders every ```mermaid``` / ```chart``` block off-screen and stores the
  /// PNG bytes under a key derived from the block's own source, so the builder
  /// can drop the right picture into the right place.
  static Future<void> _captureFigures(
    BuildContext context,
    List<md.Node> nodes,
    Map<String, Uint8List> out,
    PdfExportOptions options,
  ) async {
    final List<_FencedBlock> blocks = <_FencedBlock>[];
    _collectFences(nodes, blocks);

    for (final _FencedBlock block in blocks) {
      if (block.language != 'mermaid' && block.language != 'chart') continue;
      final String key = _figureKey(block.language, block.source);
      if (out.containsKey(key)) continue;
      if (!context.mounted) return;

      // One malformed diagram (bad mermaid syntax, a chart spec that fails
      // to parse, an off-screen render that times out) used to take the
      // whole export down with it, since this call sat outside any
      // try/catch and the exception would bubble all the way up to
      // [export]'s catch — killing pages of otherwise-fine content over one
      // figure. Each figure now fails on its own: it's simply dropped and
      // the PDF gets a fallback source-text box for it (see the builder),
      // while every other block still exports normally.
      try {
        final Uint8List? bytes = await OffscreenWidgetCapture.capture(
          context,
          width: options.diagramQuality == PdfDiagramQuality.high ? 1000 : 760,
          pixelRatio:
              options.diagramQuality == PdfDiagramQuality.high ? 4 : 2.5,
          settle: options.diagramQuality == PdfDiagramQuality.high
              ? const Duration(milliseconds: 1200)
              : const Duration(milliseconds: 800),
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: block.language == 'mermaid'

                  // A printed page is white, so diagrams always use a fixed
                  // light palette regardless of the current app theme.
                  ? FlowchartView(
                      source: block.source,
                      palette: FlowchartPalette.printFriendly(),
                    )
                  : ChartBlock(spec: block.source),
            ),
          ),
        );
        if (bytes != null) out[key] = bytes;
      } catch (error, stackTrace) {
        debugPrint(
          'MarkdownPdfExporter: figure render failed for a '
          '${block.language} block, skipping it — $error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  static Future<void> _resolveImages(
    List<md.Node> nodes,
    Future<Uint8List?> Function(Uri uri) resolver,
    Map<String, Uint8List> out,
  ) async {
    final Set<String> sources = <String>{};
    _collectImageSources(nodes, sources);
    for (final String src in sources) {
      final Uri? uri = Uri.tryParse(src);
      if (uri == null) continue;
      try {
        final Uint8List? bytes = await resolver(uri);
        if (bytes != null && bytes.isNotEmpty) out[src] = bytes;
      } catch (_) {
        // A broken image must never abort the whole export.
      }
    }
  }

  static void _collectFences(List<md.Node> nodes, List<_FencedBlock> out) {
    for (final md.Node node in nodes) {
      if (node is! md.Element) continue;
      if (node.tag == 'pre') {
        final md.Element? code = _firstElement(node.children);
        if (code != null && code.tag == 'code') {
          final String cls = code.attributes['class'] ?? '';
          out.add(
            _FencedBlock(
              language: cls.replaceFirst('language-', '').trim(),
              source: code.textContent.trim(),
            ),
          );
        }
        continue;
      }
      final List<md.Node>? children = node.children;
      if (children != null) _collectFences(children, out);
    }
  }

  static void _collectImageSources(List<md.Node> nodes, Set<String> out) {
    for (final md.Node node in nodes) {
      if (node is! md.Element) continue;
      if (node.tag == 'img') {
        final String? src = node.attributes['src'];
        if (src != null && src.isNotEmpty) out.add(src);
      }
      final List<md.Node>? children = node.children;
      if (children != null) _collectImageSources(children, out);
    }
  }
}

String _figureKey(String language, String source) => '$language\u0000$source';

/// First child element of [nodes], or null. (Avoids depending on
/// `package:collection`'s `firstOrNull` extension.)
md.Element? _firstElement(List<md.Node>? nodes) {
  if (nodes == null) return null;
  for (final md.Node node in nodes) {
    if (node is md.Element) return node;
  }
  return null;
}

class _FencedBlock {
  const _FencedBlock({required this.language, required this.source});
  final String language;
  final String source;
}

class _PdfPalette {
  static const PdfColor text = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor muted = PdfColor.fromInt(0xFF6B6B6B);
  static const PdfColor hairline = PdfColor.fromInt(0xFFD8D5CF);
  static const PdfColor codeBackground = PdfColor.fromInt(0xFFF5F4F1);
  static const PdfColor tableHeader = PdfColor.fromInt(0xFFF0EEE9);
  static const PdfColor link = PdfColor.fromInt(0xFF1F5FBF);
  static const PdfColor highlight = PdfColor.fromInt(0xFFFFF3B0);
}

class _PdfFonts {
  _PdfFonts({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.mono,
    required this.monoBold,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;
  final pw.Font mono;
  final pw.Font monoBold;

  static _PdfFonts? _cached;

  static Future<_PdfFonts> load() async {
    final _PdfFonts? cached = _cached;
    if (cached != null) return cached;

    Future<pw.Font> font(String name) async {
      final ByteData data = await rootBundle.load('assets/fonts/$name.ttf');
      return pw.Font.ttf(data);
    }

    final _PdfFonts loaded = _PdfFonts(
      regular: await font('NotoSans-Regular'),
      bold: await font('NotoSans-Bold'),
      italic: await font('NotoSans-Italic'),
      boldItalic: await font('NotoSans-BoldItalic'),
      mono: await font('NotoSansMono-Regular'),
      monoBold: await font('NotoSansMono-Bold'),
    );
    _cached = loaded;
    return loaded;
  }
}

/// Walks the parsed markdown tree and emits native PDF widgets for it.
class _PdfMarkdownBuilder {
  _PdfMarkdownBuilder({
    required this.fonts,
    required this.figures,
    required this.images,
  });

  final _PdfFonts fonts;
  final Map<String, Uint8List> figures;
  final Map<String, Uint8List> images;

  static const double _bodySize = 12;
  static const double _blockGap = 10;

  pw.TextStyle get _body => pw.TextStyle(
        font: fonts.regular,
        fontSize: _bodySize,
        color: _PdfPalette.text,
        lineSpacing: 3.4,
      );

  pw.TextStyle _heading(int level) {
    const Map<int, double> sizes = <int, double>{
      1: 21,
      2: 17,
      3: 14.5,
      4: 13,
      5: 12,
      6: 11.5,
    };
    return pw.TextStyle(
      font: fonts.bold,
      fontWeight: pw.FontWeight.bold,
      fontSize: sizes[level] ?? 12,
      color: level >= 6 ? _PdfPalette.muted : _PdfPalette.text,
      lineSpacing: 2.5,
    );
  }

  List<pw.Widget> buildBlocks(List<md.Node> nodes) {
    final List<pw.Widget> out = <pw.Widget>[];
    for (final md.Node node in nodes) {
      final pw.Widget? widget = _block(node);
      if (widget == null) continue;
      out.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: _blockGap),
          child: widget,
        ),
      );
    }
    return out;
  }

  pw.Widget? _block(md.Node node) {
    if (node is md.Text) {
      final String text = node.text.trim();
      if (text.isEmpty) return null;
      return pw.Text(text, style: _body);
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final int level = int.tryParse(node.tag.substring(1)) ?? 1;
        return pw.Padding(
          padding: pw.EdgeInsets.only(top: level <= 2 ? 8 : 4),
          child: pw.RichText(
            text: pw.TextSpan(
              children: _inline(node.children, _heading(level)),
            ),
          ),
        );

      case 'p':
        return _paragraph(node);

      case 'blockquote':
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: pw.BoxDecoration(
            color: _PdfPalette.codeBackground,
            border: pw.Border(
              left: pw.BorderSide(color: _PdfPalette.hairline, width: 3),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: _stripLastGap(buildBlocks(node.children ?? const [])),
          ),
        );

      case 'pre':
        return _preformatted(node);

      case 'ul':
        return _list(node, ordered: false);
      case 'ol':
        return _list(node, ordered: true);

      case 'hr':
        return pw.Container(height: 0.8, color: _PdfPalette.hairline);

      case 'table':
        return _table(node);

      case 'img':
        return _image(node.attributes['src'] ?? '');

      case 'math_block':
        return pw.Container(
          width: double.infinity,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Text(
            node.textContent.trim(),
            style: pw.TextStyle(
              font: fonts.mono,
              fontSize: _bodySize,
              color: _PdfPalette.text,
            ),
          ),
        );

      default:
        final List<md.Node>? children = node.children;
        if (children == null || children.isEmpty) return null;
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: _stripLastGap(buildBlocks(children)),
        );
    }
  }

  /// A paragraph made up of nothing but an image becomes a figure; otherwise
  /// any images it contains are emitted underneath the text.
  pw.Widget? _paragraph(md.Element node) {
    final List<md.Node> children = node.children ?? const <md.Node>[];
    final List<md.Element> imgs = children
        .whereType<md.Element>()
        .where((md.Element e) => e.tag == 'img')
        .toList();
    final bool textOnlyWhitespace = children.every(
      (md.Node n) =>
          (n is md.Element && n.tag == 'img') ||
          (n is md.Text && n.text.trim().isEmpty),
    );

    if (imgs.isNotEmpty && textOnlyWhitespace) {
      final List<pw.Widget> figures = <pw.Widget>[];
      for (final md.Element img in imgs) {
        final pw.Widget? w = _image(img.attributes['src'] ?? '');
        if (w != null) figures.add(w);
      }
      if (figures.isEmpty) return null;
      if (figures.length == 1) return figures.first;
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: figures,
      );
    }

    final List<pw.InlineSpan> spans = _inline(children, _body);
    if (spans.isEmpty && imgs.isEmpty) return null;

    final pw.Widget text = pw.RichText(
      text: pw.TextSpan(children: spans),
    );
    if (imgs.isEmpty) return text;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        text,
        for (final md.Element img in imgs)
          ...<pw.Widget>[
            pw.SizedBox(height: 6),
            _image(img.attributes['src'] ?? '') ?? pw.SizedBox(),
          ],
      ],
    );
  }

  pw.Widget? _image(String src) {
    final Uint8List? bytes = images[src];
    if (bytes == null) {
      return pw.Text(
        '[image]',
        style: pw.TextStyle(
          font: fonts.italic,
          fontStyle: pw.FontStyle.italic,
          fontSize: 10,
          color: _PdfPalette.muted,
        ),
      );
    }
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.ConstrainedBox(
        constraints: const pw.BoxConstraints(maxHeight: 340),
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
      ),
    );
  }

  pw.Widget _preformatted(md.Element node) {
    final md.Element? code = _firstElement(node.children);
    final String cls = code?.attributes['class'] ?? '';
    final String language = cls.replaceFirst('language-', '').trim();
    final String source = (code?.textContent ?? node.textContent).trimRight();

    if (language == 'mermaid' || language == 'chart') {
      final Uint8List? figure = figures[_figureKey(language, source.trim())];
      if (figure != null) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Container(
              width: double.infinity,
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _PdfPalette.hairline, width: 0.6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              // `fit: fitWidth` inside a width-only SizedBox used to let a
              // tall, narrow diagram scale to a height *taller than the
              // page itself* — a plain Container isn't a SpanningWidget, so
              // MultiPage couldn't split it, couldn't fit it on a fresh
              // page either, and gave up with a TooManyPagesException,
              // silently failing the whole export. Bounding both width AND
              // height here with `BoxFit.contain` guarantees the figure
              // always fits within a single page's content area — it
              // scales down (preserving aspect ratio) instead of forcing
              // an impossible layout.
              child: pw.ConstrainedBox(
                constraints: pw.BoxConstraints(
                  maxWidth: _contentWidth - 18,
                  maxHeight: _contentHeight - 60,
                ),
                child: pw.Image(
                  pw.MemoryImage(figure),
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              language == 'mermaid' ? 'Flowchart' : 'Chart',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 9,
                color: _PdfPalette.muted,
              ),
            ),
          ],
        );

      }
      // Couldn't render the diagram — fall through and print its source
      // rather than losing the content entirely.
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: pw.BoxDecoration(
        color: _PdfPalette.codeBackground,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _PdfPalette.hairline, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          if (language.isNotEmpty) ...<pw.Widget>[
            pw.Text(
              language,
              style: pw.TextStyle(
                font: fonts.monoBold,
                fontSize: 8.5,
                color: _PdfPalette.muted,
              ),
            ),
            pw.SizedBox(height: 6),
          ],
          pw.Text(
            source,
            style: pw.TextStyle(
              font: fonts.mono,
              fontSize: 9.8,
              color: _PdfPalette.text,
              lineSpacing: 2.6,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _list(md.Element node, {required bool ordered, int depth = 0}) {
    final List<md.Element> items = (node.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((md.Element e) => e.tag == 'li')
        .toList();

    int index = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final List<pw.Widget> rows = <pw.Widget>[];

    for (final md.Element item in items) {
      final _ListItem parsed = _listItem(item);
      final String marker = ordered ? '${index++}.' : (depth.isEven ? '•' : '-');

      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.SizedBox(width: depth * 16.0),
              if (parsed.checkbox == null)
                pw.Container(
                  width: 18,
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: pw.Text(marker, style: _body),
                )
              else
                pw.Container(
                  width: 18,
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Container(
                    width: 9,
                    height: 9,
                    decoration: pw.BoxDecoration(
                      color: parsed.checkbox == true
                          ? _PdfPalette.text
                          : PdfColors.white,
                      border: pw.Border.all(
                        color: _PdfPalette.muted,
                        width: 0.8,
                      ),
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    if (parsed.inline.isNotEmpty)
                      pw.RichText(
                        text: pw.TextSpan(children: parsed.inline),
                      ),
                    for (final md.Element child in parsed.blocks)
                      if (child.tag == 'ul' || child.tag == 'ol')
                        _list(
                          child,
                          ordered: child.tag == 'ol',
                          depth: depth + 1,
                        )
                      else
                        ...buildBlocks(<md.Node>[child]),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// Splits a list item into its own inline content (the text on the bullet's
  /// line) and any nested block children (sub-lists, extra paragraphs).
  _ListItem _listItem(md.Element item) {
    final List<md.Node> children = item.children ?? const <md.Node>[];
    final List<md.Node> inlineNodes = <md.Node>[];
    final List<md.Element> blocks = <md.Element>[];
    bool? checkbox;

    for (final md.Node child in children) {
      if (child is md.Element) {
        if (child.tag == 'ul' || child.tag == 'ol' || child.tag == 'pre' ||
            child.tag == 'blockquote' || child.tag == 'table') {
          blocks.add(child);
          continue;
        }
        if (child.tag == 'input') {
          checkbox = _isChecked(child);
          continue;
        }
        if (child.tag == 'p') {
          for (final md.Node inner in child.children ?? const <md.Node>[]) {
            if (inner is md.Element && inner.tag == 'input') {
              checkbox = _isChecked(inner);
              continue;
            }
            if (inner is md.Element &&
                (inner.tag == 'ul' || inner.tag == 'ol')) {
              blocks.add(inner);
              continue;
            }
            inlineNodes.add(inner);
          }
          continue;
        }
      }
      inlineNodes.add(child);
    }

    return _ListItem(
      inline: _inline(inlineNodes, _body),
      blocks: blocks,
      checkbox: checkbox,
    );
  }

  static bool _isChecked(md.Element input) {
    final String? checked = input.attributes['checked'];
    return checked != null && checked.toLowerCase() != 'false';
  }

  /// Printable width of the sheet (A4/Letter minus the page margins set on the
  /// [pw.MultiPage]) and the matching usable height, used to fit tables.
  static const double _contentWidth = 483.0;
  static const double _contentHeight = 700.0;

  /// Renders a GFM table so that it (a) never splits across two pages and
  /// (b) never overflows the printable width.
  ///
  /// Column widths are estimated from cell content, then — while the table is
  /// too wide — font size and cell padding step down; if it still doesn't fit,
  /// the finished table is uniformly scaled down. A table taller than one page
  /// is scaled to the page height too, so it always occupies a single page.
  pw.Widget _table(md.Element node) {
    final List<md.Element> rows = <md.Element>[];
    for (final md.Node section in node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      if (section.tag == 'thead' || section.tag == 'tbody') {
        rows.addAll(
          (section.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((md.Element e) => e.tag == 'tr'),
        );
      } else if (section.tag == 'tr') {
        rows.add(section);
      }
    }
    if (rows.isEmpty) return pw.SizedBox();

    final List<List<md.Element?>> grid = <List<md.Element?>>[];
    int columns = 0;
    for (final md.Element row in rows) {
      final List<md.Element> cells =
          (row.children ?? const <md.Node>[]).whereType<md.Element>().toList();
      if (cells.length > columns) columns = cells.length;
      grid.add(cells);
    }
    if (columns == 0) return pw.SizedBox();
    for (final List<md.Element?> row in grid) {
      while (row.length < columns) {
        row.add(null);
      }
    }

    // Longest single word and full text length per column drive the natural
    // and minimum widths. Character widths are estimated from the font size
    // (the embedded fonts average ~0.52em for mixed-case text).
    final List<int> longest = List<int>.filled(columns, 1);
    final List<int> longestWord = List<int>.filled(columns, 1);
    for (final List<md.Element?> row in grid) {
      for (int c = 0; c < columns; c++) {
        final String text = (row[c]?.textContent ?? '').trim();
        if (text.length > longest[c]) longest[c] = text.length;
        for (final String word in text.split(RegExp(r'\s+'))) {
          if (word.length > longestWord[c]) longestWord[c] = word.length;
        }
      }
    }

    double fontSize = _bodySize;
    double padH = 8;
    double padV = 6;
    List<double> widths = const <double>[];
    double total = 0;

    // Step 1: shrink type and padding until the content-sized columns fit.
    for (int attempt = 0; attempt < 8; attempt++) {
      final double em = fontSize * 0.52;
      widths = <double>[
        for (int c = 0; c < columns; c++)
          (longest[c] * em + padH * 2).clamp(
            (longestWord[c] * em + padH * 2).clamp(28.0, 150.0),
            190.0,
          ),
      ];
      total = widths.fold<double>(0, (double a, double b) => a + b);
      if (total <= _contentWidth) break;
      fontSize = fontSize * 0.9;
      padH = padH * 0.85;
      padV = padV * 0.9;
      if (fontSize < 6.5) break;
    }

    // Step 2: distribute (or, as a last resort, proportionally squeeze) the
    // columns so the table exactly matches the printable width.
    final double fitFactor = total > 0 ? _contentWidth / total : 1;
    widths = <double>[for (final double w in widths) w * fitFactor];

    final pw.Widget table = pw.Table(
      border: pw.TableBorder.all(color: _PdfPalette.hairline, width: 0.6),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      columnWidths: <int, pw.TableColumnWidth>{
        for (int c = 0; c < columns; c++) c: pw.FixedColumnWidth(widths[c]),
      },
      children: <pw.TableRow>[
        for (int r = 0; r < grid.length; r++)
          pw.TableRow(
            decoration: _isHeaderRow(rows[r])
                ? const pw.BoxDecoration(color: _PdfPalette.tableHeader)
                : null,
            children: <pw.Widget>[
              for (int c = 0; c < columns; c++)
                pw.Padding(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: padH,
                    vertical: padV,
                  ),
                  child: pw.RichText(
                    textAlign: _cellAlign(grid[r][c]),
                    text: pw.TextSpan(
                      children: _inline(
                        grid[r][c]?.children,
                        (grid[r][c]?.tag == 'th'
                                ? _body.copyWith(
                                    font: fonts.bold,
                                    fontWeight: pw.FontWeight.bold,
                                  )
                                : _body)
                            .copyWith(fontSize: fontSize),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );

    // A rough height estimate (wrapped lines per row) decides whether the
    // table also needs scaling down to fit a single page's height.
    double estimatedHeight = 0;
    for (int r = 0; r < grid.length; r++) {
      int lines = 1;
      for (int c = 0; c < columns; c++) {
        final String text = (grid[r][c]?.textContent ?? '').trim();
        final double usable = widths[c] - padH * 2;
        final int perLine = (usable / (fontSize * 0.52)).floor().clamp(1, 500);
        final int rowLines = (text.length / perLine).ceil().clamp(1, 100);
        if (rowLines > lines) lines = rowLines;
      }
      estimatedHeight += lines * fontSize * 1.4 + padV * 2 + 0.6;
    }

    final double heightScale = estimatedHeight > _contentHeight
        ? _contentHeight / estimatedHeight
        : 1;

    pw.Widget fitted = table;
    if (heightScale < 1) {
      fitted = pw.Transform.scale(
        scale: heightScale,
        alignment: pw.Alignment.topLeft,
        child: pw.SizedBox(width: _contentWidth, child: table),
      );
    }

    // A plain `Container` is not a `SpanningWidget`, so `MultiPage` places the
    // table as one indivisible unit: if it doesn't fit in the space left on
    // this page, the whole table moves onto the next one.
    return pw.Container(
      width: double.infinity,
      alignment: pw.Alignment.topLeft,
      child: fitted,
    );
  }


  static bool _isHeaderRow(md.Element row) => (row.children ?? const <md.Node>[])
      .whereType<md.Element>()
      .any((md.Element c) => c.tag == 'th');

  static pw.TextAlign _cellAlign(md.Element? cell) {
    if (cell == null) return pw.TextAlign.left;
    switch (cell.attributes['style']) {
      case 'text-align: center;':
        return pw.TextAlign.center;
      case 'text-align: right;':
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.left;
    }
  }

  List<pw.InlineSpan> _inline(List<md.Node>? nodes, pw.TextStyle style) {
    final List<pw.InlineSpan> spans = <pw.InlineSpan>[];
    if (nodes == null) return spans;

    for (final md.Node node in nodes) {
      if (node is md.Text) {
        final String text = _unescape(node.text);
        if (text.isEmpty) continue;
        spans.add(pw.TextSpan(text: text, style: style));
        continue;
      }
      if (node is! md.Element) continue;

      switch (node.tag) {
        case 'em':
          spans.addAll(
            _inline(
              node.children,
              style.copyWith(
                font: style.fontWeight == pw.FontWeight.bold
                    ? fonts.boldItalic
                    : fonts.italic,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          );
          break;
        case 'strong':
          spans.addAll(
            _inline(
              node.children,
              style.copyWith(
                font: style.fontStyle == pw.FontStyle.italic
                    ? fonts.boldItalic
                    : fonts.bold,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          );
          break;
        case 'del':
          spans.addAll(
            _inline(
              node.children,
              style.copyWith(
                decoration: pw.TextDecoration.lineThrough,
                color: _PdfPalette.muted,
              ),
            ),
          );
          break;
        case 'code':
        case 'math_inline':
          spans.add(
            pw.TextSpan(
              text: _unescape(node.textContent),
              style: style.copyWith(
                font: fonts.mono,
                fontSize: (style.fontSize ?? _bodySize) * 0.92,
                background: const pw.BoxDecoration(
                  color: _PdfPalette.codeBackground,
                ),
              ),
            ),
          );
          break;
        case 'mark':
          spans.add(
            pw.TextSpan(
              text: _unescape(node.textContent),
              style: style.copyWith(
                background: const pw.BoxDecoration(
                  color: _PdfPalette.highlight,
                ),
              ),
            ),
          );
          break;
        case 'a':
          final String? href = node.attributes['href'];
          final pw.TextStyle linkStyle = style.copyWith(
            color: _PdfPalette.link,
            decoration: pw.TextDecoration.underline,
          );
          if (href == null || href.isEmpty) {
            spans.addAll(_inline(node.children, linkStyle));
          } else {
            spans.add(
              pw.TextSpan(
                text: _unescape(node.textContent),
                style: linkStyle,
                annotation: pw.AnnotationUrl(href),
              ),
            );
          }
          break;
        case 'br':
          spans.add(pw.TextSpan(text: '\n', style: style));
          break;
        case 'input':
          // Task-list checkbox handled by the list renderer.
          break;
        case 'img':
          spans.add(
            pw.TextSpan(
              text: node.attributes['alt']?.isNotEmpty == true
                  ? '[${node.attributes['alt']}]'
                  : '[image]',
              style: style.copyWith(
                font: fonts.italic,
                fontStyle: pw.FontStyle.italic,
                color: _PdfPalette.muted,
              ),
            ),
          );
          break;
        default:
          spans.addAll(_inline(node.children, style));
      }
    }
    return spans;
  }

  /// The markdown package leaves a few HTML entities in text nodes; the PDF
  /// is plain text, so turn them back into the characters people typed.
  static String _unescape(String input) => input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  /// The last block inside a container shouldn't add trailing padding.
  static List<pw.Widget> _stripLastGap(List<pw.Widget> widgets) {
    if (widgets.isEmpty) return widgets;
    final pw.Widget last = widgets.removeLast();
    if (last is pw.Padding) {
      widgets.add(last.child ?? pw.SizedBox());
    } else {
      widgets.add(last);
    }
    return widgets;
  }
}

class _ListItem {
  const _ListItem({
    required this.inline,
    required this.blocks,
    required this.checkbox,
  });

  final List<pw.InlineSpan> inline;
  final List<md.Element> blocks;
  final bool? checkbox;
}
