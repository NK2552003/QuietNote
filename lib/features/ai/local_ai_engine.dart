import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/ai/cloud_ai_providers.dart';

enum AiEngineState { missingModel, importing, ready, failed }

final aiEngineProvider = NotifierProvider<AiEngineNotifier, AiEngineState>(
  AiEngineNotifier.new,
);

class AiEngineNotifier extends Notifier<AiEngineState> {
  InferenceModel? _model;
  dynamic _chat;

  /// True once local (on-device) inference is initialized and ready, kept
  /// separate from [state] because [state] also has to reflect API-mode
  /// readiness, which doesn't depend on the local model at all.
  bool _localReady = false;

  bool get _apiConfigured {
    final AppSettings settings =
        ref.read(settingsProvider).value ?? const AppSettings();
    return settings.aiProviderMode == 'api' &&
        settings.aiApiKey.trim().isNotEmpty &&
        settings.aiApiModel.trim().isNotEmpty;
  }

  @override
  AiEngineState build() {
    ref.listen(settingsProvider, (previous, next) {
      final AppSettings? prev = previous?.value;
      final AppSettings? curr = next.value;
      if (curr == null) return;
      final bool relevantChange =
          prev == null ||
          prev.aiProviderMode != curr.aiProviderMode ||
          prev.aiApiKey != curr.aiApiKey ||
          prev.aiApiModel != curr.aiApiModel ||
          prev.aiApiProviderId != curr.aiApiProviderId ||
          prev.aiApiBaseUrl != curr.aiApiBaseUrl;
      if (relevantChange) _refreshState();
    });
    _initialize();
    return AiEngineState.missingModel;
  }

  void _refreshState() {
    if (_apiConfigured) {
      state = AiEngineState.ready;
    } else {
      state = _localReady ? AiEngineState.ready : AiEngineState.missingModel;
    }
  }

  Future<void> _initialize() async {
    try {
      final isInstalled =
          await FlutterGemmaPlugin.instance.modelManager.isModelInstalled;
      if (!isInstalled) {
        _localReady = false;
        _refreshState();
        return;
      }

      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
      );
      _chat = await _model?.createChat();
      _localReady = _chat != null;
      _refreshState();
    } catch (e) {
      if (_apiConfigured) {
        state = AiEngineState.ready;
      } else {
        state = AiEngineState.failed;
      }
    }
  }

  Future<void> importModel(String sourcePath) async {
    state = AiEngineState.importing;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final extension = p.extension(sourcePath).isEmpty
          ? '.task'
          : p.extension(sourcePath);
      final targetPath = p.join(appDir.path, 'quietnote_local_model$extension');

      final sourceFile = File(sourcePath);
      await sourceFile.copy(targetPath);

      await FlutterGemmaPlugin.instance.modelManager.setModelPath(targetPath);
      await _initialize();
    } catch (e) {
      state = AiEngineState.failed;
    }
  }

  CloudAiClient _cloudClient() {
    final AppSettings settings =
        ref.read(settingsProvider).value ?? const AppSettings();
    final CloudAiProviderPreset preset = cloudAiProviderById(
      settings.aiApiProviderId,
    );
    final String baseUrl = preset.id == 'custom'
        ? settings.aiApiBaseUrl
        : preset.baseUrl;
    return CloudAiClient(
      baseUrl: baseUrl,
      apiKey: settings.aiApiKey,
      model: settings.aiApiModel,
    );
  }

  Future<Map<String, dynamic>> parseAction(String text) async {
    const systemPrompt =
        '''You are QuietNote's capture assistant.
Rewrite the user's capture as one concise factual title only. Preserve names,
dates, times, quantities, and intent exactly. Do not invent details, add
explanations, use markdown, or change the requested action.''';

    if (_apiConfigured) {
      final response = await _cloudClient().chat(
        systemPrompt: systemPrompt,
        userMessage: 'User capture: $text',
        maxTokens: 128,
      );
      return {'type': 'todo', 'text': response};
    }

    if (state != AiEngineState.ready || _chat == null) {
      throw StateError('AI Engine is not ready. Current state: $state');
    }

    await _chat!.session.addQueryChunk(
      Message(
        text: '$systemPrompt\nUser capture: $text',
        isUser: true,
      ),
    );
    final response = await _chat!.session.getResponse();

    return {'type': 'todo', 'text': response ?? text};
  }

  /// A short, conversational answer used by the AI Capture screen — served
  /// from the on-device model, or from the person's own cloud API key if
  /// they've configured one in Settings > AI.
  Future<String> answer(String text) async {
    const systemPrompt =
        '''You are QuietNote, a private productivity assistant.
Answer in at most four short sentences. Be specific, practical, and honest
about uncertainty. Preserve dates, times, names, and numbers from the user.
For planning questions, give the single best next action first. Never claim
you completed a real-world action or accessed data not present in this chat.''';

    if (_apiConfigured) {
      return _cloudClient().chat(
        systemPrompt: systemPrompt,
        userMessage: text,
      );
    }

    if (state != AiEngineState.ready || _chat == null) {
      throw StateError('Add a local model before asking an AI question.');
    }
    await _chat!.session.addQueryChunk(
      Message(text: '$systemPrompt\nUser: $text', isUser: true),
    );
    final response = await _chat!.session.getResponse();
    final answer = response?.toString().trim();
    if (answer == null || answer.isEmpty) {
      throw StateError('The local model did not return a response.');
    }
    return answer;
  }
}
