import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

class JournalPreviewScreen extends ConsumerWidget {
  const JournalPreviewScreen({super.key, required this.entryId});
  final String entryId;

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<JournalData?>(
    future: ref.read(journalRepositoryProvider).getEntry(entryId),
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
            UiButton(
              label: 'Edit',
              leadingIcon: Icons.edit_outlined,
              onPressed: () => context.push('/journal/edit/$entryId'),
            ),
          ],
        ),
        child: MarkdownBody(
          data: entry.entry.isEmpty ? '*Nothing written yet.*' : entry.entry,
          selectable: true,
          sizedImageBuilder: (config) => _image(ref, config.uri),
          styleSheet: MarkdownStyleSheet(
            p: context.uiText.body,
            h1: context.uiText.heading,
            h2: context.uiText.subheading,
          ),
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
}
