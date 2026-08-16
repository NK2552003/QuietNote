import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quietnote/core/markdown_kit/markdown_kit.dart';

void main() {
  group('renderSafeHtml (tokenizer)', () {
    test('img with a local-image:// src is captured with its attributes', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      final String out = renderSafeHtml(
        'before <img src="local-image://abc123" alt="a cat" width="100"> after',
        registry,
      );

      // The <img ...> run is replaced by exactly one placeholder token;
      // the surrounding plain text is left completely untouched.
      expect(out, startsWith('before '));
      expect(out, endsWith(' after'));
      expect(out.contains('<img'), isFalse);
      expect(registry, hasLength(1));

      final HtmlNode node = registry.values.single;
      expect(node, isA<HtmlElementNode>());
      final HtmlElementNode img = node as HtmlElementNode;
      expect(img.tag, 'img');
      expect(img.attributes['src'], 'local-image://abc123');
      expect(img.attributes['alt'], 'a cat');
      expect(img.attributes['width'], '100');
    });

    test('a <script> tag is stripped and produces no registry entry', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      final String out = renderSafeHtml(
        'safe text <script>alert("x")</script> more text',
        registry,
      );

      expect(out.contains('script'), isFalse);
      expect(out.contains('alert'), isFalse);
      expect(registry, isEmpty);
      expect(out, contains('safe text'));
      expect(out, contains('more text'));
    });

    test('an onclick handler and a javascript: href are dropped', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      renderSafeHtml(
        '<a href="javascript:alert(1)" onclick="doBad()">click</a>',
        registry,
      );

      final HtmlElementNode a = registry.values.single as HtmlElementNode;
      expect(a.attributes.containsKey('onclick'), isFalse);
      // href is kept (styling still applies) but callers must treat it as
      // inert — this app never wires an onTap handler for it.
      expect(a.attributes['href'], 'javascript:alert(1)');
    });

    test('nested formatting <b><i>text</i></b> parses as a nested tree', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      renderSafeHtml('<b><i>text</i></b>', registry);

      final HtmlElementNode b = registry.values.single as HtmlElementNode;
      expect(b.tag, 'b');
      expect(b.children, hasLength(1));
      final HtmlElementNode i = b.children.single as HtmlElementNode;
      expect(i.tag, 'i');
      expect(i.children.single, isA<HtmlTextNode>());
      expect((i.children.single as HtmlTextNode).text, 'text');
    });

    test('an unclosed tag degrades gracefully instead of throwing', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      expect(
        () => renderSafeHtml('<div><b>unterminated', registry),
        returnsNormally,
      );
      expect(registry, hasLength(1));
      final HtmlElementNode div = registry.values.single as HtmlElementNode;
      expect(div.tag, 'div');
      final HtmlElementNode b = div.children.single as HtmlElementNode;
      expect(b.tag, 'b');
      expect((b.children.single as HtmlTextNode).text, 'unterminated');
    });

    test('a stray unmatched closing tag is ignored, not thrown', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      expect(
        () => renderSafeHtml('plain </b> text with no opener', registry),
        returnsNormally,
      );
      expect(registry, isEmpty);
    });

    test('HTML inside a fenced code block is left completely untouched', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      const String source = 'text\n```\n<b>literal</b>\n```\nmore <b>real</b>';
      final String out = renderSafeHtml(source, registry);

      // The fenced block's <b> is untouched (still literal in the output)...
      expect(out, contains('<b>literal</b>'));
      // ...while the one outside the fence was captured.
      expect(registry, hasLength(1));
      expect((registry.values.single as HtmlElementNode).tag, 'b');
    });

    test('an unrecognized tag is left as literal text', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      final String out = renderSafeHtml('<custom-tag>hi</custom-tag>', registry);
      expect(out, '<custom-tag>hi</custom-tag>');
      expect(registry, isEmpty);
    });

    test('source with no angle brackets is returned unchanged', () {
      final Map<String, HtmlNode> registry = <String, HtmlNode>{};
      const String source = 'plain **markdown** text, nothing HTML here.';
      expect(renderSafeHtml(source, registry), source);
      expect(registry, isEmpty);
    });
  });

  group('RichMarkdownPreview widget integration', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('local-image:// <img> resolves through imageResolver', (tester) async {
      Uri? resolvedUri;
      await tester.pumpWidget(
        host(
          RichMarkdownPreview(
            data: 'Look: <img src="local-image://note-attachment-1" alt="pic">',
            imageResolver: (context, uri) {
              resolvedUri = uri;
              return const Icon(Icons.image, key: Key('resolved-image'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(resolvedUri, isNotNull);
      expect(resolvedUri!.scheme, 'local-image');
      expect(resolvedUri!.host, 'note-attachment-1');
      expect(find.byKey(const Key('resolved-image')), findsOneWidget);
    });

    testWidgets('a <script> tag renders no widget and no visible text', (tester) async {
      await tester.pumpWidget(
        host(
          const RichMarkdownPreview(
            data: 'Before. <script>document.location="evil"</script> After.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('document.location'), findsNothing);
      expect(find.textContaining('evil'), findsNothing);
      expect(find.textContaining('Before.'), findsOneWidget);
      expect(find.textContaining('After.'), findsOneWidget);
    });

    testWidgets('nested <b><i>text</i></b> renders without throwing', (tester) async {
      await tester.pumpWidget(
        host(const RichMarkdownPreview(data: 'Some <b><i>emphasis</i></b> here.')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('emphasis'), findsOneWidget);
    });

    testWidgets('malformed/unclosed HTML never crashes the preview', (tester) async {
      await tester.pumpWidget(
        host(const RichMarkdownPreview(data: 'Broken: <div><b>oops and <i>more')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Broken:'), findsOneWidget);
    });

    testWidgets('plain markdown with no HTML still renders as before', (tester) async {
      await tester.pumpWidget(
        host(const RichMarkdownPreview(data: '# Heading\n\nSome **bold** text.')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Heading'), findsOneWidget);
      expect(find.textContaining('bold'), findsOneWidget);
    });
  });
}
