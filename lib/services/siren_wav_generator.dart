import 'dart:math' as math;
import 'dart:typed_data';

/// Advanced Synthesized Acoustic & Neuro-Stimulation Engine.
/// Generates 100% offline PCM WAV audio in memory for instant zero-latency playback.
class SirenWavGenerator {
  static Uint8List? _cachedSirenWavBytes;
  static Uint8List? _cachedGamma40HzWavBytes;
  static Uint8List? _cachedPulseAlertWavBytes;

  /// Mode 1: High-Gain Dual-Tone 880Hz / 440Hz Square Wave Emergency Siren.
  static Uint8List generateDualToneSirenWav() {
    if (_cachedSirenWavBytes != null) return _cachedSirenWavBytes!;

    const int sampleRate = 22050;
    const int durationSeconds = 2;
    const int numSamples = sampleRate * durationSeconds;
    final ByteData data = ByteData(44 + numSamples * 2);

    _writeWavHeader(
      data: data,
      sampleRate: sampleRate,
      numChannels: 1,
      bitsPerSample: 16,
      numSamples: numSamples,
    );

    // High-gain alternating 880Hz / 440Hz square-wave siren
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double freq = ((t * 3.5).floor() % 2 == 0) ? 880.0 : 440.0;
      final double phase = (t * freq) % 1.0;
      final int sample = phase < 0.5 ? 28000 : -28000;
      data.setInt16(44 + i * 2, sample, Endian.little);
    }

    _cachedSirenWavBytes = data.buffer.asUint8List();
    return _cachedSirenWavBytes!;
  }

  /// Mode 2: 40Hz Gamma Binaural Neuro-Stimulation Wave (Stereo).
  /// Left ear receives 400Hz, Right ear receives 440Hz -> creates a 40Hz perceptual
  /// binaural beat in the auditory cortex, synchronizing gamma brainwaves to restore alertness.
  static Uint8List generateBinauralGamma40HzWav() {
    if (_cachedGamma40HzWavBytes != null) return _cachedGamma40HzWavBytes!;

    const int sampleRate = 22050;
    const int durationSeconds = 2;
    const int numFrames = sampleRate * durationSeconds;
    const int numChannels = 2; // Stereo for true binaural separation
    const int byteLength = 44 + numFrames * numChannels * 2;
    final ByteData data = ByteData(byteLength);

    _writeWavHeader(
      data: data,
      sampleRate: sampleRate,
      numChannels: numChannels,
      bitsPerSample: 16,
      numSamples: numFrames * numChannels,
    );

    const double freqLeft = 400.0; // Carrier
    const double freqRight = 440.0; // 400 + 40Hz Gamma delta
    const double gammaModFreq = 40.0; // 40Hz Gamma envelope modulation

    int offset = 44;
    for (int i = 0; i < numFrames; i++) {
      final double t = i / sampleRate;

      // 40Hz amplitude modulation envelope (0.25 .. 1.0) for acoustic stimulation
      final double env = 0.625 + 0.375 * math.sin(2.0 * math.pi * gammaModFreq * t);

      // Left Channel (400Hz sine wave)
      final double sampleL = math.sin(2.0 * math.pi * freqLeft * t) * env;
      final int intSampleL = (sampleL * 26000).clamp(-32000, 32000).toInt();

      // Right Channel (440Hz sine wave)
      final double sampleR = math.sin(2.0 * math.pi * freqRight * t) * env;
      final int intSampleR = (sampleR * 26000).clamp(-32000, 32000).toInt();

      data.setInt16(offset, intSampleL, Endian.little);
      data.setInt16(offset + 2, intSampleR, Endian.little);
      offset += 4;
    }

    _cachedGamma40HzWavBytes = data.buffer.asUint8List();
    return _cachedGamma40HzWavBytes!;
  }

  /// Mode 3: Dynamic Accelerating Pulse Rhythm (Psychoacoustic Intercept).
  /// Produces rhythmic staccato pulses accelerating from 100 BPM to 150 BPM.
  static Uint8List generateAcceleratingPulseWav() {
    if (_cachedPulseAlertWavBytes != null) return _cachedPulseAlertWavBytes!;

    const int sampleRate = 22050;
    const int durationSeconds = 2;
    const int numSamples = sampleRate * durationSeconds;
    final ByteData data = ByteData(44 + numSamples * 2);

    _writeWavHeader(
      data: data,
      sampleRate: sampleRate,
      numChannels: 1,
      bitsPerSample: 16,
      numSamples: numSamples,
    );

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      // Accelerating pulse frequency: 2Hz (120 BPM) up to 3.5Hz (210 BPM)
      final double pulseRate = 2.2 + (t * 0.7);
      final double pulsePhase = (t * pulseRate) % 1.0;
      final bool soundOn = pulsePhase < 0.6;

      if (!soundOn) {
        data.setInt16(44 + i * 2, 0, Endian.little);
      } else {
        // Dual-tone harmonic 900Hz + 1200Hz
        final double s1 = math.sin(2.0 * math.pi * 900.0 * t);
        final double s2 = math.sin(2.0 * math.pi * 1200.0 * t) * 0.4;
        final int val = ((s1 + s2) * 22000).clamp(-32000, 32000).toInt();
        data.setInt16(44 + i * 2, val, Endian.little);
      }
    }

    _cachedPulseAlertWavBytes = data.buffer.asUint8List();
    return _cachedPulseAlertWavBytes!;
  }

  static void _writeWavHeader({
    required ByteData data,
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
    required int numSamples,
  }) {
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int subChunk2Size = numSamples * (bitsPerSample ~/ 8);

    // RIFF header
    _writeString(data, 0, 'RIFF');
    data.setUint32(4, 36 + subChunk2Size, Endian.little);
    _writeString(data, 8, 'WAVE');
    _writeString(data, 12, 'fmt ');
    data.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    data.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    _writeString(data, 36, 'data');
    data.setUint32(40, subChunk2Size, Endian.little);
  }

  static void _writeString(ByteData data, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
