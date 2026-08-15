import 'dart:async';

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
///
/// Two independent ways to get AI, either of which is enough on its own:
///  * an on-device Gemma model (fully offline, private), and
///  * any OpenAI-compatible provider using the person's own API key.
class SettingsAiScreen extends ConsumerStatefulWidget {
  const SettingsAiScreen({super.key});

  @override
  ConsumerState<SettingsAiScreen> createState() => _SettingsAiScreenState();
}

class _SettingsAiScreenState extends ConsumerState<SettingsAiScreen> {
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  Timer? _debounce;
  bool _testingConnection = false;
  bool _loadingModels = false;
  bool _revealKey = false;
  bool _syncedFromSettings = false;
  List<String> _fetchedModels = const <String>[];

  @override
  void dispose() {
    _debounce?.cancel();
    _baseUrlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  /// Fills the controllers once, the first time persisted settings arrive.
  void _syncControllers(AppSettings settings) {
    if (_syncedFromSettings) return;
    _syncedFromSettings = true;
    _baseUrlCtrl.text = settings.aiApiBaseUrl;
    _keyCtrl.text = settings.aiApiKey;
    _modelCtrl.text = settings.aiApiModel;
  }

  /// Writes to the database a moment after typing stops, so every keystroke
  /// doesn't cause a write (and the field never loses focus mid-edit).
  void _debouncedUpdate(AppSettings Function(AppSettings) transform) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      ref.read(settingsProvider.notifier).update(transform);
    });
  }

  void _updateNow(AppSettings Function(AppSettings) transform) {
    _debounce?.cancel();
    ref.read(settingsProvider.notifier).update(transform);
  }

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? const AppSettings();

  /// The settings object as currently typed, so Test/Fetch act on what is on
  /// screen even if the debounce hasn't fired yet.
  AppSettings get _pendingSettings => _settings.copyWith(
        aiApiBaseUrl: _baseUrlCtrl.text.trim(),
        aiApiKey: _keyCtrl.text.trim(),
        aiApiModel: _modelCtrl.text.trim(),
      );

  // ------------------------------------------------------------ local model

  Future<void> _importModel() async {
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
      final bool ok =
          await ref.read(aiEngineProvider.notifier).importModel(path);
      _reportLocalResult(ok, 'Model imported');
    } catch (e) {
      _toastError('Import failed', e);
    }
  }

  Future<void> _downloadModel() async {
    final _DownloadRequest? request = await UiDialog.show<_DownloadRequest>(
      context,
      child: const _DownloadModelDialog(),
    );
    if (request == null) return;
    final bool ok = await ref
        .read(aiEngineProvider.notifier)
        .downloadModel(request.url, accessToken: request.token);
    _reportLocalResult(ok, 'Model downloaded');
  }

  Future<void> _loadBundled() async {
    final bool ok = await ref
        .read(aiEngineProvider.notifier)
        .installBundledModel('assets/models/gemma-3n-E2B-it-int4.task');
    _reportLocalResult(ok, 'Bundled model loaded');
  }

  Future<void> _removeModel() async {
    final bool go = await UiDialog.confirm(
      context,
      title: 'Remove the on-device model?',
      description:
          'The model file is deleted from this device. Capture keeps working '
          'with the built-in parser, and you can import it again later.',
      confirmLabel: 'Remove',
      confirmVariant: UiVariant.destructive,
    );
    if (!go) return;
    await ref.read(aiEngineProvider.notifier).deleteLocalModel();
    if (!mounted) return;
    UiToast.show(
      context,
      title: 'Model removed',
      message: 'On-device AI is off.',
      icon: Icons.delete_outline,
    );
  }

  void _reportLocalResult(bool ok, String successTitle) {
    if (!mounted) return;
    final AiEngineDetail detail = ref.read(aiEngineDetailProvider);
    if (ok) {
      UiToast.show(
        context,
        title: successTitle,
        message: 'AI Capture now works fully offline.',
        intent: UiIntent.success,
        icon: Icons.check_circle_outline,
      );
    } else {
      UiToast.show(
        context,
        title: 'That did not work',
        message: detail.error ?? 'The model could not be loaded.',
        intent: UiIntent.danger,
        icon: Icons.error_outline,
        duration: const Duration(seconds: 8),
      );
    }
  }

  // -------------------------------------------------------------------- api

  Future<void> _testConnection() async {
    setState(() => _testingConnection = true);
    final AppSettings pending = _pendingSettings;
    _updateNow((AppSettings s) => s.copyWith(
          aiApiBaseUrl: pending.aiApiBaseUrl,
          aiApiKey: pending.aiApiKey,
          aiApiModel: pending.aiApiModel,
        ));
    try {
      await ref.read(aiEngineProvider.notifier).testApiConnection(pending);
      if (mounted) {
        UiToast.show(
          context,
          title: 'Connected',
          message:
              '${cloudAiProviderById(pending.aiApiProviderId).label} answered '
              'successfully. AI is ready to use.',
          intent: UiIntent.success,
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      _toastError("Couldn't connect", e);
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _fetchModels() async {
    setState(() => _loadingModels = true);
    try {
      final List<String> models = await ref
          .read(aiEngineProvider.notifier)
          .listApiModels(_pendingSettings);
      if (!mounted) return;
      setState(() => _fetchedModels = models);
      if (models.isEmpty) {
        UiToast.show(
          context,
          title: 'No models returned',
          message: 'Type the model ID manually instead.',
          intent: UiIntent.warning,
        );
        return;
      }
      final String? picked = await UiDialog.show<String>(
        context,
        child: _ModelPickerDialog(models: models),
      );
      if (picked != null) {
        _modelCtrl.text = picked;
        _updateNow((AppSettings s) => s.copyWith(aiApiModel: picked));
      }
    } catch (e) {
      _toastError("Couldn't list models", e);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _toastError(String title, Object error) {
    if (!mounted) return;
    UiToast.show(
      context,
      title: title,
      message: '$error',
      intent: UiIntent.danger,
      icon: Icons.error_outline,
      duration: const Duration(seconds: 8),
    );
  }

  Future<void> _showGuidelines() async {
    await UiDialog.show<void>(
      context,
      child: Builder(
        builder: (BuildContext ctx) => UiDialog(
          title: 'Two ways to switch AI on',
          icon: Icons.help_outline,
          description: 'Either one is enough — pick what suits you.',
          content: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Step(
                number: 1,
                text: 'Fully offline: download a Gemma .task model (Hugging '
                    'Face "litert-community" or Kaggle MediaPipe pages), accept '
                    'the licence, then use "Import local model" or paste the '
                    'direct link into "Download model".',
              ),
              _Step(
                number: 2,
                text: 'Or use an API key: pick a provider above, paste the key '
                    'from its console, tap "Fetch models", choose one and hit '
                    '"Test connection".',
              ),
              _Step(
                number: 3,
                text: 'Set the mode to Automatic and QuietNote uses the '
                    'on-device model when it is installed, and your API key '
                    'otherwise.',
              ),
              _Step(
                number: 4,
                text: 'Capture always works even with no AI at all — the '
                    'built-in parser handles dates, priorities and moods.',
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

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final AiEngineState state = ref.watch(aiEngineProvider);
    final AiEngineDetail detail = ref.watch(aiEngineDetailProvider);
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    _syncControllers(settings);

    final bool busy = detail.isBusy || state == AiEngineState.importing;
    final CloudAiProviderPreset preset =
        cloudAiProviderById(settings.aiApiProviderId);
    final String mode = <String>['auto', 'local', 'api']
            .contains(settings.aiProviderMode)
        ? settings.aiProviderMode
        : 'auto';
    final bool showApi = mode != 'local';
    final bool ready = detail.localReady || detail.apiReady;

    return SettingsSubPage(
      title: 'AI Capture',
      subtitle: 'Private on-device AI, or your own API key.',
      children: <Widget>[
        _StatusCard(state: state, detail: detail, ready: ready),
        if (detail.error != null) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.md)),
          UiCallout(
            intent: UiIntent.warning,
            icon: Icons.info_outline,
            title: 'Last AI problem',
            message: detail.error!,
          ),
        ],
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'How AI runs',
          description:
              'Automatic prefers the on-device model and falls back to your '
              'API key. Keys are stored only on this device and sent only to '
              'the provider you pick.',
          children: <Widget>[
            SettingsTile(
              icon: Icons.tune_outlined,
              title: 'Mode',
              showChevron: false,
              trailing: SizedBox(
                width: context.sz(180),
                child: UiSelect<String>(
                  value: mode,
                  options: const <UiOption<String>>[
                    UiOption<String>(value: 'auto', label: 'Automatic'),
                    UiOption<String>(value: 'local', label: 'On-device only'),
                    UiOption<String>(value: 'api', label: 'API key'),
                  ],
                  onChanged: (String v) =>
                      _updateNow((AppSettings s) => s.copyWith(aiProviderMode: v)),
                ),
              ),
            ),
            SettingsTile(
              icon: Icons.help_outline,
              title: 'Setup guide',
              description: 'Offline model or API key, step by step.',
              onTap: _showGuidelines,
            ),
          ],
        ),
        if (showApi) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.xl)),
          SettingsSection(
            title: 'API provider',
            description: preset.description,
            children: <Widget>[
              SettingsTile(
                icon: Icons.cloud_outlined,
                title: 'Provider',
                showChevron: false,
                trailing: SizedBox(
                  width: context.sz(190),
                  child: UiSelect<String>(
                    value: preset.id,
                    options: <UiOption<String>>[
                      for (final CloudAiProviderPreset p in kCloudAiProviders)
                        UiOption<String>(value: p.id, label: p.label),
                    ],
                    onChanged: (String v) {
                      final CloudAiProviderPreset next = cloudAiProviderById(v);
                      setState(() => _fetchedModels = const <String>[]);
                      // Pre-fill a sensible model so the field is never empty.
                      final String suggested =
                          next.suggestedFreeModels.isNotEmpty
                              ? next.suggestedFreeModels.first
                              : _modelCtrl.text.trim();
                      _modelCtrl.text = suggested;
                      _updateNow(
                        (AppSettings s) => s.copyWith(
                          aiApiProviderId: v,
                          aiApiModel: suggested,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (preset.isCustom)
                _FieldRow(
                  child: UiInput(
                    controller: _baseUrlCtrl,
                    hintText: preset.id == 'ollama'
                        ? 'http://192.168.1.20:11434/v1'
                        : 'Base URL, e.g. https://your-host/v1',
                    keyboardType: TextInputType.url,
                    onChanged: (String v) => _debouncedUpdate(
                      (AppSettings s) => s.copyWith(aiApiBaseUrl: v.trim()),
                    ),
                  ),
                ),
              _FieldRow(
                child: UiInput(
                  controller: _keyCtrl,
                  hintText: preset.requiresKey
                      ? 'API key'
                      : 'API key (not needed for this provider)',
                  obscure: !_revealKey,
                  trailingIcon:
                      _revealKey ? Icons.visibility_off : Icons.visibility,
                  onTrailingTap: () =>
                      setState(() => _revealKey = !_revealKey),
                  onChanged: (String v) => _debouncedUpdate(
                    (AppSettings s) => s.copyWith(aiApiKey: v.trim()),
                  ),
                ),
              ),
              _FieldRow(
                child: UiInput(
                  controller: _modelCtrl,
                  hintText: 'Model ID',
                  onChanged: (String v) => _debouncedUpdate(
                    (AppSettings s) => s.copyWith(aiApiModel: v.trim()),
                  ),
                ),
              ),
              if (preset.suggestedFreeModels.isNotEmpty)
                _FieldRow(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String m in preset.suggestedFreeModels)
                        UiBadge(
                          label: m,
                          size: UiSize.sm,
                          variant: UiBadgeVariant.soft,
                          intent: _modelCtrl.text.trim() == m
                              ? UiIntent.primary
                              : UiIntent.neutral,
                          onTap: () {
                            _modelCtrl.text = m;
                            setState(() {});
                            _updateNow(
                              (AppSettings s) => s.copyWith(aiApiModel: m),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              _FieldRow(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: UiButton(
                        label: _testingConnection ? 'Testing…' : 'Test connection',
                        leadingIcon: Icons.wifi_tethering,
                        loading: _testingConnection,
                        onPressed: _testingConnection ? null : _testConnection,
                      ),
                    ),
                    SizedBox(width: context.sp(theme.spacing.sm)),
                    Expanded(
                      child: UiButton(
                        label: 'Fetch models',
                        variant: UiVariant.secondary,
                        leadingIcon: Icons.list_alt_outlined,
                        loading: _loadingModels,
                        onPressed: _loadingModels ? null : _fetchModels,
                      ),
                    ),
                  ],
                ),
              ),
              if (_fetchedModels.isNotEmpty)
                _FieldRow(
                  child: Text(
                    '${_fetchedModels.length} models available from this key.',
                    style: context.uiText.caption.copyWith(
                      color: theme.colors.foregroundMuted,
                    ),
                  ),
                ),
              if (preset.keyHelpUrl.isNotEmpty)
                _FieldRow(
                  child: Text(
                    'Get a key at ${preset.keyHelpUrl}',
                    style: context.uiText.caption.copyWith(
                      color: theme.colors.foregroundMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
        SizedBox(height: context.sp(theme.spacing.xl)),
        SettingsSection(
          title: 'On-device model',
          description:
              'Runs offline with nothing sent anywhere. Needs a Gemma '
              '.task/.bin file (roughly 500 MB – 3 GB).',
          children: <Widget>[
            if (detail.isBusy)
              _FieldRow(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(detail.busyLabel!, style: context.uiText.bodyStrong),
                    SizedBox(height: context.sp(theme.spacing.xs)),
                    LinearProgressIndicator(value: detail.progress),
                    if (detail.progress != null) ...<Widget>[
                      SizedBox(height: context.sp(theme.spacing.xs)),
                      Text(
                        '${(detail.progress! * 100).round()}%',
                        style: context.uiText.caption,
                      ),
                    ],
                  ],
                ),
              ),
            SettingsTile(
              icon: Icons.folder_open_outlined,
              title: 'Import local model',
              description: 'Pick a file already on this device.',
              enabled: !busy,
              onTap: busy ? null : _importModel,
            ),
            SettingsTile(
              icon: Icons.cloud_download_outlined,
              title: 'Download model',
              description: 'Paste a direct link and download it here.',
              enabled: !busy,
              onTap: busy ? null : _downloadModel,
            ),
            SettingsTile(
              icon: Icons.inventory_2_outlined,
              title: 'Use bundled model',
              description: 'Only if a model was shipped inside this build.',
              enabled: !busy,
              onTap: busy ? null : _loadBundled,
            ),
            if (state == AiEngineState.failed && !detail.localReady)
              SettingsTile(
                icon: Icons.refresh,
                title: 'Retry loading',
                description: 'Try to start the on-device runtime again.',
                enabled: !busy,
                onTap: busy
                    ? null
                    : () => ref.read(aiEngineProvider.notifier).retryLocal(),
              ),
            if (detail.localReady)
              SettingsTile(
                icon: Icons.delete_outline,
                title: 'Remove model',
                description: 'Free the space and turn off on-device AI.',
                intent: UiIntent.danger,
                enabled: !busy,
                onTap: busy ? null : _removeModel,
              ),
          ],
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),
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
                  onChanged: (String v) => _updateNow(
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
              onChanged: (bool v) => _updateNow(
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

/// Consistent horizontal padding for the inline form fields inside sections.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.sp(theme.spacing.md),
        context.sp(theme.spacing.xs),
        context.sp(theme.spacing.md),
        context.sp(theme.spacing.sm),
      ),
      child: child,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.detail,
    required this.ready,
  });

  final AiEngineState state;
  final AiEngineDetail detail;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color accent = ready ? theme.colors.bullish : theme.colors.warning;
    final String title = detail.isBusy
        ? detail.busyLabel!
        : detail.localReady && detail.apiReady
            ? 'On-device model and API key ready'
            : detail.localReady
                ? 'On-device model ready'
                : detail.apiReady
                    ? 'API key ready'
                    : state == AiEngineState.failed
                        ? 'AI could not start'
                        : 'No AI configured yet';
    final String body = ready
        ? detail.backend == AiBackend.local
            ? 'Answers are generated on this device — fully offline and private.'
            : 'Requests go from this device straight to your provider.'
        : 'Capture still works with the built-in parser. Add a model or a key '
            'below to unlock smarter sorting and questions.';

    return UiCard(
      variant: UiCardVariant.elevated,
      child: Row(
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(context.sp(theme.spacing.md)),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: context.radius(theme.radii.lg),
            ),
            child: Icon(
              ready ? Icons.verified_outlined : Icons.auto_awesome,
              color: accent,
              size: context.sz(theme.sizes.iconLg),
            ),
          ),
          SizedBox(width: context.sp(theme.spacing.md)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: context.uiText.bodyStrong),
                SizedBox(height: context.sp(theme.spacing.xxs)),
                Text(
                  body,
                  style: context.uiText.caption.copyWith(
                    color: theme.colors.foregroundMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRequest {
  const _DownloadRequest(this.url, this.token);
  final String url;
  final String? token;
}

/// Asks for a direct model URL and an optional access token (Hugging Face
/// gated repos need one).
class _DownloadModelDialog extends StatefulWidget {
  const _DownloadModelDialog();

  @override
  State<_DownloadModelDialog> createState() => _DownloadModelDialogState();
}

class _DownloadModelDialogState extends State<_DownloadModelDialog> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _token = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return UiDialog(
      title: 'Download a model',
      icon: Icons.cloud_download_outlined,
      description:
          'Paste the direct file link (it should end in .task or .bin). Large '
          'files can take a while on mobile data.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UiInput(
            controller: _url,
            hintText: 'https://…/gemma-3n-E2B-it-int4.task',
            keyboardType: TextInputType.url,
          ),
          SizedBox(height: context.sp(theme.spacing.sm)),
          UiInput(
            controller: _token,
            hintText: 'Access token (only for gated downloads)',
            obscure: true,
          ),
        ],
      ),
      actions: <Widget>[
        UiButton(
          label: 'Cancel',
          variant: UiVariant.ghost,
          expandOnMobile: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        UiButton(
          label: 'Download',
          expandOnMobile: false,
          onPressed: () {
            final String url = _url.text.trim();
            if (url.isEmpty) return;
            Navigator.of(context).pop(
              _DownloadRequest(
                url,
                _token.text.trim().isEmpty ? null : _token.text.trim(),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Simple searchable list of the model IDs a provider reported.
class _ModelPickerDialog extends StatefulWidget {
  const _ModelPickerDialog({required this.models});
  final List<String> models;

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final List<String> filtered = widget.models
        .where((String m) => m.toLowerCase().contains(_query.toLowerCase()))
        .take(120)
        .toList();
    return UiDialog(
      title: 'Choose a model',
      icon: Icons.list_alt_outlined,
      description: '${widget.models.length} available',
      content: SizedBox(
        height: context.sz(360),
        child: Column(
          children: <Widget>[
            UiInput(
              hintText: 'Search',
              leadingIcon: Icons.search,
              onChanged: (String v) => setState(() => _query = v),
            ),
            SizedBox(height: context.sp(theme.spacing.sm)),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (BuildContext ctx, int i) => ListTile(
                  dense: true,
                  title: Text(filtered[i], style: context.uiText.body),
                  onTap: () => Navigator.of(ctx).pop(filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        UiButton(
          label: 'Cancel',
          variant: UiVariant.ghost,
          expandOnMobile: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
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
