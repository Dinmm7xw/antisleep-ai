import 'dart:typed_data';

/// Synthesized WAV Siren Generator (In-Memory PCM WAV for AudioPlayer)
/// Ensures loud 880Hz/440Hz siren works 100% offline with zero missing assets.
class SirenWavGenerator {
  static Uint8List? _cachedWavBytes;

  static Uint8List generateDualToneSirenWav() {
    if (_cachedWavBytes != null) return _cachedWavBytes!;

    const int sampleRate = 22050;
    const int durationSeconds = 2;
    const int numSamples = sampleRate * durationSeconds;
    final ByteData data = ByteData(44 + numSamples * 2);

    // RIFF header
    _writeString(data, 0, 'RIFF');
    data.setUint32(4, 36 + numSamples * 2, Endian.little);
    _writeString(data, 8, 'WAVE');
    _writeString(data, 12, 'fmt ');
    data.setUint32(16, 16, Endian.little); // PCM chunk size
    data.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    data.setUint16(22, 1, Endian.little); // NumChannels = 1 (Mono)
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    data.setUint16(32, 2, Endian.little); // BlockAlign
    data.setUint16(34, 16, Endian.little); // BitsPerSample = 16
    _writeString(data, 36, 'data');
    data.setUint32(40, numSamples * 2, Endian.little);

    // Generate high-gain alternating 880Hz / 440Hz square-wave emergency siren
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double freq = ((t * 3.5).floor() % 2 == 0) ? 880.0 : 440.0;
      final double phase = (t * freq) % 1.0;
      final int sample = phase < 0.5 ? 28000 : -28000;
      data.setInt16(44 + i * 2, sample, Endian.little);
    }

    _cachedWavBytes = data.buffer.asUint8List();
    return _cachedWavBytes!;
  }

  static void _writeString(ByteData data, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}

