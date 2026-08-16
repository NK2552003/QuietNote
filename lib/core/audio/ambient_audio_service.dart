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
  final AudioPlayer _alarmPlayer = AudioPlayer();
  String _currentSound = 'none';
  bool _isPlayingAlarm = false;

  String get currentSound => _currentSound;
  bool get isPlayingAlarm => _isPlayingAlarm;

  // ---------------------------------------------------------------------------
  // Ambient Soundscapes
  // ---------------------------------------------------------------------------

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
    } catch (_) {
      // Graceful fallback if audio device unavailable
    }
  }

  Future<void> stop() async {
    _currentSound = 'none';
    await _player.stop();
  }

  // ---------------------------------------------------------------------------
  // Alarm & Chime System
  // ---------------------------------------------------------------------------

  Future<void> playAlarmSound(String alarmKey) async {
    if (alarmKey == 'none') return;
    try {
      _isPlayingAlarm = true;
      final file = await _getOrCreateAlarmFile(alarmKey);
      await _alarmPlayer.setReleaseMode(ReleaseMode.stop);
      await _alarmPlayer.stop();
      await _alarmPlayer.play(DeviceFileSource(file.path));
    } catch (_) {
      _isPlayingAlarm = false;
    }
  }

  Future<void> stopAlarm() async {
    _isPlayingAlarm = false;
    try {
      await _alarmPlayer.stop();
    } catch (_) {}
  }

  Future<void> previewAlarmSound(String alarmKey) async {
    await stopAlarm();
    await playAlarmSound(alarmKey);
  }

  // ---------------------------------------------------------------------------
  // File Cache & Synthesis
  // ---------------------------------------------------------------------------

  Future<File> _getOrCreateSoundFile(String soundKey) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/ambient_${soundKey}_v2.wav');
    if (await file.exists()) {
      return file;
    }

    final bytes = _generateSeamlessAmbientWav(soundKey);
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<File> _getOrCreateAlarmFile(String alarmKey) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/alarm_${alarmKey}_v1.wav');
    if (await file.exists()) {
      return file;
    }

    final bytes = _generateAlarmWav(alarmKey);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Synthesizes a seamless looping ambient buffer using circular overlap-add
  /// raised-cosine crossfading to completely eliminate seam clicks and silence.
  Uint8List _generateSeamlessAmbientWav(String soundKey) {
    const sampleRate = 22050;
    const durationSeconds = 8;
    const totalSamples = sampleRate * durationSeconds;
    const crossfadeSamples = 33075; // 1.5s crossfade at 22050Hz
    final rand = Random(42);

    final rawSamples = Float64List(totalSamples);
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
          sample = pink * 0.09;
          if (rand.nextDouble() < 0.003) {
            sample += (rand.nextDouble() - 0.5) * 0.35;
          }
          break;

        case 'waves':
          b0 = 0.98 * b0 + white * 0.02;
          final swell = (sin(2 * pi * (1.0 / durationSeconds) * 2 * t) + 1.0) / 2.0;
          sample = b0 * (0.15 + 0.35 * swell);
          break;

        case 'whitenoise':
          sample = white * 0.11;
          break;

        case 'cafe':
          b0 = 0.95 * b0 + white * 0.05;
          final hum = sin(2 * pi * 120 * t) * 0.02;
          final murmur = sin(2 * pi * 0.5 * t) * 0.03;
          sample = b0 * 0.14 + hum + murmur;
          break;

        case 'synth':
          final tone1 = sin(2 * pi * 174.61 * t); // F3
          final tone2 = sin(2 * pi * 261.63 * t); // C4
          final tone3 = sin(2 * pi * 329.63 * t); // E4
          final lfo = (sin(2 * pi * 0.25 * t) + 1.0) / 2.0;
          sample = (tone1 * 0.06 + tone2 * 0.05 + tone3 * 0.04) * (0.8 + 0.2 * lfo);
          break;

        default:
          sample = white * 0.08;
      }
      rawSamples[i] = sample;
    }

    // Circular crossfade head and tail to create seamless infinite loop
    final pcmSamples = Int16List(totalSamples - crossfadeSamples);
    const finalLength = totalSamples - crossfadeSamples;

    for (int i = 0; i < finalLength; i++) {
      double sample = rawSamples[i];
      if (i < crossfadeSamples) {
        // Blend the end of the buffer into the start
        final fade = 0.5 * (1.0 - cos(pi * i / crossfadeSamples));
        final tailIndex = finalLength + i;
        if (tailIndex < totalSamples) {
          sample = rawSamples[i] * fade + rawSamples[tailIndex] * (1.0 - fade);
        }
      }
      pcmSamples[i] = (sample.clamp(-1.0, 1.0) * 32767).toInt();
    }

    return _buildWavBytes(pcmSamples, sampleRate);
  }

  /// Synthesizes acoustic and harmonic alarm sounds.
  Uint8List _generateAlarmWav(String alarmKey) {
    const sampleRate = 22050;
    double durationSeconds = 3.5;
    if (alarmKey == 'digital_beep') durationSeconds = 2.5;
    if (alarmKey == 'gong') durationSeconds = 4.5;

    final totalSamples = (sampleRate * durationSeconds).toInt();
    final pcmSamples = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double sample = 0.0;

      switch (alarmKey) {
        case 'zen_bell':
          // Multi-harmonic singing bowl / bell
          const f = 528.0; // 528Hz Solfeggio frequency
          final decay = exp(-1.2 * t);
          final h1 = sin(2 * pi * f * t) * 0.5;
          final h2 = sin(2 * pi * f * 2.02 * t) * 0.25;
          final h3 = sin(2 * pi * f * 3.01 * t) * 0.12;
          final h4 = sin(2 * pi * f * 4.15 * t) * 0.06;
          sample = (h1 + h2 + h3 + h4) * decay;
          break;

        case 'crystal_chime':
          // Ascending 4-tone crystal chime (C5 -> E5 -> G5 -> C6)
          const notes = [523.25, 659.25, 783.99, 1046.50];
          const noteDuration = 0.35;
          double currentSample = 0.0;

          for (int n = 0; n < notes.length; n++) {
            final noteStart = n * noteDuration;
            if (t >= noteStart) {
              final localT = t - noteStart;
              final decay = exp(-2.2 * localT);
              final noteF = notes[n];
              final s1 = sin(2 * pi * noteF * localT) * 0.4;
              final s2 = sin(2 * pi * noteF * 2.0 * localT) * 0.15;
              final s3 = sin(2 * pi * noteF * 3.0 * localT) * 0.08;
              currentSample += (s1 + s2 + s3) * decay;
            }
          }
          sample = currentSample;
          break;

        case 'digital_beep':
          // 3 rhythmic digital alert pulses (880Hz / 1760Hz)
          final pulseTime = t % 0.6;
          if (pulseTime < 0.2) {
            final env = sin(pi * (pulseTime / 0.2));
            final tone = sin(2 * pi * 987.77 * pulseTime); // B5
            final harmonic = sin(2 * pi * 1975.53 * pulseTime) * 0.3;
            sample = (tone + harmonic) * env * 0.45;
          }
          break;

        case 'gong':
          // Deep resonant temple gong (110Hz + harmonics with long warm shimmer)
          final decay = exp(-0.85 * t);
          final shimmer = 1.0 + 0.08 * sin(2 * pi * 4.5 * t);
          final g1 = sin(2 * pi * 110.0 * t) * 0.55;
          final g2 = sin(2 * pi * 221.5 * t) * 0.25;
          final g3 = sin(2 * pi * 334.0 * t) * 0.15;
          final g4 = sin(2 * pi * 558.0 * t) * 0.08;
          sample = (g1 + g2 + g3 + g4) * decay * shimmer;
          break;

        default:
          final decay = exp(-1.5 * t);
          sample = sin(2 * pi * 440.0 * t) * 0.4 * decay;
      }

      pcmSamples[i] = (sample.clamp(-1.0, 1.0) * 32767).toInt();
    }

    return _buildWavBytes(pcmSamples, sampleRate);
  }

  Uint8List _buildWavBytes(Int16List pcmSamples, int sampleRate) {
    final dataSize = pcmSamples.length * 2;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint32(0, 0x52494646, Endian.big); // 'RIFF'
    header.setUint32(4, fileSize, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // 'WAVE'
    header.setUint32(12, 0x666d7420, Endian.big); // 'fmt '
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // Audio format: 1 (PCM)
    header.setUint16(22, 1, Endian.little); // Channels: 1 (Mono)
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    header.setUint16(32, 2, Endian.little); // Block align
    header.setUint16(34, 16, Endian.little); // Bits per sample
    header.setUint32(36, 0x64617461, Endian.big); // 'data'
    header.setUint32(40, dataSize, Endian.little);

    final bytes = BytesBuilder();
    bytes.add(header.buffer.asUint8List());
    bytes.add(pcmSamples.buffer.asUint8List());
    return bytes.toBytes();
  }
}
