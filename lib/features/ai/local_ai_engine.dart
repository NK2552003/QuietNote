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
import 'package:quietnote/features/ai/ai_local_prompts.dart';
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

      // 1. Check if user previously imported/downloaded a model in app storage
      try {
        final Directory appDir = await getApplicationDocumentsDirectory();
        String? existingPath;
        for (final String ext in const <String>['.task', '.bin', '.tflite', '.gguf']) {
          final File f = File(p.join(appDir.path, 'quietnote_local_model$ext'));
          if (await f.exists() && (await f.length()) > 1024 * 1024) {
            existingPath = f.path;
            break;
          }
        }

        if (existingPath != null) {
          try {
            await manager.setModelPath(existingPath);
            _setDetail(detail.copyWith(modelPath: existingPath));
            await _createRuntime();
            if (_localReady) return;
          } catch (e) {
            // If setting path failed, continue to fallback check
          }
        }
      } catch (_) {
        // Continue to plugin isModelInstalled check
      }

      // 2. Check plugin internal installed state
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
    try {
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
      );
    } catch (_) {
      try {
        _model = await FlutterGemmaPlugin.instance.createModel(
          modelType: ModelType.general,
        );
      } catch (e) {
        _model = null;
        rethrow;
      }
    }
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
  /// it. Supports both file paths and byte streams (for scoped storage).
  Future<bool> importModel(String sourcePath, [List<int>? sourceBytes]) async {
    state = AiEngineState.importing;
    _setDetail(
      detail.copyWith(
        busyLabel: 'Importing model…',
        clearError: true,
        clearProgress: true,
      ),
    );
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      String extension = '.task';
      if (sourcePath.isNotEmpty) {
        final ext = p.extension(sourcePath);
        if (ext.isNotEmpty) extension = ext;
      }

      final String targetPath =
          p.join(appDir.path, 'quietnote_local_model$extension');
      final File target = File(targetPath);
      if (await target.exists()) await target.delete();

      if (sourcePath.isNotEmpty && await File(sourcePath).exists()) {
        final File sourceFile = File(sourcePath);
        final int size = await sourceFile.length();
        if (size < 1024 * 1024) {
          throw StateError(
            'That file is only ${(size / 1024).round()} KB — pick a valid Gemma '
            '.task or .bin model file (typically 500MB - 2GB).',
          );
        }
        await sourceFile.copy(targetPath);
      } else if (sourceBytes != null && sourceBytes.isNotEmpty) {
        if (sourceBytes.length < 1024 * 1024) {
          throw StateError(
            'That file is only ${(sourceBytes.length / 1024).round()} KB — pick a valid Gemma '
            '.task or .bin model file (typically 500MB - 2GB).',
          );
        }
        await target.writeAsBytes(sourceBytes);
      } else {
        throw StateError('The selected model file could not be read.');
      }

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
  Future<bool> installBundledModel([String? customAsset]) async {
    state = AiEngineState.importing;
    _setDetail(
      detail.copyWith(busyLabel: 'Checking bundled model…', clearError: true),
    );
    final List<String> candidateAssets = <String>[
      if (customAsset != null && customAsset.isNotEmpty) customAsset,
      'assets/models/gemma-3n-E2B-it-int4.task',
      'assets/models/functiongemma-270m-it.task',
      'assets/models/model.bin',
    ];

    final dynamic manager = FlutterGemmaPlugin.instance.modelManager;
    for (final String asset in candidateAssets) {
      try {
        await manager.installModelFromAsset(asset);
        _setDetail(detail.copyWith(modelPath: asset));
        await _createRuntime();
        if (_localReady) {
          _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
          return true;
        }
      } catch (_) {
        // try next candidate
      }
    }

    _localReady = false;
    _setDetail(detail.copyWith(clearBusy: true, clearProgress: true));
    _refreshState(
      error: 'No bundled model file found in this build. You can import a downloaded Gemma .task or .bin model with "Import local model" or use a Cloud API key.',
    );
    return false;
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
      for (final String ext in const <String>['.task', '.bin', '.tflite', '.gguf']) {
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
      systemPrompt: 'You are an AI assistant. Answer with the single word: ok',
      userMessage: 'Test connection',
      maxTokens: 16,
      temperature: 0,
      timeout: const Duration(seconds: 25),
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

  // ---------------------------------------------------------- AI enrichment

  /// Generates flashcard Q&A pairs from a [topic] using the active backend.
  /// Returns [] when no AI backend is configured or the call fails — the
  /// conversation flow continues and lets the user add cards manually.
  Future<List<({String front, String back})>> generateFlashcards(
    String topic, {
    int count = 5,
  }) async {
    if (!canGenerate) return const [];
    try {
      final String reply = await _generate(
        systemPrompt:
            'You generate flashcard pairs. Reply with ONLY a JSON array.',
        userMessage: AiLocalPrompts.generateFlashcards(topic, count: count),
        maxTokens: 512,
        temperature: 0.3,
        jsonMode: false,
      );
      return AiCaptureIntelligence.parseFlashcardPairs(reply);
    } catch (_) {
      return const [];
    }
  }

  /// Suggests 3 milestone strings for a goal. Returns [] on failure.
  Future<List<String>> suggestGoalMilestones(
    String title,
    double target, {
    String? unit,
  }) async {
    if (!canGenerate) return const [];
    try {
      final String reply = await _generate(
        systemPrompt:
            'You suggest milestone steps for goals. Reply ONLY with a JSON array of strings.',
        userMessage: AiLocalPrompts.suggestMilestones(title, target, unit),
        maxTokens: 256,
        temperature: 0.4,
      );
      return AiCaptureIntelligence.parseMilestones(reply);
    } catch (_) {
      return const [];
    }
  }

  /// Returns a polished, concise title for the given raw capture text.
  /// Falls back to [rawText] on any failure so callers are always safe.
  Future<String> polishTitle(String rawText, CaptureType type) async {
    if (!canGenerate || rawText.trim().isEmpty) return rawText;
    try {
      final String reply = await _generate(
        systemPrompt: 'You clean up and improve capture titles. Reply with ONLY the improved title.',
        userMessage: AiLocalPrompts.cleanTitle(rawText, type.shortLabel),
        maxTokens: 80,
        temperature: 0.2,
      );
      final String clean = reply.trim();
      if (clean.isEmpty || clean.length > 200) return rawText;
      return clean;
    } catch (_) {
      return rawText;
    }
  }

  /// Suggests 3-4 actionable subtasks for a task title.
  Future<List<String>> generateSubtasks(String taskTitle) async {
    if (!canGenerate || taskTitle.trim().isEmpty) return const [];
    try {
      final String reply = await _generate(
        systemPrompt:
            'You break down tasks into actionable subtasks. Reply ONLY with a JSON array of strings.',
        userMessage: AiLocalPrompts.generateSubtasks(taskTitle),
        maxTokens: 256,
        temperature: 0.3,
      );
      return AiCaptureIntelligence.parseMilestones(reply);
    } catch (_) {
      return const [];
    }
  }

  /// Generates a structured study note in Markdown for the given topic.
  Future<String> writeMarkdownNote(String topic) async {
    if (!canGenerate || topic.trim().isEmpty) return '';
    try {
      final String reply = await _generate(
        systemPrompt:
            'You are an expert academic tutor. Write clear, structured study notes formatted with Markdown.',
        userMessage: AiLocalPrompts.formatNoteMarkdown(topic),
        maxTokens: 1024,
        temperature: 0.4,
      );
      return reply.trim();
    } catch (_) {
      return '';
    }
  }

  /// Generates a reflective journal entry for the given topic.
  Future<String> writeJournalEntry(String topic) async {
    if (!canGenerate || topic.trim().isEmpty) return '';
    try {
      final String reply = await _generate(
        systemPrompt:
            'You are a thoughtful journaling assistant. Write a reflective, personal, first-person journal entry. '
            'Focus on emotional depth, insight, and mindfulness. Use authentic prose without bullet points or Markdown headers.',
        userMessage: 'Write a personal journal entry about: $topic',
        maxTokens: 800,
        temperature: 0.7,
      );
      return reply.trim();
    } catch (_) {
      return '';
    }
  }

  /// Enhances or refactors selected text in a note or journal entry according
  /// to the active AI backend (local on-device model or cloud API from Settings).
  Future<String> enhanceSelectedText({
    required String selectedText,
    required CaptureType type,
    String? contextTitle,
    String? customInstruction,
  }) async {
    if (!canGenerate || selectedText.trim().isEmpty) return '';
    try {
      final String systemPrompt;
      final String userPrompt;
      final int tokens =
          customInstruction != null && customInstruction.isNotEmpty ? 2048 : 800;

      if (type == CaptureType.journal) {
        systemPrompt =
            'You are a thoughtful writing editor and journaling assistant. '
            'Improve, rewrite, or expand the provided journal text according to the user instruction while keeping the authentic, reflective first-person voice and emotional depth. '
            'Return ONLY the replacement text without conversational preamble or meta-commentary.';
        userPrompt = customInstruction != null && customInstruction.isNotEmpty
            ? 'Journal context: ${contextTitle ?? ""}\nInstruction: $customInstruction\n\nSelected text:\n"$selectedText"'
            : 'Journal context: ${contextTitle ?? ""}\n\nPlease improve and polish this journal excerpt while maintaining its personal voice:\n"$selectedText"';
      } else {
        systemPrompt =
            'You are an expert academic tutor and writing assistant. '
            'Rewrite, expand, or format the provided text strictly according to the user instruction. '
            'Maintain or generate clean, well-structured Markdown formatting when appropriate. '
            'Return ONLY the replacement content without meta-commentary, introductory greetings, or conversational filler.';
        userPrompt = customInstruction != null && customInstruction.isNotEmpty
            ? 'Note context: ${contextTitle ?? ""}\nInstruction: $customInstruction\n\nSelected text:\n"$selectedText"'
            : 'Note context: ${contextTitle ?? ""}\n\nPlease enhance, clarify, and improve this note excerpt:\n"$selectedText"';
      }

      final String reply = await _generate(
        systemPrompt: systemPrompt,
        userMessage: userPrompt,
        maxTokens: tokens,
        temperature: 0.4,
      );
      return reply.trim();
    } catch (_) {
      return '';
    }
  }

  /// Generates content for a specific field/type combination during an AI capture
  /// conversation step. The AI fills in the field so the user doesn't have to
  /// type the entire body themselves.
  ///
  /// Returns the generated text, or empty string on failure.
  Future<String> generateFieldContent({
    required String title,
    required CaptureType type,
    required String field,
    String? userHint,
  }) async {
    if (!canGenerate || title.trim().isEmpty) return '';
    final topic = userHint?.isNotEmpty == true ? '$title — $userHint' : title;
    try {
      switch (type) {
        case CaptureType.note:
          return await writeMarkdownNote(topic);
        case CaptureType.journal:
          return await writeJournalEntry(topic);
        case CaptureType.todo:
          // For todo "details" — write a short step-by-step description
          return await _generate(
            systemPrompt:
                'You are a productivity assistant. Write a concise, step-by-step breakdown for completing the task. '
                'Use a numbered list or short prose.',
            userMessage: 'Describe how to complete this task: $topic',
            maxTokens: 400,
            temperature: 0.4,
          ).then((r) => r.trim());
        case CaptureType.habit:
          return await _generate(
            systemPrompt:
                'You are a wellness coach. Write a short motivational description for the habit '
                'explaining its benefits and how to stay consistent.',
            userMessage: 'Describe the habit: $topic',
            maxTokens: 300,
            temperature: 0.5,
          ).then((r) => r.trim());
        case CaptureType.goal:
          return await _generate(
            systemPrompt:
                'You are a goal-setting coach. Write a clear description of why this goal matters '
                'and an approach to achieving it.',
            userMessage: 'Describe this goal: $topic',
            maxTokens: 350,
            temperature: 0.5,
          ).then((r) => r.trim());
        case CaptureType.routine:
          return await _generate(
            systemPrompt:
                'You are a productivity and wellness expert. Write a structured routine description '
                'with steps and the purpose of each step.',
            userMessage: 'Write a routine description for: $topic',
            maxTokens: 500,
            temperature: 0.45,
          ).then((r) => r.trim());
        case CaptureType.event:
          return await _generate(
            systemPrompt:
                'You are an assistant helping plan events. Write a concise event description or agenda.',
            userMessage: 'Write a description for this event: $topic',
            maxTokens: 300,
            temperature: 0.45,
          ).then((r) => r.trim());
        default:
          // Fallback for any unhandled type
          return await _generate(
            systemPrompt: 'You are a helpful writing assistant. Write a clear, concise description.',
            userMessage: 'Write content about: $topic',
            maxTokens: 400,
            temperature: 0.5,
          ).then((r) => r.trim());
      }
    } catch (_) {
      return '';
    }
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
      return 'Native on-device AI runtime is not supported on this platform/device. '
          'You can use any free Cloud API key (Gemini, Groq, NVIDIA) in Settings › AI.';
    }
    if (text.contains('PlatformException') || text.contains('Failed to load')) {
      return 'Could not initialize the local model: $text. Please check that the file is a valid Gemma .task or .bin MediaPipe model.';
    }
    return text.replaceFirst('StateError: ', '');
  }
}
