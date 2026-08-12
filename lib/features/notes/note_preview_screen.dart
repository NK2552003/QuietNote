import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

/// Read-only route: opening an existing note never puts the cursor in a
/// writable field. Editing is an explicit, deliberate action.
class NotePreviewScreen extends ConsumerWidget {
  const NotePreviewScreen({super.key, required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              UiButton(
                label: 'Edit',
                leadingIcon: Icons.edit_outlined,
                onPressed: () => context.push('/notes/edit/$noteId'),
              ),
            ],
          ),
          child: MarkdownBody(
            data: note.content.isEmpty
                ? '*Nothing written yet.*'
                : note.content,
            selectable: true,
            sizedImageBuilder: (config) => _localImage(ref, config.uri),
            styleSheet: MarkdownStyleSheet(
              p: context.uiText.body,
              h1: context.uiText.heading,
              h2: context.uiText.subheading,
            ),
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
}
