import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/markdown_kit/markdown_kit.dart';
import 'package:quietnote/core/utils/markdown_pdf_export.dart';
import 'package:quietnote/core/utils/pdf_export_options.dart';
import 'package:quietnote/core/utils/tag_utils.dart';

/// Read-only route: opening an existing note never puts the cursor in a
/// writable field. Editing is an explicit, deliberate action.
class NotePreviewScreen extends ConsumerStatefulWidget {
  const NotePreviewScreen({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<NotePreviewScreen> createState() => _NotePreviewScreenState();
}

class _NotePreviewScreenState extends ConsumerState<NotePreviewScreen> {
  final MarkdownOutlineController _outline = MarkdownOutlineController();

  @override
  void dispose() {
    _outline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final String noteId = widget.noteId;
    return FutureBuilder<Note?>(
      future: ref.read(noteRepositoryProvider).getNoteById(noteId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const UiPage(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final note = snapshot.data;
        if (note == null) {
          return const UiPage(
            header: UiHeader(title: 'Note'),
            child: UiEmptyState(
              title: 'Note not found',
              message: 'It may have been deleted.',
              icon: Icons.note_alt_outlined,
            ),
          );
        }
          return UiPage(
          reserveDockSpace: false,
          floatingActionButton: MarkdownOutlineFab(controller: _outline),
          header: UiHeader(
            title: note.title.isEmpty ? 'Untitled note' : note.title,
            subtitle: DateFormat.yMMMd().add_jm().format(note.createdAt),
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
                  final ok = await MarkdownPdfExporter.exportAndShare(
                    context: context,
                    markdown: note.content,
                    title: note.title.isEmpty ? 'Untitled note' : note.title,
                    subtitle: DateFormat.yMMMd().add_jm().format(note.createdAt),
                    imageResolver: (uri) => _imageBytes(ref, uri),
                    options: options,
                  );
                  if (!context.mounted) return;
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
                onPressed: () => context.push('/notes/edit/$noteId'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (parseTagsCsv(note.tags).isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in parseTagsCsv(note.tags))
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
                color: context.uiColors.surface,
                child: RichMarkdownPreview(
                  data: note.content,
                  imageResolver: (context, uri) => _localImage(ref, uri),
                  outlineController: _outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _localImage(WidgetRef ref, Uri uri) {
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
