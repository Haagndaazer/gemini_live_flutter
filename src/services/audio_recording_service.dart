import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/live_error.dart';

/// Audio recording service for capturing microphone input
///
/// Captures audio in the format required by Gemini Live API:
/// - Format: 16-bit PCM
/// - Sample rate: 16kHz
/// - Channels: Mono
/// - Endianness: Little-endian
class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  StreamController<Uint8List>? _audioStreamController;
  StreamSubscription<Uint8List>? _recordStreamSubscription;

  // Callbacks
  final void Function()? onRecordingStarted;
  final void Function()? onRecordingStopped;
  final void Function(LiveError)? onError;

  AudioRecordingService({
    this.onRecordingStarted,
    this.onRecordingStopped,
    this.onError,
  });

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Stream of audio data chunks
  Stream<Uint8List>? get audioStream => _audioStreamController?.stream;

  /// Start recording audio
  ///
  /// Returns a stream of PCM audio chunks (16kHz, 16-bit, mono)
  ///
  /// Throws [LiveError] if:
  /// - Microphone permission denied
  /// - Recording already in progress
  /// - Platform not supported
  Future<void> startRecording() async {
    if (_isRecording) {
      throw LiveError(
        type: LiveErrorType.audioRecording,
        message: 'Already recording',
      );
    }

    try {
      // Check and request permission
      final hasPermission = await this.hasPermission();
      if (!hasPermission) {
        final granted = await requestPermission();
        if (!granted) {
          throw LiveError.permissionDenied('Microphone');
        }
      }

      // Create audio stream controller
      _audioStreamController = StreamController<Uint8List>.broadcast();

      // Configure recorder for Gemini Live requirements
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits, // 16-bit PCM
        sampleRate: 16000, // 16kHz
        numChannels: 1, // Mono
        bitRate: 128000,
        autoGain: true, // Enable auto gain for better quality
        echoCancel: true, // Echo cancellation
        noiseSuppress: true, // Noise suppression
      );

      // Check if device supports recording
      final canRecord = await _recorder.hasPermission();
      if (!canRecord) {
        throw LiveError.permissionDenied('Microphone');
      }

      // Start recording stream
      final recordStream = await _recorder.startStream(config);

      // Listen to audio chunks and forward to our controller
      _recordStreamSubscription = recordStream.listen(
        (audioChunk) {
          if (_audioStreamController != null && !_audioStreamController!.isClosed) {
            _audioStreamController!.add(audioChunk);
          }
        },
        onError: (error, stackTrace) {
          final liveError = LiveError.audioRecording(error, stackTrace);
          onError?.call(liveError);
          stopRecording();
        },
        onDone: () {
          if (_isRecording) {
            stopRecording();
          }
        },
      );

      _isRecording = true;
      onRecordingStarted?.call();
    } catch (e, stackTrace) {
      _isRecording = false;
      await _cleanup();

      if (e is LiveError) {
        onError?.call(e);
        rethrow;
      }

      final error = LiveError.audioRecording(e, stackTrace);
      onError?.call(error);
      throw error;
    }
  }

  /// Stop recording audio
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.stop();
      _isRecording = false;

      await _cleanup();
      onRecordingStopped?.call();
    } catch (e, stackTrace) {
      _isRecording = false;
      await _cleanup();

      final error = LiveError.audioRecording(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Pause recording (keeps stream open)
  Future<void> pauseRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.pause();
    } catch (e, stackTrace) {
      final error = LiveError.audioRecording(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Resume recording after pause
  Future<void> resumeRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.resume();
    } catch (e, stackTrace) {
      final error = LiveError.audioRecording(e, stackTrace);
      onError?.call(error);
      rethrow;
    }
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    try {
      final status = await Permission.microphone.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Request microphone permission
  Future<bool> requestPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Check if device supports recording
  Future<bool> isSupported() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      return false;
    }
  }

  /// Get current audio input level (amplitude)
  ///
  /// Returns value between 0.0 (silent) and 1.0 (loud)
  /// Returns null if not recording
  Future<double?> getAmplitude() async {
    if (!_isRecording) return null;

    try {
      final amplitude = await _recorder.getAmplitude();
      // Normalize amplitude to 0.0-1.0 range
      // Amplitude.current is typically -160 (silent) to 0 (loud)
      final normalized = (amplitude.current + 160) / 160;
      return normalized.clamp(0.0, 1.0);
    } catch (e) {
      return null;
    }
  }

  /// Clean up resources
  Future<void> _cleanup() async {
    await _recordStreamSubscription?.cancel();
    _recordStreamSubscription = null;

    if (_audioStreamController != null && !_audioStreamController!.isClosed) {
      await _audioStreamController!.close();
    }
    _audioStreamController = null;
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    await stopRecording();
    await _recorder.dispose();
  }
}

/// Audio configuration for recording
class AudioRecordingConfig {
  /// Sample rate in Hz (Gemini Live requires 16000)
  final int sampleRate;

  /// Number of channels (1 = mono, 2 = stereo)
  /// Gemini Live requires mono
  final int numChannels;

  /// Bit depth (Gemini Live requires 16-bit)
  final int bitDepth;

  /// Enable automatic gain control
  final bool autoGain;

  /// Enable echo cancellation
  final bool echoCancel;

  /// Enable noise suppression
  final bool noiseSuppress;

  const AudioRecordingConfig({
    this.sampleRate = 16000,
    this.numChannels = 1,
    this.bitDepth = 16,
    this.autoGain = true,
    this.echoCancel = true,
    this.noiseSuppress = true,
  });

  /// Default config for Gemini Live API
  factory AudioRecordingConfig.geminiLive() => const AudioRecordingConfig(
        sampleRate: 16000,
        numChannels: 1,
        bitDepth: 16,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

  @override
  String toString() =>
      'AudioRecordingConfig($sampleRate Hz, $numChannels ch, $bitDepth-bit, '
      'autoGain: $autoGain, echo: $echoCancel, noise: $noiseSuppress)';
}
