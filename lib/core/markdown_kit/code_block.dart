import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// Side-effect import: registers every bundled `highlight` language (dart,
// python, js, java, kotlin, swift, sql, bash, json, yaml, and 150+ more) so
// any ```lang fenced block can be syntax-highlighted without maintaining a
// per-language registration list.
// ignore: unused_import
import 'package:highlight/languages/all.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/chart_block.dart';
import 'package:quietnote/core/utils/image_export.dart';

/// Registers with [MarkdownBody]/[Markdown] via the `builders: {'pre': ...}`
/// hook. Routes fenced code blocks to the right renderer by language tag:
/// ```mermaid``` → an interactive flowchart/diagram, ```chart``` → a native
/// chart, everything else → a syntax-highlighted code block with a copy
/// button.
class RichCodeBlockBuilder extends MarkdownElementBuilder {
  RichCodeBlockBuilder({required this.dark});

  final bool dark;

  // `pre` is a block-level tag. Without this override some flutter_markdown
  // versions never hand the element to a custom builder at all and silently
  // fall back to the default code-block renderer.
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final md.Element? code =
        element.children?.whereType<md.Element>().firstOrNull;
    if (code == null || code.tag != 'code') return null;

    final String cls = code.attributes['class'] ?? '';
    final String lang = cls.replaceFirst('language-', '').trim();
    final String source = code.textContent;
    if (source.trim().isEmpty) return null;

    if (lang == 'mermaid') {
      return _MermaidBlock(source: source.trim(), dark: dark);
    }
    if (lang == 'chart') {
      return ChartBlock(spec: source.trim());
    }
    return _CodeBlock(source: source.trimRight(), language: lang, dark: dark);
  }
}

/// A syntax-highlighted, copyable fenced code block.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.source, required this.language, required this.dark});

  final String source;
  final String language;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F5F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark ? const Color(0xFF33322F) : const Color(0xFFE4E1DB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: colors.foregroundSubtle,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  color: colors.foregroundMuted,
                  splashRadius: 16,
                  tooltip: 'Copy code',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: source));
                    if (context.mounted) {
                      UiToast.show(context, title: 'Copied', intent: UiIntent.success);
                    }
                  },
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 10),
              child: _highlighted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlighted(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.45,
    );
    if (language.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SelectableText(
          source,
          style: style.copyWith(color: context.uiColors.foreground),
        ),
      );
    }
    try {
      return HighlightView(
        source,
        language: language,
        theme: dark ? atomOneDarkTheme : atomOneLightTheme,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: style,
      );
    } catch (_) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SelectableText(
          source,
          style: style.copyWith(color: context.uiColors.foreground),
        ),
      );
    }
  }
}

/// A mermaid flowchart/diagram block with a header offering fullscreen
/// pan+zoom viewing and a PNG download/share.
class _MermaidBlock extends StatefulWidget {
  const _MermaidBlock({required this.source, required this.dark});

  final String source;
  final bool dark;

  @override
  State<_MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<_MermaidBlock> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _exporting = false;

  Future<void> _download(BuildContext context) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final bool ok = await PngExporter.exportAndShare(
      boundaryKey: _boundaryKey,
      filename: 'flowchart',
    );
    if (!context.mounted) return;
    setState(() => _exporting = false);
    if (!ok) {
      UiToast.show(
        context,
        title: "Couldn't export diagram",
        message: 'Please try again.',
        intent: UiIntent.warning,
      );
    }
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MermaidFullscreenView(source: widget.source, dark: widget.dark),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F5F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.dark ? const Color(0xFF33322F) : const Color(0xFFE4E1DB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 14, color: colors.foregroundSubtle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Flowchart',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: colors.foregroundSubtle,
                    ),
                  ),
                ),
                _exporting
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_outlined, size: 16),
                        color: colors.foregroundMuted,
                        splashRadius: 16,
                        tooltip: 'Download as PNG',
                        onPressed: () => _download(context),
                      ),
                IconButton(
                  icon: const Icon(Icons.fullscreen, size: 18),
                  color: colors.foregroundMuted,
                  splashRadius: 16,
                  tooltip: 'View fullscreen',
                  onPressed: () => _openFullscreen(context),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _openFullscreen(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  color: widget.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F5F3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 160),
                      child: MermaidDiagram(
                        code: widget.source,
                        style: widget.dark ? MermaidStyle.dark() : MermaidStyle.neutral(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen pan/zoom viewer for a mermaid diagram, with its own PNG
/// download action.
class _MermaidFullscreenView extends StatefulWidget {
  const _MermaidFullscreenView({required this.source, required this.dark});

  final String source;
  final bool dark;

  @override
  State<_MermaidFullscreenView> createState() => _MermaidFullscreenViewState();
}

class _MermaidFullscreenViewState extends State<_MermaidFullscreenView> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  bool _exporting = false;

  Future<void> _download() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final bool ok = await PngExporter.exportAndShare(
      boundaryKey: _boundaryKey,
      filename: 'flowchart',
    );
    if (!mounted) return;
    setState(() => _exporting = false);
    if (!ok) {
      UiToast.show(
        context,
        title: "Couldn't export diagram",
        message: 'Please try again.',
        intent: UiIntent.warning,
      );
    }
  }

  void _resetZoom() => _transform.value = Matrix4.identity();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = widget.dark ? const Color(0xFF121212) : const Color(0xFFFAF9F6);
    final Color fg = widget.dark ? Colors.white : Colors.black87;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: fg),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                  Expanded(
                    child: Text(
                      'Flowchart',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.center_focus_strong_outlined, color: fg),
                    onPressed: _resetZoom,
                    tooltip: 'Reset zoom',
                  ),
                  _exporting
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                          ),
                        )
                      : IconButton(
                          icon: Icon(Icons.download_outlined, color: fg),
                          onPressed: _download,
                          tooltip: 'Download as PNG',
                        ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.4,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(120),
                transformationController: _transform,
                child: Center(
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: Container(
                      color: bg,
                      padding: const EdgeInsets.all(24),
                      child: MermaidDiagram(
                        code: widget.source,
                        style: widget.dark ? MermaidStyle.dark() : MermaidStyle.neutral(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Text(
                'Pinch or scroll to zoom · drag to pan',
                style: TextStyle(color: fg.withValues(alpha: 0.55), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
