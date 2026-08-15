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
import 'package:markdown/markdown.dart' as md;
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/chart_block.dart';
import 'package:quietnote/core/markdown_kit/flowchart/flowchart_view.dart';
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
    final String rawLang = cls.replaceFirst('language-', '').trim();
    final String source = code.textContent;
    if (source.trim().isEmpty) return null;

    if (rawLang == 'mermaid') {
      return _MermaidBlock(source: source.trim(), dark: dark);
    }
    if (rawLang == 'chart') {
      return ChartBlock(spec: source.trim());
    }
    return _CodeBlock(
      source: source.trimRight(),
      language: _canonicalLanguage(rawLang),
      displayLanguage: rawLang,
      dark: dark,
    );
  }
}

/// Maps the shorthand/alias people actually type after a fence (```html,
/// ```js, ```sh, ...) to the grammar name the `highlight` package registers
/// it under, so every common alias — not just the canonical name — lights
/// up correctly. This is what makes ```html fenced blocks highlight like
/// GitHub renders them (tags, attributes, embedded script/style) instead of
/// falling back to plain text.
String _canonicalLanguage(String lang) {
  const Map<String, String> aliases = <String, String>{
    'html': 'xml',
    'htm': 'xml',
    'xhtml': 'xml',
    'svg': 'xml',
    'vue': 'xml',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'js': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'py3': 'python',
    'rb': 'ruby',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'cs': 'csharp',
    'c++': 'cpp',
    'cc': 'cpp',
    'h': 'cpp',
    'hpp': 'cpp',
    'yml': 'yaml',
    'md': 'markdown',
    'ps1': 'powershell',
    'dockerfile': 'dockerfile',
    'plaintext': '',
    'text': '',
    'txt': '',
  };
  final String key = lang.toLowerCase();
  return aliases[key] ?? key;
}

/// Shared header chrome for every fenced block (code, mermaid): a themed
/// container with a rounded top strip holding a label chip + icon on the
/// left and up to a few icon actions on the right, a hairline divider, then
/// whatever [body] renders below it. Code blocks and flowchart blocks share
/// this exact frame so they read as one visual family that follows the
/// app's live theme (colors, radii) rather than fixed hex values.
class _FencedBlockChrome extends StatelessWidget {
  const _FencedBlockChrome({
    required this.icon,
    required this.label,
    required this.actions,
    required this.body,
    this.bodyPadding = EdgeInsets.zero,
  });

  final IconData icon;
  final String label;
  final List<Widget> actions;
  final Widget body;
  final EdgeInsets bodyPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    final radius = context.uiRadii.lg;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(context.uiRadii.pill),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: colors.foregroundMuted),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: colors.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ...actions,
              ],
            ),
          ),
          Container(height: 1, color: colors.border),
          Container(
            color: colors.surfaceMuted.withValues(alpha: 0.4),
            padding: bodyPadding,
            child: body,
          ),
        ],
      ),
    );
  }
}

/// A small icon-only action button matching the fenced-block header style
/// (quiet by default, themed hover/press state, compact hit target).
class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    return IconButton(
      icon: Icon(icon, size: 16),
      color: color ?? colors.foregroundMuted,
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

/// A syntax-highlighted, copyable fenced code block. Chrome (background,
/// border, label chip) is driven entirely by the live [UiTheme] — including
/// the person's chosen accent — rather than fixed colors, so it always
/// matches the rest of the app; only the token colors inside the code come
/// from a dedicated syntax theme, since those need their own fixed palette
/// to stay readable and distinguishable regardless of the accent color.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.source,
    required this.language,
    required this.displayLanguage,
    required this.dark,
  });

  final String source;
  final String language;
  final String displayLanguage;
  final bool dark;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.source));
    if (!mounted) return;
    setState(() => _copied = true);
    UiToast.show(context, title: 'Copied', intent: UiIntent.success);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    final String label = widget.displayLanguage.isEmpty
        ? 'code'
        : widget.displayLanguage.toLowerCase();
    return _FencedBlockChrome(
      icon: Icons.code_rounded,
      label: label,
      bodyPadding: EdgeInsets.zero,
      actions: [
        _ChromeIconButton(
          icon: _copied ? Icons.check_rounded : Icons.copy_outlined,
          tooltip: 'Copy code',
          color: _copied ? colors.bullish : null,
          onPressed: () => _copy(context),
        ),
      ],
      body: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _highlighted(context),
        ),
      ),
    );
  }

  Widget _highlighted(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
      color: context.uiColors.foreground,
    );
    if (widget.language.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SelectableText(widget.source, style: style),
      );
    }
    try {
      // The bundled syntax theme supplies token colors only; its own
      // background is stripped so the surrounding themed chrome (which
      // follows the app's live theme/accent) shows through instead of a
      // hardcoded editor-theme background that could clash with it.
      final Map<String, TextStyle> base =
          widget.dark ? atomOneDarkTheme : atomOneLightTheme;
      final Map<String, TextStyle> transparent = <String, TextStyle>{
        for (final entry in base.entries) entry.key: entry.value,
        'root': (base['root'] ?? const TextStyle()).copyWith(
          backgroundColor: Colors.transparent,
        ),
      };
      return HighlightView(
        widget.source,
        language: widget.language,
        theme: transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: style,
      );
    } catch (_) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SelectableText(widget.source, style: style),
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
    return _FencedBlockChrome(
      icon: Icons.account_tree_outlined,
      label: 'flowchart',
      bodyPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      actions: [
        _exporting
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _ChromeIconButton(
                icon: Icons.download_outlined,
                tooltip: 'Download as PNG',
                onPressed: () => _download(context),
              ),
        _ChromeIconButton(
          icon: Icons.fullscreen,
          tooltip: 'View fullscreen',
          onPressed: () => _openFullscreen(context),
        ),
      ],
      body: GestureDetector(
        onTap: () => _openFullscreen(context),
        // The capture boundary wraps the *full-width* box (not the
        // diagram's natural-size render), so a downloaded PNG matches
        // exactly what is on screen.
        child: RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            width: double.infinity,
            color: colors.surface,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 160),
                // Mermaid lays out at the diagram's own natural size, so a
                // narrow chart used to sit small and left-aligned.
                // `FittedBox` with `fitWidth` hands the diagram unbounded
                // constraints (natural size), then uniformly scales it to
                // span the card's width, preserving aspect ratio.
                child: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: FlowchartView(
                      source: widget.source,
                      palette: FlowchartPalette.themed(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
      // viewport. Without `UnconstrainedBox`, `FlowchartView`'s responsive
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
              child: FlowchartView(
                source: widget.source,
                palette: FlowchartPalette.themed(context),
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
