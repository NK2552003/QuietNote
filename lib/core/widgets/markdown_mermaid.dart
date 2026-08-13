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

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final md.Element? code = element.children?.whereType<md.Element>().firstOrNull;
    if (code == null || code.tag != 'code') return null;

    final String cls = code.attributes['class'] ?? '';
    if (!cls.contains('language-mermaid')) return null;

    final String source = code.textContent.trim();
    if (source.isEmpty) return null;

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
        child: MermaidDiagram(
          code: source,
          style: dark ? MermaidStyle.dark() : MermaidStyle.neutral(),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
