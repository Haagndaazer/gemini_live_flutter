import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../models/live_error.dart';

/// Audio playback service for playing AI responses
///
/// Plays audio in the format returned by Gemini Live API:
/// - Format: 16-bit PCM
/// - Sample rate: 24kHz
/// - Channels: Mono
/// - Endianness: Little-endian
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  final List<Uint8List> _audioQueue = [];
  bool _isProcessingQueue = false;
  Completer<void>? _playbackCompleter;

  // Callbacks
  final void Function()? onPlaybackStarted;
  final void Function()? onPlaybackCompleted;
  final void Function(LiveError)? onError;

  AudioPlaybackService({
    this.onPlaybackStarted,
    this.onPlaybackCompleted,
    this.onError,
  }) {
    _setupPlayerListeners();
  }

  /// Set up audio player event listeners
  void _setupPlayerListeners() {
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _playbackCompleter?.complete();
      _playbackCompleter = null;
      onPlaybackCompleted?.call();

      // Continue processing queue if there are more chunks
      if (_audioQueue.isNotEmpty) {
        _processQueue();
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        _isPlaying = false;
      } else if (state == PlayerState.playing) {
        _isPlaying = true;
      }
    });
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Queue audio chunk for playback
  ///
  /// Audio chunks are queued and played sequentially to maintain
  /// smooth playback without gaps or overlaps.
  void queueAudio(Uint8List pcmData) {
    _audioQueue.add(pcmData);
    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  /// Play PCM audio data immediately
  ///
  /// This will interrupt any currently playing audio.
  Future<void> playAudio(Uint8List pcmData) async {
    try {
      await stop();
      _audioQueue.clear();
      await _playPcmData(pcmData);
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Process queued audio chunks
  Future<void> _processQueue() async {
    if (_isProcessingQueue || _audioQueue.isEmpty) return;

    _isProcessingQueue = true;

    try {
      while (_audioQueue.isNotEmpty) {
        final chunk = _audioQueue.removeAt(0);
        await _playPcmData(chunk);
      }
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Play PCM data chunk
  Future<void> _playPcmData(Uint8List pcmData) async {
    if (pcmData.isEmpty) return;

    try {
      onPlaybackStarted?.call();
      _isPlaying = true;

      // Convert PCM to WAV format (audioplayers requires WAV headers)
      final wavData = _addWavHeader(
        pcmData,
        sampleRate: 24000,
        numChannels: 1,
        bitDepth: 16,
      );

      // Create completer to wait for playback completion
      _playbackCompleter = Completer<void>();

      // Play audio from bytes
      await _player.play(BytesSource(wavData));

      // Wait for playback to complete
      await _playbackCompleter?.future;
    } catch (e, stackTrace) {
      _isPlaying = false;
      _playbackCompleter?.completeError(e);
      _playbackCompleter = null;

      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Stop current playback
  Future<void> stop() async {
    if (!_isPlaying) return;

    try {
      await _player.stop();
      _isPlaying = false;
      _playbackCompleter?.complete();
      _playbackCompleter = null;
      onPlaybackCompleted?.call();
    } catch (e, stackTrace) {
      _isPlaying = false;
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
    }
  }

  /// Pause current playback
  Future<void> pause() async {
    if (!_isPlaying) return;

    try {
      await _player.pause();
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Resume paused playback
  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Clear audio queue
  void clearQueue() {
    _audioQueue.clear();
  }

  /// Get current playback position
  Future<Duration?> getPosition() async {
    try {
      return await _player.getCurrentPosition();
    } catch (e) {
      return null;
    }
  }

  /// Get audio duration
  Future<Duration?> getDuration() async {
    try {
      return await _player.getDuration();
    } catch (e) {
      return null;
    }
  }

  /// Set playback volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
    }
  }

  /// Add WAV header to PCM data
  ///
  /// Audioplayers requires WAV format instead of raw PCM.
  /// This helper adds a minimal WAV header to the PCM data.
  Uint8List _addWavHeader(
    Uint8List pcmData, {
    int sampleRate = 24000,
    int numChannels = 1,
    int bitDepth = 16,
  }) {
    final dataSize = pcmData.length;
    final byteRate = sampleRate * numChannels * (bitDepth ~/ 8);
    final blockAlign = numChannels * (bitDepth ~/ 8);

    final header = BytesBuilder();

    // RIFF header
    header.add('RIFF'.codeUnits);
    header.add(_int32Bytes(dataSize + 36)); // File size - 8
    header.add('WAVE'.codeUnits);

    // fmt chunk
    header.add('fmt '.codeUnits);
    header.add(_int32Bytes(16)); // fmt chunk size
    header.add(_int16Bytes(1)); // Audio format (1 = PCM)
    header.add(_int16Bytes(numChannels));
    header.add(_int32Bytes(sampleRate));
    header.add(_int32Bytes(byteRate));
    header.add(_int16Bytes(blockAlign));
    header.add(_int16Bytes(bitDepth));

    // data chunk
    header.add('data'.codeUnits);
    header.add(_int32Bytes(dataSize));
    header.add(pcmData);

    return header.toBytes();
  }

  /// Convert int32 to little-endian bytes
  Uint8List _int32Bytes(int value) {
    return Uint8List(4)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = (value >> 16) & 0xFF
      ..[3] = (value >> 24) & 0xFF;
  }

  /// Convert int16 to little-endian bytes
  Uint8List _int16Bytes(int value) {
    return Uint8List(2)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF;
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    await stop();
    clearQueue();
    await _player.dispose();
  }
}

/// Audio configuration for playback
class AudioPlaybackConfig {
  /// Sample rate in Hz (Gemini Live outputs 24000)
  final int sampleRate;

  /// Number of channels (1 = mono, 2 = stereo)
  final int numChannels;

  /// Bit depth (Gemini Live outputs 16-bit)
  final int bitDepth;

  /// Playback volume (0.0 to 1.0)
  final double volume;

  const AudioPlaybackConfig({
    this.sampleRate = 24000,
    this.numChannels = 1,
    this.bitDepth = 16,
    this.volume = 1.0,
  });

  /// Default config for Gemini Live API
  factory AudioPlaybackConfig.geminiLive() => const AudioPlaybackConfig(
        sampleRate: 24000,
        numChannels: 1,
        bitDepth: 16,
        volume: 1.0,
      );

  @override
  String toString() =>
      'AudioPlaybackConfig($sampleRate Hz, $numChannels ch, $bitDepth-bit, volume: $volume)';
}
