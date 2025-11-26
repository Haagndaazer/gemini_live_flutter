import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import '../models/live_error.dart';

/// Audio playback service for playing AI responses using real-time PCM streaming
///
/// Plays audio in the format returned by Gemini Live API:
/// - Format: 16-bit PCM
/// - Sample rate: 24kHz
/// - Channels: Mono
/// - Endianness: Little-endian
///
/// Uses flutter_pcm_sound for gapless streaming playback following Google's
/// official Gemini Live pattern: queue-based buffering with event-driven feeding.
class AudioPlaybackService {
  // Audio queue for incoming chunks
  final Queue<Uint8List> _audioQueue = Queue();
  bool _isPlaying = false;
  bool _isInitialized = false;

  // Pre-buffering configuration (Google recommends 3-5 chunks = ~120-200ms)
  static const int preBufferChunks = 4;  // 4 chunks × 40ms = ~160ms latency

  // Callbacks
  final void Function()? onPlaybackStarted;
  final void Function()? onPlaybackCompleted;
  final void Function(LiveError)? onError;

  AudioPlaybackService({
    this.onPlaybackStarted,
    this.onPlaybackCompleted,
    this.onError,
  });

  /// Initialize flutter_pcm_sound with Gemini Live audio specifications
  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      // Disable verbose PCM logging
      FlutterPcmSound.setLogLevel(LogLevel.none);

      await FlutterPcmSound.setup(
        sampleRate: 24000,  // Gemini outputs at 24kHz
        channelCount: 1,     // Mono
      );

      // Set feed threshold - callback triggers when buffer falls below this
      // 4800 frames = 200ms at 24kHz (provides smooth playback buffer)
      await FlutterPcmSound.setFeedThreshold(4800);

      // Set callback for when more audio is needed
      FlutterPcmSound.setFeedCallback(_onFeedNeeded);

      _isInitialized = true;
    } catch (e, stackTrace) {
      _isInitialized = false;
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Called by flutter_pcm_sound when buffer needs more data
  void _onFeedNeeded(int remainingFrames) {
    if (_audioQueue.isNotEmpty) {
      final chunk = _audioQueue.removeFirst();
      _feedChunk(chunk);
    } else {
      _handlePlaybackComplete();
    }
  }

  /// Feed a single audio chunk to the player
  void _feedChunk(Uint8List pcmData) {
    if (pcmData.isEmpty) return;

    try {
      FlutterPcmSound.feed(
        PcmArrayInt16.fromList(
          Int16List.view(pcmData.buffer),
        ),
      );
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
    }
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Queue audio chunk for playback (following Google's pattern)
  ///
  /// Chunks are queued and playback starts once we have enough buffered
  /// to prevent stuttering (pre-buffer threshold).
  void queueAudio(Uint8List pcmData) {
    if (pcmData.isEmpty) return;

    _audioQueue.add(pcmData);

    // Start playback if we've reached pre-buffer threshold
    if (!_isPlaying && _audioQueue.length >= preBufferChunks) {
      _startPlayback();
    }
  }

  /// Start playback with queued chunks
  Future<void> _startPlayback() async {
    if (_isPlaying) return;

    try {
      // Initialize on first use
      if (!_isInitialized) {
        await _initialize();
      }

      _isPlaying = true;
      onPlaybackStarted?.call();

      FlutterPcmSound.start();  // Returns bool, not Future

      // Feed initial chunks to fill the buffer
      while (_audioQueue.isNotEmpty) {
        final chunk = _audioQueue.removeFirst();
        _feedChunk(chunk);
      }
    } catch (e, stackTrace) {
      _isPlaying = false;
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Flush remaining buffer (call when audio stream ends)
  ///
  /// This triggers playback of any queued chunks even if pre-buffer
  /// threshold hasn't been reached.
  void flushBuffer() {
    if (_audioQueue.isEmpty) return;

    if (!_isPlaying) {
      _startPlayback();
    }
  }

  /// Play PCM audio data immediately (for one-off playback)
  ///
  /// This will clear the queue and play the provided audio.
  Future<void> playAudio(Uint8List pcmData) async {
    try {
      await stop();
      _audioQueue.clear();
      _audioQueue.add(pcmData);
      await _startPlayback();
    } catch (e, stackTrace) {
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Stop current playback and clear queue
  Future<void> stop() async {
    if (!_isPlaying && _audioQueue.isEmpty) return;

    try {
      // Clear queue to stop feeding audio (playback stops naturally when buffer drains)
      _audioQueue.clear();

      // Optional: Release resources to immediately stop playback
      if (_isInitialized) {
        await FlutterPcmSound.release();
        _isInitialized = false;  // Will need to re-initialize on next playback
      }

      _isPlaying = false;
      onPlaybackCompleted?.call();
    } catch (e, stackTrace) {
      _isPlaying = false;
      final error = LiveError.audioPlayback(e, stackTrace);
      onError?.call(error);
    }
  }

  /// Clear audio queue without stopping playback
  void clearQueue() {
    _audioQueue.clear();
  }

  /// Handle playback completion
  void _handlePlaybackComplete() {
    if (!_isPlaying) return;
    _isPlaying = false;
    onPlaybackCompleted?.call();
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    await stop();
    clearQueue();

    if (_isInitialized) {
      await FlutterPcmSound.release();
      _isInitialized = false;
    }
  }
}

/// Audio configuration for playback (for reference)
class AudioPlaybackConfig {
  /// Sample rate in Hz (Gemini Live outputs 24000)
  final int sampleRate;

  /// Number of channels (1 = mono, 2 = stereo)
  final int numChannels;

  /// Bit depth (Gemini Live outputs 16-bit)
  final int bitDepth;

  /// Playback volume (0.0 to 1.0)
  final double volume;

  /// Pre-buffer size in chunks (Google recommends 3-5)
  final int preBufferChunks;

  const AudioPlaybackConfig({
    this.sampleRate = 24000,
    this.numChannels = 1,
    this.bitDepth = 16,
    this.volume = 1.0,
    this.preBufferChunks = 4,
  });

  /// Default config for Gemini Live API
  factory AudioPlaybackConfig.geminiLive() => const AudioPlaybackConfig(
        sampleRate: 24000,
        numChannels: 1,
        bitDepth: 16,
        volume: 1.0,
        preBufferChunks: 4,
      );

  @override
  String toString() =>
      'AudioPlaybackConfig($sampleRate Hz, $numChannels ch, $bitDepth-bit, volume: $volume, preBuffer: $preBufferChunks chunks)';
}
