import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/ai/cloud_ai_providers.dart';
import 'package:quietnote/features/ai/local_ai_engine.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// Local model management, cloud API configuration, and AI Capture defaults.
class SettingsAiScreen extends ConsumerStatefulWidget {
  const SettingsAiScreen({super.key});

  @override
  ConsumerState<SettingsAiScreen> createState() => _SettingsAiScreenState();
}

class _SettingsAiScreenState extends ConsumerState<SettingsAiScreen> {
  bool _testingConnection = false;

  Future<void> _importModel(BuildContext context, WidgetRef ref) async {
    final bool go = await UiDialog.confirm(
      context,
      title: 'Import a local model?',
      description:
          'Pick the Gemma .task or .bin file you downloaded. It is copied into '
          'the app and never leaves your device. This can take a minute.',
      confirmLabel: 'Choose file',
    );
    if (!go) return;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      final String? path = result?.files.single.path;
      if (path == null) return;

      if (context.mounted) {
        UiToast.show(
          context,
          title: 'Importing model…',
          message: 'Keep the app open while this finishes.',
          icon: Icons.downloading_outlined,
          duration: const Duration(seconds: 6),
        );
      }
      await ref.read(aiEngineProvider.notifier).importModel(path);
      final AiEngineState state = ref.read(aiEngineProvider);
      if (!context.mounted) return;
      if (state == AiEngineState.ready) {
        UiToast.show(
          context,
          title: 'Model ready',
          message: 'AI Capture now works fully offline.',
          intent: UiIntent.success,
          icon: Icons.check_circle_outline,
        );
      } else {
        UiToast.show(
          context,
          title: 'Import finished with problems',
          message: 'The model could not be loaded. Try another file.',
          intent: UiIntent.danger,
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (context.mounted) {
        UiToast.show(
          context,
          title: 'Import failed',
          message: '$e',
          intent: UiIntent.danger,
          icon: Icons.error_outline,
        );
      }
    }
  }

  Future<void> _showGuidelines(BuildContext context) async {
    await UiDialog.show<void>(
      context,
      child: Builder(
        builder: (BuildContext ctx) => UiDialog(
          title: 'Set up the offline AI',
          icon: Icons.help_outline,
          description: 'Four steps, done once.',
          content: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Step(
                number: 1,
                text: 'Open Kaggle and find the Gemma MediaPipe models.',
              ),
              _Step(number: 2, text: 'Accept the licence agreement.'),
              _Step(
                number: 3,
                text: 'Download the Gemma 2B IT file to your phone.',
              ),
              _Step(
                number: 4,
                text: 'Come back here and tap "Import local model".',
              ),
            ],
          ),
          actions: <Widget>[
            UiButton(
              label: 'Got it',
              expandOnMobile: false,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection(AppSettings settings) async {
    setState(() => _testingConnection = true);
    try {
      final CloudAiProviderPreset preset = cloudAiProviderById(
        settings.aiApiProviderId,
      );
      final String baseUrl = preset.id == 'custom'
          ? settings.aiApiBaseUrl
          : preset.baseUrl;
      final client = CloudAiClient(
        baseUrl: baseUrl,
        apiKey: settings.aiApiKey,
        model: settings.aiApiModel,
      );
      await client.chat(
        systemPrompt: 'Reply with the single word: ok',
        userMessage: 'ok',
        maxTokens: 8,
      );
      if (mounted) {
        UiToast.show(
          context,
          title: 'Connected',
          message: '${preset.label} answered successfully.',
          intent: UiIntent.success,
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (mounted) {
        UiToast.show(
          context,
          title: "Couldn't connect",
          message: '$e',
          intent: UiIntent.danger,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final AiEngineState state = ref.watch(aiEngineProvider);
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    final SettingsController controller = ref.read(settingsProvider.notifier);

    final bool ready = state == AiEngineState.ready;
    final bool importing = state == AiEngineState.importing;
    final CloudAiProviderPreset selectedPreset = cloudAiProviderById(
      settings.aiApiProviderId,
    );

    return SettingsSubPage(
      title: 'AI Capture',
      subtitle: 'A private assistant that runs on your phone.',
      children: <Widget>[
        UiCard(
          variant: UiCardVariant.elevated,
          child: Row(
            children: <Widget>[
              Container(
                padding: EdgeInsets.all(context.sp(theme.spacing.md)),
                decoration: BoxDecoration(
                  color: (ready ? theme.colors.bullish : theme.colors.warning)
                      .withValues(alpha: 0.14),
                  borderRadius: context.radius(theme.radii.lg),
                ),
                child: Icon(
                  ready ? Icons.verified_outlined : Icons.auto_awesome,
                  color: ready ? theme.colors.bullish : theme.colors.warning,
                  size: context.sz(theme.sizes.iconLg),
                ),
              ),
              SizedBox(width: context.sp(theme.spacing.md)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ready
                          ? 'Model installed'
                          : importing
                          ? 'Importing model…'
                          : state == AiEngineState.failed
                          ? 'Model failed to load'
                          : 'No model installed',
                      style: context.uiText.bodyStrong,
                    ),
                    SizedBox(height: context.sp(theme.spacing.xxs)),
                    Text(
                      ready
                          ? 'Configured and persisted on this device. Capture runs offline.'
                          : 'Not configured — capture still works with the built-in rules parser.',
                      style: context.uiText.caption.copyWith(
                        color: theme.colors.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'Provider',
          description:
              'Run AI Capture fully on-device, or use your own API key with '
              'a hosted provider instead. The key is stored only on this '
              'device and sent only to the provider you pick below.',
          children: <Widget>[
            SettingsTile(
              icon: Icons.smartphone_outlined,
              title: 'Use on-device model',
              showChevron: false,
              trailing: Switch(
                value: settings.aiProviderMode == 'local',
                onChanged: (bool useLocal) => controller.update(
                  (AppSettings s) => s.copyWith(
                    aiProviderMode: useLocal ? 'local' : 'api',
                  ),
                ),
              ),
            ),
            if (settings.aiProviderMode == 'api') ...[
              SettingsTile(
                icon: Icons.cloud_outlined,
                title: 'Provider',
                showChevron: false,
                trailing: SizedBox(
                  width: context.sz(190),
                  child: UiSelect<String>(
                    value: settings.aiApiProviderId,
                    options: <UiOption<String>>[
                      for (final CloudAiProviderPreset p in kCloudAiProviders)
                        UiOption<String>(value: p.id, label: p.label),
                    ],
                    onChanged: (String v) => controller.update(
                      (AppSettings s) => s.copyWith(aiApiProviderId: v),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.sp(theme.spacing.md),
                ),
                child: Text(
                  selectedPreset.description,
                  style: context.uiText.caption.copyWith(
                    color: theme.colors.foregroundMuted,
                  ),
                ),
              ),
              SizedBox(height: context.sp(theme.spacing.sm)),
              if (selectedPreset.id == 'custom')
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.sp(theme.spacing.md),
                  ),
                  child: UiInput(
                    hintText: 'Base URL, e.g. https://your-host/v1',
                    value: settings.aiApiBaseUrl,
                    onChanged: (String v) => controller.update(
                      (AppSettings s) => s.copyWith(aiApiBaseUrl: v),
                    ),
                  ),
                ),
              if (selectedPreset.id == 'custom')
                SizedBox(height: context.sp(theme.spacing.sm)),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.sp(theme.spacing.md),
                ),
                child: UiInput(
                  hintText: 'API key',
                  obscure: true,
                  value: settings.aiApiKey,
                  onChanged: (String v) => controller.update(
                    (AppSettings s) => s.copyWith(aiApiKey: v),
                  ),
                ),
              ),
              SizedBox(height: context.sp(theme.spacing.sm)),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.sp(theme.spacing.md),
                ),
                child: UiInput(
                  hintText: 'Model ID',
                  value: settings.aiApiModel,
                  onChanged: (String v) => controller.update(
                    (AppSettings s) => s.copyWith(aiApiModel: v),
                  ),
                ),
              ),
              if (selectedPreset.suggestedFreeModels.isNotEmpty) ...[
                SizedBox(height: context.sp(theme.spacing.sm)),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.sp(theme.spacing.md),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String m in selectedPreset.suggestedFreeModels)
                        UiBadge(
                          label: m,
                          size: UiSize.sm,
                          variant: UiBadgeVariant.soft,
                          intent: settings.aiApiModel == m
                              ? UiIntent.primary
                              : UiIntent.neutral,
                          onTap: () => controller.update(
                            (AppSettings s) => s.copyWith(aiApiModel: m),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: context.sp(theme.spacing.md)),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.sp(theme.spacing.md),
                ),
                child: UiButton(
                  label: _testingConnection ? 'Testing…' : 'Test connection',
                  leadingIcon: Icons.wifi_tethering,
                  onPressed: _testingConnection
                      ? null
                      : () => _testConnection(settings),
                ),
              ),
              SizedBox(height: context.sp(theme.spacing.sm)),
            ],
          ],
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'Model',
          children: <Widget>[
            SettingsTile(
              icon: Icons.download_outlined,
              title: 'Import local model',
              description: 'Select a downloaded Gemma file.',
              enabled: !importing,
              onTap: () => _importModel(context, ref),
            ),
            SettingsTile(
              icon: Icons.help_outline,
              title: 'Setup guidelines',
              description: 'Where to get the model and how to install it.',
              onTap: () => _showGuidelines(context),
            ),
          ],
        ),
        SettingsSection(
          title: 'Capture defaults',
          description: 'What quick capture should do by default.',
          children: <Widget>[
            SettingsTile(
              icon: Icons.category_outlined,
              title: 'Default destination',
              showChevron: false,
              trailing: SizedBox(
                width: context.sz(150),
                child: UiSelect<String>(
                  value: settings.captureDefaultTarget,
                  options: const <UiOption<String>>[
                    UiOption<String>(value: 'todo', label: 'To-do'),
                    UiOption<String>(value: 'note', label: 'Note'),
                    UiOption<String>(value: 'journal', label: 'Journal'),
                    UiOption<String>(value: 'event', label: 'Calendar'),
                    UiOption<String>(value: 'routine', label: 'Routine'),
                  ],
                  onChanged: (String v) => controller.update(
                    (AppSettings s) => s.copyWith(captureDefaultTarget: v),
                  ),
                ),
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.bolt_outlined,
              title: 'Save without review',
              description: 'Skip the review sheet when confidence is high.',
              value: settings.captureAutoSave,
              onChanged: (bool v) => controller.update(
                (AppSettings s) => s.copyWith(captureAutoSave: v),
              ),
            ),
          ],
        ),
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Padding(
      padding: EdgeInsets.only(bottom: context.sp(theme.spacing.sm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: context.sz(22),
            height: context.sz(22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colors.surfaceMuted,
              borderRadius: context.radius(theme.radii.pill),
            ),
            child: Text('$number', style: context.uiText.caption),
          ),
          SizedBox(width: context.sp(theme.spacing.sm)),
          Expanded(child: Text(text, style: context.uiText.body)),
        ],
      ),
    );
  }
}
