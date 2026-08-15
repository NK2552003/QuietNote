import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/markdown_kit.dart';
import 'package:quietnote/core/utils/export_progress.dart';
import 'package:quietnote/core/utils/markdown_pdf_export.dart';
import 'package:quietnote/core/utils/pdf_export_options.dart';
import 'package:quietnote/core/utils/tag_utils.dart';

class JournalPreviewScreen extends ConsumerStatefulWidget {
  const JournalPreviewScreen({super.key, required this.entryId});
  final String entryId;

  @override
  ConsumerState<JournalPreviewScreen> createState() => _JournalPreviewScreenState();
}

class _JournalPreviewScreenState extends ConsumerState<JournalPreviewScreen> {
  final MarkdownOutlineController _outline = MarkdownOutlineController();

  @override
  void dispose() {
    _outline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JournalData?>(
    future: ref.read(journalRepositoryProvider).getEntry(widget.entryId),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const UiPage(child: Center(child: CircularProgressIndicator()));
      }
      final entry = snapshot.data;
      if (entry == null) {
        return const UiPage(
          header: UiHeader(title: 'Journal'),
          child: UiEmptyState(
            title: 'Entry not found',
            message: 'It may have been deleted.',
            icon: Icons.menu_book_outlined,
          ),
        );
      }
      return UiPage(
        reserveDockSpace: false,
        floatingActionButton: MarkdownOutlineFab(controller: _outline),
        header: UiHeader(
          title: entry.title,
          subtitle:
              '${entry.mood ?? 'Neutral'} · ${DateFormat.yMMMd().add_jm().format(entry.createdAt)}',
          leading: UiIconButton(
            icon: Icons.arrow_back,
            variant: UiVariant.ghost,
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
          actions: [
            UiIconButton(
              icon: Icons.picture_as_pdf_outlined,
              variant: UiVariant.ghost,
              tooltip: 'Export as PDF',
              onPressed: () async {
                final options = await showPdfExportOptions(context);
                if (options == null || !context.mounted) return;
                final ok = await runWithProgressOverlay<bool>(
                  context,
                  task: (setStep) async {
                    setStep('Rendering diagrams');
                    return MarkdownPdfExporter.exportAndShare(
                      context: context,
                      markdown: entry.entry,
                      title: entry.title.isEmpty ? 'Journal entry' : entry.title,
                      subtitle:
                          DateFormat.yMMMd().add_jm().format(entry.createdAt),
                      imageResolver: (uri) => _imageBytes(ref, uri),
                      options: options,
                      onStep: setStep,
                    );
                  },
                );
                if (!context.mounted || ok == null) return;
                if (!ok) {
                  UiToast.show(
                    context,
                    title: 'Couldn\'t export PDF',
                    message: 'Please try again.',
                    intent: UiIntent.warning,
                  );
                }
              },

            ),
            UiButton(
              label: 'Edit',
              leadingIcon: Icons.edit_outlined,
              onPressed: () => context.push('/journal/edit/${widget.entryId}'),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (parseTagsCsv(entry.tags).isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in parseTagsCsv(entry.tags))
                    UiBadge(
                      label: tag,
                      size: UiSize.sm,
                      variant: UiBadgeVariant.soft,
                      intent: UiIntent.neutral,
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Container(
              // Matches the page's own background (not the "surface" card
              // color) so the preview blends straight into the screen
              // behind it instead of sitting in a visibly different-colored
              // box.
              color: context.uiColors.background,
              child: RichMarkdownPreview(
                data: entry.entry,
                imageResolver: (context, uri) => _image(ref, uri),
                outlineController: _outline,
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _image(WidgetRef ref, Uri uri) {
    if (uri.scheme != 'local-image') return Image.network(uri.toString());
    return FutureBuilder<Attachment?>(
      future:
          (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).attachments)
                ..where((a) => a.id.equals(uri.host)))
              .getSingleOrNull(),
      builder: (_, snapshot) => snapshot.hasData && snapshot.data != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(snapshot.data!.filePath)),
            )
          : const SizedBox(
              height: 96,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
    );
  }

  /// Loads a note image's raw bytes for the PDF exporter (which embeds the
  /// picture in the document instead of drawing a widget).
  Future<Uint8List?> _imageBytes(WidgetRef ref, Uri uri) async {
    if (uri.scheme != 'local-image' && uri.scheme != 'local-file') return null;
    final db = ref.read(databaseProvider);
    final attachment =
        await (db.select(db.attachments)..where((a) => a.id.equals(uri.host)))
            .getSingleOrNull();
    final String? path = attachment?.filePath;
    if (path == null) return null;
    final File file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

}
