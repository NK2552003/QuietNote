import 'package:flutter/material.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// One heading found while rendering a [RichMarkdownPreview] — used to build
/// a tappable "index" of the document.
class MarkdownHeading {
  const MarkdownHeading({required this.level, required this.text, required this.key});

  /// 1 for `#`, 2 for `##`, … 6 for `######`.
  final int level;
  final String text;

  /// Key of the actual rendered heading widget, so it can be located and
  /// scrolled into view.
  final GlobalKey key;
}

/// Passed into [RichMarkdownPreview] to receive the document's heading
/// outline as it's built, and to jump the enclosing scroll view to any of
/// them. One controller per preview; dispose it with the screen that owns it.
///
/// ```dart
/// final _outline = MarkdownOutlineController();
/// ...
/// RichMarkdownPreview(data: note.content, outlineController: _outline)
/// ...
/// floatingActionButton: MarkdownOutlineFab(controller: _outline),
/// ```
class MarkdownOutlineController extends ChangeNotifier {
  List<MarkdownHeading> _headings = const <MarkdownHeading>[];
  final Map<String, GlobalKey> _keyCache = <String, GlobalKey>{};

  /// Headings found in the most recently built document, in source order.
  List<MarkdownHeading> get headings => _headings;

  GlobalKey keyFor(String cacheId) =>
      _keyCache.putIfAbsent(cacheId, () => GlobalKey(debugLabel: cacheId));

  /// Called by [RichMarkdownPreview] once its child tree has actually built
  /// (so every [MarkdownHeading.key] is attached to a live widget). Prunes
  /// keys for headings that no longer exist so they don't leak, then
  /// notifies listeners (e.g. [MarkdownOutlineFab]) on the next frame.
  void commit(List<MarkdownHeading> found, Set<String> liveCacheIds) {
    _headings = found;
    _keyCache.removeWhere((id, _) => !liveCacheIds.contains(id));
    if (!hasListeners) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  /// Scrolls the nearest enclosing [Scrollable] so [heading] is visible.
  Future<void> scrollTo(MarkdownHeading heading) async {
    final BuildContext? ctx = heading.key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
  }
}

/// Floating "jump to section" button for a [RichMarkdownPreview] screen.
/// Hidden automatically when the document has no headings. Tapping it opens
/// a bottom sheet listing every heading (indented by level); tapping one
/// scrolls the preview straight to it.
class MarkdownOutlineFab extends StatelessWidget {
  const MarkdownOutlineFab({super.key, required this.controller});

  final MarkdownOutlineController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.headings.isEmpty) return const SizedBox.shrink();
        return FloatingActionButton(
          heroTag: 'markdown-outline-fab',
          tooltip: 'Jump to section',
          onPressed: () => _openOutline(context),
          child: const Icon(Icons.format_list_bulleted),
        );
      },
    );
  }

  void _openOutline(BuildContext context) {
    final colors = context.uiColors;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      builder: (sheetContext) {
        final headings = controller.headings;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.6),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: headings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Text(
                      'Jump to section',
                      style: context.uiText.bodyStrong.copyWith(fontSize: 15),
                    ),
                  );
                }
                final heading = headings[index - 1];
                return InkWell(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    controller.scrollTo(heading);
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20 + ((heading.level - 1) * 16).toDouble(),
                      10,
                      20,
                      10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          heading.level <= 2 ? Icons.subject : Icons.short_text,
                          size: 16,
                          color: colors.foregroundMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            heading.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: heading.level <= 2
                                ? context.uiText.bodyStrong
                                : context.uiText.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
