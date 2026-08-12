import 'package:flutter_tts/flutter_tts.dart';

/// Small shared speech-output wrapper. It intentionally uses the device's
/// installed voice, so AI responses stay offline and do not require an API.
class AiVoiceService {
  AiVoiceService._();
  static final AiVoiceService instance = AiVoiceService._();

  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!_configured) {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.46);
      await _tts.awaitSpeakCompletion(true);
      _configured = true;
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
