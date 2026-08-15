import 'dart:math' as math;

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
  Size? _viewportSize;
  bool _didAutoFit = false;
  // Mermaid resolves its true rendered size a frame or two after first
  // build (it parses/lays out the diagram asynchronously), so an auto-fit
  // that trusts the very first measurement fits to a placeholder-sized box
  // and then visibly snaps to the real size right after — reading as
  // "zooms in then zooms back out". Tracking the last measured size and
  // only committing once two consecutive frames agree means we fit exactly
  // once, against the diagram's real, settled size.
  Size? _lastMeasured;
  // Once the person starts pinching/panning, auto-fit must never touch the
  // transform again — even if a late layout pass fires after that point —
  // or it fights their input by silently resetting what they just did.
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    // Give the diagram a frame to lay out at its natural (now unconstrained)
    // size, then zoom out just enough that the whole thing is visible instead
    // of opening at 100% with the bottom of a tall diagram off-screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
  }

  void _fitToScreen() {
    if (_didAutoFit || _userInteracted || !mounted) return;
    final RenderBox? box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    final Size? viewport = _viewportSize;
    if (box == null || viewport == null || !box.hasSize) return;
    final Size content = box.size;
    if (content.width <= 0 || content.height <= 0) return;

    // Not settled yet (or this is the first reading) — remember it and
    // wait for the next frame's measurement to confirm it before acting.
    if (_lastMeasured == null || _lastMeasured != content) {
      _lastMeasured = content;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
      return;
    }

    final double fitScale = math.min(
      viewport.width / content.width,
      viewport.height / content.height,
    );
    final double scale = fitScale.clamp(0.4, 1.0);
    final double dx = (viewport.width - content.width * scale) / 2;
    final double dy = (viewport.height - content.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
    _didAutoFit = true;
  }

  void _handleInteractionStart(ScaleStartDetails _) {
    _userInteracted = true;
  }

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

  void _resetZoom() {
    // A deliberate tap on "Reset zoom" should actually refit — including
    // re-enabling auto-fit even after the person has already panned/pinched,
    // since that's exactly what they're now asking for.
    _didAutoFit = false;
    _userInteracted = false;
    _lastMeasured = null;
    _transform.value = Matrix4.identity();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Widget _buildViewer(Color bg) {
    return InteractiveViewer(
      // Without `constrained: false`, InteractiveViewer forces its child to
      // fit inside the viewport no matter what the child itself wants —
      // zooming still "works" but panning can never reveal anything past
      // the edge of that box, because the diagram was never actually laid
      // out larger than the screen in the first place. `constrained: false`
      // lets the child (here, sized to its natural content size via
      // UnconstrainedBox below) grow past the viewport so there's actually
      // something to pan to.
      constrained: false,
      minScale: 0.4,
      maxScale: 8,
      boundaryMargin: const EdgeInsets.all(120),
      transformationController: _transform,
      onInteractionStart: _handleInteractionStart,
      // `Center` hands its child *bounded* max constraints equal to the
      // viewport. Without `UnconstrainedBox`, `MermaidDiagram`'s responsive
      // sizing shrinks/clips itself to fit that box instead of laying out at
      // its natural content size — so a diagram taller than one screen never
      // renders what's past the fold, and panning has nothing extra to
      // reveal (this was the "stuck at half, can't scroll further" bug).
      // `UnconstrainedBox` ignores the incoming constraints so the diagram
      // lays out at full size, and `InteractiveViewer` can then pan/zoom
      // across the whole thing.
      child: Center(
        child: UnconstrainedBox(
          constrainedAxis: null,
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
    );
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
                  // Keep nudging _fitToScreen every build; it no-ops itself
                  // once it has committed a fit (or the person has taken
                  // over with a pinch/pan) — see _fitToScreen for the
                  // two-frame settle check that avoids fitting to a
                  // not-yet-final mermaid layout.
                  WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
                  return _buildViewer(bg);
                },
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
