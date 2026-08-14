import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:markdown/markdown.dart' as md;

/// Registers with [MarkdownBody]/[Markdown] via the `builders: {'pre': ...}`
/// hook. Fenced code blocks tagged ```mermaid render as an actual diagram
/// (via `flutter_mermaid`); every other fenced/code block falls back to the
/// package's normal styled text rendering.
class MermaidCodeBuilder extends MarkdownElementBuilder {
  MermaidCodeBuilder({required this.dark});

  final bool dark;

  // `pre` is a block-level tag. Without this override some flutter_markdown
  // versions never hand the element to a custom builder at all and silently
  // fall back to the default code-block renderer, which is why ```mermaid
  // fences were showing up as plain text instead of a diagram.
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final md.Element? code = element.children?.whereType<md.Element>().firstOrNull;
    if (code == null || code.tag != 'code') return null;

    final String cls = code.attributes['class'] ?? '';
    if (!cls.contains('language-mermaid')) return null;

    final String source = code.textContent.trim();
    if (source.isEmpty) return null;

    return _MermaidBlock(source: source, dark: dark);
  }
}

/// Wraps the diagram in a fixed-minimum-height box. The note/journal
/// markdown body renders inside a scrolling column with unbounded height,
/// and [MermaidDiagram] needs a bounded/non-zero constraint to lay itself
/// out — without this the diagram could collapse to zero height and never
/// actually appear even though the builder ran correctly.
class _MermaidBlock extends StatelessWidget {
  const _MermaidBlock({required this.source, required this.dark});

  final String source;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F5F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark ? const Color(0xFF33322F) : const Color(0xFFE4E1DB),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 160),
          child: MermaidDiagram(
            code: source,
            style: dark ? MermaidStyle.dark() : MermaidStyle.neutral(),
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
