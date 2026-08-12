import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

enum AiEngineState { missingModel, importing, ready, failed }

final aiEngineProvider = NotifierProvider<AiEngineNotifier, AiEngineState>(
  AiEngineNotifier.new,
);

class AiEngineNotifier extends Notifier<AiEngineState> {
  InferenceModel? _model;
  dynamic _chat;

  @override
  AiEngineState build() {
    _initialize();
    return AiEngineState.missingModel;
  }

  Future<void> _initialize() async {
    try {
      final isInstalled =
          await FlutterGemmaPlugin.instance.modelManager.isModelInstalled;
      if (!isInstalled) {
        state = AiEngineState.missingModel;
        return;
      }

      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
      );
      _chat = await _model?.createChat();
      if (_chat != null) {
        state = AiEngineState.ready;
      } else {
        state = AiEngineState.missingModel;
      }
    } catch (e) {
      state = AiEngineState.failed;
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

  Future<Map<String, dynamic>> parseAction(String text) async {
    if (state != AiEngineState.ready || _chat == null) {
      throw StateError('AI Engine is not ready. Current state: $state');
    }

    await _chat!.session.addQueryChunk(
      Message(
        text: '''You are QuietNote's offline capture assistant.
Rewrite the user's capture as one concise factual title only. Preserve names,
dates, times, quantities, and intent exactly. Do not invent details, add
explanations, use markdown, or change the requested action.
User capture: $text''',
        isUser: true,
      ),
    );
    final response = await _chat!.session.getResponse();

    return {'type': 'todo', 'text': response ?? text};
  }

  /// A short, conversational on-device answer used by the AI Capture screen.
  /// This is inference, not model training: the imported model remains local
  /// and untouched while the conversation is processed.
  Future<String> answer(String text) async {
    if (state != AiEngineState.ready || _chat == null) {
      throw StateError('Add a local model before asking an AI question.');
    }
    await _chat!.session.addQueryChunk(
      Message(
        text: '''You are QuietNote, a private on-device productivity assistant.
Answer in at most four short sentences. Be specific, practical, and honest
about uncertainty. Preserve dates, times, names, and numbers from the user.
For planning questions, give the single best next action first. Never claim
you completed a real-world action or accessed data not present in this chat.
User: $text''',
        isUser: true,
      ),
    );
    final response = await _chat!.session.getResponse();
    final answer = response?.toString().trim();
    if (answer == null || answer.isEmpty) {
      throw StateError('The local model did not return a response.');
    }
    return answer;
  }
}
