import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/ai/ai_capture_intelligence.dart';
import 'package:quietnote/features/ai/capture_parser.dart';
import 'package:quietnote/features/ai/cloud_ai_providers.dart';

/// Coarse readiness of the AI layer, kept as-is so every screen that already
/// switches on it keeps working.
enum AiEngineState { missingModel, importing, ready, failed }

/// Which backend is actually answering right now.
enum AiBackend { none, local, api }

/// Everything the settings and capture screens need to explain the current
/// state precisely: which backend is live, what went wrong, and how far a
/// model download has got.
class AiEngineDetail {
  const AiEngineDetail({
    this.localReady = false,
    this.apiReady = false,
    this.backend = AiBackend.none,
    this.error,
    this.progress,
    this.busyLabel,
    this.modelPath,
  });

  final bool localReady;
  final bool apiReady;
  final AiBackend backend;
  final String? error;

  /// 0..1 while a model file is downloading, null otherwise.
  final double? progress;
  final String? busyLabel;
  final String? modelPath;

  bool get isBusy => busyLabel != null;

  AiEngineDetail copyWith({
    bool? localReady,
    bool? apiReady,
    AiBackend? backend,
    String? error,
    double? progress,
    String? busyLabel,
    String? modelPath,
    bool clearError = false,
    bool clearBusy = false,
    bool clearProgress = false,
  }) =>
      AiEngineDetail(
        localReady: localReady ?? this.localReady,
        apiReady: apiReady ?? this.apiReady,
        backend: backend ?? this.backend,
        error: clearError ? null : (error ?? this.error),
        progress: clearProgress ? null : (progress ?? this.progress),
        busyLabel: clearBusy ? null : (busyLabel ?? this.busyLabel),
        modelPath: modelPath ?? this.modelPath,
      );
}

/// Live detail about the AI engine. Written only by [AiEngineNotifier].
final aiEngineDetailProvider = StateProvider<AiEngineDetail>(
  (Ref ref) => const AiEngineDetail(),
);

final aiEngineProvider = NotifierProvider<AiEngineNotifier, AiEngineState>(
  AiEngineNotifier.new,
);

/// Owns both AI paths: the on-device Gemma runtime and the person's own cloud
/// API key. Nothing here talks to a QuietNote server, because there isn't one.
class AiEngineNotifier extends Notifier<AiEngineState> {
  InferenceModel? _model;
  dynamic _chat;
  bool _localReady = false;
  bool _initializing = false;

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? const AppSettings();

  AiEngineDetail get detail => ref.read(aiEngineDetailProvider);

  void _setDetail(AiEngineDetail next) =>
      ref.read(aiEngineDetailProvider.notifier).state = next;

  /// The API path is usable when a base URL and model are known and — unless
  /// it is a keyless local server — a key has been pasted.
  bool get _apiConfigured {
    final AppSettings s = _settings;
    if (s.aiProviderMode == 'local') return false;
    final CloudAiProviderPreset preset = cloudAiProviderById(s.aiApiProviderId);
    final String baseUrl = CloudAiClient.normalizeBaseUrl(
      preset.isCustom ? s.aiApiBaseUrl : preset.baseUrl,
    );
    if (baseUrl.isEmpty) return false;
    if (s.aiApiModel.trim().isEmpty) return false;
    if (preset.requiresKey && s.aiApiKey.trim().isEmpty) return false;
    return true;
  }

  bool get isApiReady => _apiConfigured;
  bool get isLocalReady => _localReady;

  /// True when *anything* can answer a free-form question.
  bool get canGenerate => _apiConfigured || _localReady;

  /// Which backend a request would use right now.
  AiBackend get activeBackend {
    final AppSettings s = _settings;
    if (s.aiProviderMode == 'local') {
      return _localReady ? AiBackend.local : AiBackend.none;
    }
    if (s.aiProviderMode == 'api') {
      return _apiConfigured
          ? AiBackend.api
          : (_localReady ? AiBackend.local : AiBackend.none);
    }
    // 'auto' (and any unknown value): prefer whatever is actually configured,
    // on-device first because it is private and free.
    if (_localReady) return AiBackend.local;
    return _apiConfigured ? AiBackend.api : AiBackend.none;
  }

  @override
  AiEngineState build() {
    ref.listen<AsyncValue<AppSettings>>(settingsProvider,
        (AsyncValue<AppSettings>? previous, AsyncValue<AppSettings> next) {
      final AppSettings? prev = previous?.value;
      final AppSettings? curr = next.value;
      if (curr == null) return;
      final bool relevantChange = prev == null ||
          prev.aiProviderMode != curr.aiProviderMode ||
          prev.aiApiKey != curr.aiApiKey ||
          prev.aiApiModel != curr.aiApiModel ||
          prev.aiApiProviderId != curr.aiApiProviderId ||
          prev.aiApiBaseUrl != curr.aiApiBaseUrl;
      if (relevantChange) _refreshState();
    });
    Future<void>.microtask(_initializeLocal);
    return AiEngineState.missingModel;
  }

  void _refreshState({String? error, bool clearError = false}) {
    final bool ready = canGenerate;
    _setDetail(
      detail.copyWith(
        localReady: _localReady,
        apiReady: _apiConfigured,
        backend: activeBackend,
        error: error,
        clearError: clearError || error == null,
      ),
    );
    if (ready) {
      state = AiEngineState.ready;
    } else if (error != null) {
      state = AiEngineState.failed;
    } else {
      state = AiEngineState.missingModel;
    }
  }

  // ---------------------------------------------------------------- local

  Future<void> _initializeLocal() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final dynamic manager = FlutterGemmaPlugin.instance.modelManager;
      bool installed = false;
      try {
        installed = await manager.isModelInstalled as bool;
      } catch (_) {
        installed = false;
      }
      if (!installed) {
        _localReady = false;
        _refreshState();
        return;
      }
      await _createRuntime();
    } catch (e) {
      _localReady = false;
      _refreshState(error: _friendlyLocalError(e));
    } finally {
      _initializing = false;
    }
  }

  Future<void> _createRuntime() async {
    await _disposeRuntime();
    _model = await FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.gemmaIt,
    );
    // A chat handle is optional: sessions are the primary path and are created
    // per request so context never leaks between unrelated captures.
    try {
      _chat = await _model?.createChat();
    } catch (_) {
      _chat = null;
    }
    _localReady = _model != null;
    _refreshState(clearError: true);
  }

  Future<void> _disposeRuntime() async {
    try {
      await (_chat as dynamic)?.session?.close();
    } catch (_) {
      // Older/newer plugin versions expose different shapes; ignore.
    }
    try {
      await (_model as dynamic)?.close();
    } catch (_) {
      // ignore
    }
    _chat = null;
    _model = null;
    _localReady = false;
  }

  /// Copies a `.task`/`.bin` file the person picked into app storage and loads
  /// it. Safe to call repeatedly.
  Future<bool> importModel(String sourcePath) async {
    state = AiEngineState.importing;
    _setDetail(
      detail.copyWith(
        busyLabel: 'Importing model…',
        clearError: true,
        clearProgress: true,
      ),
    );
    try {
      final File sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw StateError('That file no longer exists on this device.');
      }
      final int size = await sourceFile.length();
      if (size < 1024 * 1024) {
        throw StateError(
          'That file is only ${(size / 1024).round()} KB — pick the Gemma '
          '.task or .bin model file, not a placeholder.',
        );
      }

      final Directory appDir = await getApplicationDocumentsDirectory();
      final String extension =
          p.extension(sourcePath).isEmpty ? '.task' : p.extension(sourcePath);
      final String targetPath =
          p.join(appDir.path, 'quietnote_local_model$extension');
      final File target = File(targetPath);
      if (await target.exists()) await target.delete();
      await sourceFile.copy(targetPath);

      await _installPath(targetPath);
      return _localReady;
    } catch (e) {
      _localReady = false;
      _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
      _refreshState(error: _friendlyLocalError(e));
      return false;
    }
  }

  /// Downloads a model file over HTTP (Hugging Face, Kaggle mirror, own host)
  /// straight into app storage, reporting progress, then loads it.
  Future<bool> downloadModel(String url, {String? accessToken}) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.isAbsolute || !uri.scheme.startsWith('http')) {
      _refreshState(error: 'That does not look like a valid download link.');
      return false;
    }

    state = AiEngineState.importing;
    _setDetail(
      detail.copyWith(
        busyLabel: 'Downloading model…',
        progress: 0,
        clearError: true,
      ),
    );

    final http.Client client = http.Client();
    IOSink? sink;
    File? partial;
    try {
      final http.Request request = http.Request('GET', uri);
      if (accessToken != null && accessToken.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${accessToken.trim()}';
      }
      final http.StreamedResponse response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'The download failed (${response.statusCode}). If the model needs a '
          'licence acceptance, add your access token.',
        );
      }

      final Directory appDir = await getApplicationDocumentsDirectory();
      final String extension = p.extension(uri.path).isEmpty
          ? '.task'
          : p.extension(uri.path).split('?').first;
      final String targetPath =
          p.join(appDir.path, 'quietnote_local_model$extension');
      partial = File('$targetPath.part');
      if (await partial.exists()) await partial.delete();
      sink = partial.openWrite();

      final int? total = response.contentLength;
      int received = 0;
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          _setDetail(
            detail.copyWith(
              busyLabel: 'Downloading model…',
              progress: (received / total).clamp(0.0, 1.0),
            ),
          );
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received < 1024 * 1024) {
        throw StateError(
          'The download returned only ${(received / 1024).round()} KB — the '
          'link probably points at a web page, not the model file.',
        );
      }

      final File target = File(targetPath);
      if (await target.exists()) await target.delete();
      await partial.rename(targetPath);
      partial = null;

      _setDetail(detail.copyWith(busyLabel: 'Loading model…'));
      await _installPath(targetPath);
      return _localReady;
    } catch (e) {
      try {
        await sink?.close();
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {
        // ignore cleanup failures
      }
      _localReady = false;
      _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
      _refreshState(error: _friendlyLocalError(e));
      return false;
    } finally {
      client.close();
    }
  }

  /// Loads a model that was shipped inside the app bundle (see
  /// `flutter_gemma: model_assets:` in pubspec.yaml).
  Future<bool> installBundledModel(String assetName) async {
    state = AiEngineState.importing;
    _setDetail(
      detail.copyWith(busyLabel: 'Loading bundled model…', clearError: true),
    );
    try {
      final dynamic manager = FlutterGemmaPlugin.instance.modelManager;
      await manager.installModelFromAsset(assetName);
      _setDetail(detail.copyWith(modelPath: assetName));
      await _createRuntime();
      _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
      return _localReady;
    } catch (e) {
      _localReady = false;
      _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
      _refreshState(
        error: 'No bundled model found in this build. ($e)',
      );
      return false;
    }
  }

  Future<void> _installPath(String targetPath) async {
    final dynamic manager = FlutterGemmaPlugin.instance.modelManager;
    await manager.setModelPath(targetPath);
    _setDetail(detail.copyWith(modelPath: targetPath));
    await _createRuntime();
    _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
  }

  /// Frees the on-device model and forgets the file.
  Future<void> deleteLocalModel() async {
    await _disposeRuntime();
    try {
      final dynamic manager = FlutterGemmaPlugin.instance.modelManager;
      await manager.deleteModel();
    } catch (_) {
      // Older plugin versions may not expose deleteModel.
    }
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      for (final String ext in const <String>['.task', '.bin', '.tflite']) {
        final File f = File(p.join(appDir.path, 'quietnote_local_model$ext'));
        if (await f.exists()) await f.delete();
      }
    } catch (_) {
      // ignore
    }
    _setDetail(
      detail.copyWith(clearBusy: true, clearProgress: true, modelPath: ''),
    );
    _refreshState(clearError: true);
  }

  /// Re-runs local initialization, e.g. after a failure.
  Future<void> retryLocal() async {
    _setDetail(detail.copyWith(clearError: true));
    await _initializeLocal();
  }

  // ------------------------------------------------------------------ api

  CloudAiClient buildCloudClient([AppSettings? override]) {
    final AppSettings s = override ?? _settings;
    final CloudAiProviderPreset preset = cloudAiProviderById(s.aiApiProviderId);
    return CloudAiClient(
      baseUrl: preset.isCustom ? s.aiApiBaseUrl : preset.baseUrl,
      apiKey: s.aiApiKey,
      model: s.aiApiModel,
      requiresKey: preset.requiresKey,
    );
  }

  /// One-shot check used by Settings > AI.
  Future<String> testApiConnection([AppSettings? override]) async {
    final String reply = await buildCloudClient(override).chat(
      systemPrompt: 'Reply with the single word: ok',
      userMessage: 'ok',
      maxTokens: 16,
      temperature: 0,
      timeout: const Duration(seconds: 30),
    );
    _refreshState(clearError: true);
    return reply;
  }

  Future<List<String>> listApiModels([AppSettings? override]) =>
      buildCloudClient(override).listModels();

  // ------------------------------------------------------------- inference

  /// Structured capture extraction. Returns the raw model reply so callers can
  /// merge it through [AiCaptureIntelligence.applyToDraft].
  Future<String> extractCapture(String text) => _generate(
        systemPrompt: AiCaptureIntelligence.systemPrompt(DateTime.now()),
        userMessage: 'Capture: $text',
        maxTokens: 320,
        temperature: 0.1,
        jsonMode: true,
      );

  /// Runs the heuristic parser, then lets the active AI backend refine it.
  /// Never throws: a failed model call simply returns the heuristic draft.
  Future<CaptureDraft> buildDraft(String text, {CaptureType? fallbackType}) async {
    final CaptureDraft draft = CaptureParser.parse(text);
    if (fallbackType != null && draft.confidence < 0.60) {
      draft.type = fallbackType;
    }
    if (!canGenerate) return draft;
    try {
      final String reply = await extractCapture(text);
      AiCaptureIntelligence.applyToDraft(draft, reply);
      _refreshState(clearError: true);
    } catch (e) {
      // Best effort: keep the heuristic draft, but remember why AI was silent.
      _setDetail(detail.copyWith(error: _friendlyLocalError(e)));
    }
    return draft;
  }

  /// A short, conversational answer — from the on-device model, or from the
  /// person's own cloud API key when that is the active backend.
  Future<String> answer(
    String text, {
    List<AiChatTurn> history = const <AiChatTurn>[],
  }) =>
      _generate(
        systemPrompt: AiCaptureIntelligence.answerSystemPrompt,
        userMessage: text,
        history: history,
        maxTokens: 700,
        temperature: 0.5,
      );

  /// Back-compat shim for older callers.
  Future<Map<String, dynamic>> parseAction(String text) async {
    final String reply = await extractCapture(text);
    final Map<String, dynamic>? json = AiCaptureIntelligence.extractJson(reply);
    return <String, dynamic>{
      'type': json?['type'] ?? 'todo',
      'text': json?['title'] ?? reply,
      'raw': reply,
    };
  }

  Future<String> _generate({
    required String systemPrompt,
    required String userMessage,
    List<AiChatTurn> history = const <AiChatTurn>[],
    int maxTokens = 512,
    double temperature = 0.4,
    bool jsonMode = false,
  }) async {
    final AiBackend backend = activeBackend;
    switch (backend) {
      case AiBackend.api:
        return buildCloudClient().chat(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          history: history,
          maxTokens: maxTokens,
          temperature: temperature,
          jsonMode: jsonMode,
        );
      case AiBackend.local:
        try {
          return await _localGenerate(
            _flattenPrompt(systemPrompt, history, userMessage),
          );
        } catch (e) {
          // A dead local runtime should not block someone who also has a key.
          if (_apiConfigured) {
            return buildCloudClient().chat(
              systemPrompt: systemPrompt,
              userMessage: userMessage,
              history: history,
              maxTokens: maxTokens,
              temperature: temperature,
              jsonMode: jsonMode,
            );
          }
          rethrow;
        }
      case AiBackend.none:
        throw CloudAiException(
          'No AI backend set up yet. Open Settings > AI to import an '
          'on-device model or paste an API key.',
        );
    }
  }

  static String _flattenPrompt(
    String systemPrompt,
    List<AiChatTurn> history,
    String userMessage,
  ) {
    final StringBuffer buffer = StringBuffer(systemPrompt)..writeln();
    for (final AiChatTurn turn in history) {
      buffer.writeln(
        '${turn.role == 'user' ? 'User' : 'Assistant'}: ${turn.content}',
      );
    }
    buffer.writeln('User: $userMessage');
    buffer.write('Assistant:');
    return buffer.toString();
  }

  /// Runs one prompt through the on-device runtime. A fresh session is used
  /// per request (and closed afterwards) so answers never drift because of
  /// unrelated earlier captures, with a chat-handle fallback for plugin
  /// versions that do not expose sessions.
  Future<String> _localGenerate(String prompt) async {
    if (_model == null || !_localReady) {
      await _initializeLocal();
    }
    final dynamic model = _model;
    if (model == null) {
      throw StateError(
        'The on-device model is not loaded. Import it again in Settings > AI.',
      );
    }

    dynamic session;
    try {
      session = await model.createSession();
    } catch (_) {
      session = null;
    }

    if (session != null) {
      try {
        await session.addQueryChunk(Message(text: prompt, isUser: true));
        final dynamic raw = await session.getResponse();
        final String text = _asText(raw);
        if (text.isEmpty) {
          throw StateError('The on-device model returned nothing.');
        }
        return text;
      } finally {
        try {
          await session.close();
        } catch (_) {
          // ignore
        }
      }
    }

    // Fallback: reuse the chat handle.
    _chat ??= await model.createChat();
    final dynamic chat = _chat;
    if (chat == null) {
      throw StateError('The on-device model could not start a session.');
    }
    dynamic raw;
    try {
      await chat.addQueryChunk(Message(text: prompt, isUser: true));
      raw = await chat.generateChatResponse();
    } catch (_) {
      await chat.session.addQueryChunk(Message(text: prompt, isUser: true));
      raw = await chat.session.getResponse();
    }
    final String text = _asText(raw);
    if (text.isEmpty) {
      throw StateError('The on-device model returned nothing.');
    }
    return text;
  }

  /// Normalises whatever the plugin hands back (String, ModelResponse, …).
  static String _asText(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return CloudAiClient.stripReasoning(raw);
    for (final String field in const <String>['token', 'text', 'message']) {
      try {
        final dynamic value = field == 'token'
            ? (raw as dynamic).token
            : field == 'text'
                ? (raw as dynamic).text
                : (raw as dynamic).message;
        if (value is String && value.trim().isNotEmpty) {
          return CloudAiClient.stripReasoning(value);
        }
      } catch (_) {
        // Field not present on this response type.
      }
    }
    return CloudAiClient.stripReasoning(raw.toString());
  }

  String _friendlyLocalError(Object error) {
    if (error is CloudAiException) return error.message;
    final String text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('MissingPluginException')) {
      return 'On-device AI is not available in this build. Use an API key '
          'instead, or run a full release build.';
    }
    return text.replaceFirst('StateError: ', '');
  }
}
