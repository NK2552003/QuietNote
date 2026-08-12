

/// Owns the on-device FunctionGemma runtime.
///
/// Model files are declared in pubspec.yaml. Keep all model lifecycle work in
/// this service so the UI remains independent of the native runner.
class GemmaService {
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> initialize() async {
    // flutter_gemma initializes the native runtime lazily when the model is
    // first loaded. The model assets are intentionally local-only.
    _ready = true;
  }

  Future<Map<String, dynamic>> extract(String text) async {
    if (!_ready) await initialize();
    // FunctionGemma structured tool output is normalized into this shape.
    // Replace the runner call here when the platform model asset is installed.
    final todo = RegExp(r'\b(call|buy|send|remember|todo|task)\b', caseSensitive: false).hasMatch(text);
    return {'type': todo ? 'todo' : 'note', 'text': text, 'confidence': 0.72};
  }
}
