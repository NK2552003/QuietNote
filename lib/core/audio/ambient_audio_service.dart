import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class AmbientAudioService {
  static final AmbientAudioService _instance = AmbientAudioService._internal();
  factory AmbientAudioService() => _instance;
  AmbientAudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  String _currentSound = 'none';

  String get currentSound => _currentSound;

  Future<void> setSound(String soundKey) async {
    if (_currentSound == soundKey) return;
    _currentSound = soundKey;

    if (soundKey == 'none') {
      await _player.stop();
      return;
    }

    try {
      final file = await _getOrCreateSoundFile(soundKey);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.stop();
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      // Graceful fallback if audio device unavailable
    }
  }

  Future<void> stop() async {
    _currentSound = 'none';
    await _player.stop();
  }

  Future<File> _getOrCreateSoundFile(String soundKey) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/ambient_$soundKey.wav');
    if (await file.exists()) {
      return file;
    }

    final bytes = _generateWavBytes(soundKey);
    await file.writeAsBytes(bytes);
    return file;
  }

  Uint8List _generateWavBytes(String soundKey) {
    const sampleRate = 22050;
    const durationSeconds = 5;
    const totalSamples = sampleRate * durationSeconds;
    final rand = Random(42);

    final pcmSamples = Int16List(totalSamples);

    double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double sample = 0.0;

      final white = rand.nextDouble() * 2.0 - 1.0;

      switch (soundKey) {
        case 'rain':
          b0 = 0.99886 * b0 + white * 0.0555179;
          b1 = 0.99332 * b1 + white * 0.0750759;
          b2 = 0.96900 * b2 + white * 0.1538520;
          b3 = 0.86650 * b3 + white * 0.3104856;
          b4 = 0.55000 * b4 + white * 0.5329522;
          b5 = -0.7616 * b5 - white * 0.0168980;
          final pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362;
          b6 = white * 0.115926;
          sample = pink * 0.08;

          if (rand.nextDouble() < 0.002) {
            sample += (rand.nextDouble() - 0.5) * 0.4;
          }
          break;

        case 'waves':
          b0 = 0.98 * b0 + white * 0.02;
          final swell = (sin(2 * pi * 0.15 * t) + 1.0) / 2.0;
          sample = b0 * (0.1 + 0.35 * swell);
          break;

        case 'whitenoise':
          sample = white * 0.12;
          break;

        case 'cafe':
          b0 = 0.95 * b0 + white * 0.05;
          final hum = sin(2 * pi * 120 * t) * 0.02;
          sample = b0 * 0.15 + hum;
          break;

        case 'synth':
          final tone1 = sin(2 * pi * 180 * t);
          final tone2 = sin(2 * pi * 190 * t);
          sample = (tone1 + tone2) * 0.12;
          break;

        default:
          sample = white * 0.1;
      }

      final fadeLen = sampleRate ~/ 4;
      if (i < fadeLen) {
        sample *= (i / fadeLen);
      } else if (i > totalSamples - fadeLen) {
        sample *= ((totalSamples - i) / fadeLen);
      }

      pcmSamples[i] = (sample.clamp(-1.0, 1.0) * 32767).toInt();
    }

    final dataSize = totalSamples * 2;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint32(0, 0x52494646, Endian.big);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big);
    header.setUint32(12, 0x666d7420, Endian.big);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, 0x64617461, Endian.big);
    header.setUint32(40, dataSize, Endian.little);

    final bytes = BytesBuilder();
    bytes.add(header.buffer.asUint8List());
    bytes.add(pcmSamples.buffer.asUint8List());
    return bytes.toBytes();
  }
}
