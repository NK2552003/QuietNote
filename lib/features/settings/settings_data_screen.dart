import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/backup_service.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Export a backup, merge one back in, and see what's stored on device.
class SettingsDataScreen extends ConsumerStatefulWidget {
  const SettingsDataScreen({super.key});

  @override
  ConsumerState<SettingsDataScreen> createState() => _SettingsDataScreenState();
}

class _SettingsDataScreenState extends ConsumerState<SettingsDataScreen> {
  bool _busy = false;

  void _toast(String title, {String? message, UiIntent intent = UiIntent.neutral, IconData? icon}) {
    if (!mounted) return;
    UiToast.show(context, title: title, message: message, intent: intent, icon: icon);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final BackupService service = ref.read(backupServiceProvider);
      final File file = await service.databaseFile();
      if (!await file.exists()) {
        _toast('Nothing to export yet',
            message: 'Your database file has not been created.',
            intent: UiIntent.warning,
            icon: Icons.info_outline);
        return;
      }
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'application/x-sqlite3')],
        text: 'QuietNote backup',
      );
      await ref.read(settingsProvider.notifier).update(
            (AppSettings s) => s.copyWith(lastBackupAt: DateTime.now()),
          );
      _toast('Backup shared',
          message: 'Keep it somewhere safe, like your school drive.',
          intent: UiIntent.success,
          icon: Icons.check_circle_outline);
    } catch (e) {
      _toast('Export failed', message: '$e', intent: UiIntent.danger, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.any);
      final String? path = result?.files.single.path;
      if (path == null) return;

      final BackupService service = ref.read(backupServiceProvider);
      final BackupPreview preview = await service.inspect(path);
      if (!mounted) return;

      final bool go = await UiDialog.confirm(
        context,
        title: 'Merge this backup?',
        description:
            '${preview.fileName} · ${formatBytes(preview.sizeBytes)}\n'
            '${preview.totalRows} rows found.\n\n'
            'Nothing is deleted. Missing items are added and older items are '
            'refreshed with the newer copy.',
        confirmLabel: 'Merge',
      );
      if (!go) return;

      final MergeReport report = await service.merge(path);
      if (!mounted) return;
      await UiDialog.show<void>(
        context,
        child: Builder(
          builder: (BuildContext ctx) => UiDialog(
            title: 'Merge complete',
            icon: Icons.download_done_outlined,
            description:
                '${report.totalAdded} added · ${report.totalUpdated} updated · '
                '${report.totalSkipped} already up to date.',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final String table in report.changedTables)
                  Padding(
                    padding: EdgeInsets.only(bottom: ctx.sp(ctx.ui.spacing.xs)),
                    child: Text(
                      '${BackupService.tableLabels[table] ?? table}: '
                      '+${report.added[table] ?? 0} new, '
                      '${report.updated[table] ?? 0} updated',
                      style: ctx.uiText.body,
                    ),
                  ),
                if (report.changedTables.isEmpty)
                  Text('Everything was already in sync.', style: ctx.uiText.body),
                for (final String warning in report.warnings)
                  Padding(
                    padding: EdgeInsets.only(top: ctx.sp(ctx.ui.spacing.xs)),
                    child: Text(
                      warning,
                      style: ctx.uiText.caption
                          .copyWith(color: ctx.uiColors.foregroundMuted),
                    ),
                  ),
              ],
            ),
            actions: <Widget>[
              UiButton(
                label: 'Done',
                expandOnMobile: false,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      _toast('Import failed', message: '$e', intent: UiIntent.danger, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    final BackupService service = ref.watch(backupServiceProvider);

    return SettingsSubPage(
      title: 'Data & backup',
      subtitle: 'Everything stays on this device unless you share it.',
      children: <Widget>[
        UiCallout(
          title: settings.lastBackupAt == null
              ? 'No backup yet'
              : 'Last backup ${_relative(settings.lastBackupAt!)}',
          message:
              'Export before switching phones — there is no cloud copy of your notes.',
          intent: settings.lastBackupAt == null ? UiIntent.warning : UiIntent.success,
          icon: Icons.shield_outlined,
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'Backup',
          children: <Widget>[
            SettingsTile(
              icon: Icons.ios_share,
              title: 'Export backup',
              description: 'Share your database file.',
              enabled: !_busy,
              onTap: _export,
            ),
            SettingsTile(
              icon: Icons.merge_type,
              title: 'Import & merge backup',
              description: 'Adds what is missing. Never deletes anything.',
              enabled: !_busy,
              onTap: _import,
            ),
          ],
        ),
        SettingsSection(
          title: 'Stored on this device',
          children: <Widget>[
            FutureBuilder<Map<String, int>>(
              future: service.liveCounts(),
              builder: (BuildContext context,
                  AsyncSnapshot<Map<String, int>> snapshot) {
                if (!snapshot.hasData) {
                  return Padding(
                    padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
                    child: const UiSkeleton(height: 90),
                  );
                }
                final Map<String, int> counts = snapshot.data!;
                return Padding(
                  padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
                  child: Wrap(
                    spacing: context.sp(theme.spacing.sm),
                    runSpacing: context.sp(theme.spacing.sm),
                    children: <Widget>[
                      for (final MapEntry<String, int> entry in counts.entries)
                        UiBadge(
                          label:
                              '${BackupService.tableLabels[entry.key] ?? entry.key} · ${entry.value}',
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        if (_busy) ...<Widget>[
          const UiSkeleton(height: 6),
          SizedBox(height: context.sp(theme.spacing.md)),
        ],
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }

  String _relative(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }
}
