import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/utils/markdown_pdf_export.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:quietnote/core/widgets/markdown_mermaid.dart';

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
      final GlobalKey previewBoundaryKey = GlobalKey();
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
            UiIconButton(
              icon: Icons.picture_as_pdf_outlined,
              variant: UiVariant.ghost,
              tooltip: 'Export as PDF',
              onPressed: () async {
                final ok = await MarkdownPdfExporter.exportAndShare(
                  boundaryKey: previewBoundaryKey,
                  title: entry.title.isEmpty ? 'Journal entry' : entry.title,
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
              onPressed: () => context.push('/journal/edit/$entryId'),
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
            RepaintBoundary(
              key: previewBoundaryKey,
              child: Container(
                color: context.uiColors.surface,
                child: MarkdownBody(
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  data: entry.entry.isEmpty ? '*Nothing written yet.*' : entry.entry,
                  selectable: true,
                  builders: <String, MarkdownElementBuilder>{
                    'pre': MermaidCodeBuilder(
                      dark: context.ui.brightness == Brightness.dark,
                    ),
                  },
                  sizedImageBuilder: (config) => _image(ref, config.uri),
                  styleSheet: MarkdownStyleSheet(
                    p: context.uiText.body,
                    h1: context.uiText.heading.copyWith(fontSize: 26),
                    h2: context.uiText.subheading.copyWith(fontSize: 22),
                    h3: context.uiText.subheading,
                    blockquote: context.uiText.body.copyWith(
                      color: context.uiColors.foregroundMuted,
                      fontStyle: FontStyle.italic,
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: context.uiColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(color: context.uiColors.border, width: 3),
                      ),
                    ),
                    blockquotePadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    code: context.uiText.numeric,
                    codeblockDecoration: BoxDecoration(
                      color: context.uiColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    horizontalRuleDecoration: BoxDecoration(
                      border: Border(top: BorderSide(color: context.uiColors.border)),
                    ),
                    tableBorder: TableBorder.all(color: context.uiColors.border),
                    a: context.uiText.body.copyWith(
                      color: context.uiColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
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
}
