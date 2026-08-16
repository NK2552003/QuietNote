import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

enum PdfPaperSize { a4, letter }

enum PdfDiagramQuality { standard, high }

class PdfExportOptions {
  const PdfExportOptions({
    this.paperSize = PdfPaperSize.a4,
    this.includeTitle = true,
    this.includeSubtitle = true,
    this.includePageNumbers = true,
    this.includeDiagrams = true,
    this.diagramQuality = PdfDiagramQuality.high,
  });

  final PdfPaperSize paperSize;
  final bool includeTitle;
  final bool includeSubtitle;
  final bool includePageNumbers;
  final bool includeDiagrams;
  final PdfDiagramQuality diagramQuality;

  PdfExportOptions copyWith({
    PdfPaperSize? paperSize,
    bool? includeTitle,
    bool? includeSubtitle,
    bool? includePageNumbers,
    bool? includeDiagrams,
    PdfDiagramQuality? diagramQuality,
  }) {
    return PdfExportOptions(
      paperSize: paperSize ?? this.paperSize,
      includeTitle: includeTitle ?? this.includeTitle,
      includeSubtitle: includeSubtitle ?? this.includeSubtitle,
      includePageNumbers: includePageNumbers ?? this.includePageNumbers,
      includeDiagrams: includeDiagrams ?? this.includeDiagrams,
      diagramQuality: diagramQuality ?? this.diagramQuality,
    );
  }
}

Future<PdfExportOptions?> showPdfExportOptions(BuildContext context) {
  return showModalBottomSheet<PdfExportOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.uiColors.surface,
    builder: (_) => const _PdfExportOptionsSheet(),
  );
}

class _PdfExportOptionsSheet extends StatefulWidget {
  const _PdfExportOptionsSheet();

  @override
  State<_PdfExportOptionsSheet> createState() => _PdfExportOptionsSheetState();
}

class _PdfExportOptionsSheetState extends State<_PdfExportOptionsSheet> {
  PdfExportOptions _options = const PdfExportOptions();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export PDF', style: context.uiText.heading),
            const SizedBox(height: 18),
            Text('Paper size', style: context.uiText.bodyStrong),
            const SizedBox(height: 8),
            SegmentedButton<PdfPaperSize>(
              segments: const [
                ButtonSegment(value: PdfPaperSize.a4, label: Text('A4')),
                ButtonSegment(value: PdfPaperSize.letter, label: Text('Letter')),
              ],
              selected: {_options.paperSize},
              onSelectionChanged: (value) => setState(
                () => _options = _options.copyWith(paperSize: value.first),
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Document title'),
              value: _options.includeTitle,
              onChanged: (value) => setState(
                () => _options = _options.copyWith(includeTitle: value),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date and details'),
              value: _options.includeSubtitle,
              onChanged: (value) => setState(
                () => _options = _options.copyWith(includeSubtitle: value),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Page numbers'),
              value: _options.includePageNumbers,
              onChanged: (value) => setState(
                () => _options = _options.copyWith(includePageNumbers: value),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Render flowcharts and charts'),
              subtitle: const Text('Otherwise their source is printed as code.'),
              value: _options.includeDiagrams,
              onChanged: (value) => setState(
                () => _options = _options.copyWith(includeDiagrams: value),
              ),
            ),
            if (_options.includeDiagrams) ...[
              const SizedBox(height: 4),
              Text('Diagram quality', style: context.uiText.bodyStrong),
              const SizedBox(height: 8),
              SegmentedButton<PdfDiagramQuality>(
                segments: const [
                  ButtonSegment(
                    value: PdfDiagramQuality.standard,
                    label: Text('Standard'),
                  ),
                  ButtonSegment(
                    value: PdfDiagramQuality.high,
                    label: Text('High'),
                  ),
                ],
                selected: {_options.diagramQuality},
                onSelectionChanged: (value) => setState(
                  () => _options = _options.copyWith(diagramQuality: value.first),
                ),
              ),
            ],
            const SizedBox(height: 22),
            UiButton(
              label: 'Create and share PDF',
              leadingIcon: Icons.picture_as_pdf_outlined,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_options),
            ),
          ],
        ),
      ),
    );
  }
}