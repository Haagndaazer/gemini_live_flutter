import 'dart:typed_data';

import '../models/live_error.dart';
import '../models/live_response.dart';
import '../models/live_state.dart';

// Re-export types used in callbacks
export '../models/live_response.dart'
    show SessionResumptionUpdateData, GoAwayData, UsageMetadataData;

/// Callbacks for Gemini Live API events
///
/// This class provides a clean interface for handling all events from the
/// Live API session. All callbacks are optional - implement only what you need.
class LiveCallbacks {
  /// Called when WebSocket connection is established and setup is complete
  final void Function()? onConnected;

  /// Called when WebSocket connection is closed
  final void Function(String reason)? onDisconnected;

  /// Called when connection state changes
  final void Function(ConnectionState state)? onConnectionStateChanged;

  /// Called when audio state changes (idle, listening, processing, speaking)
  final void Function(AudioState state)? onAudioStateChanged;

  /// Called when complete session state changes
  final void Function(LiveSessionState state)? onSessionStateChanged;

  /// Called when an error occurs
  final void Function(LiveError error)? onError;

  /// Called when server sends text content
  ///
  /// For voice mode with transcriptions, this includes both:
  /// - User transcriptions (isUser: true)
  /// - AI responses (isUser: false)
  ///
  /// The [finished] flag indicates whether this transcription segment is complete.
  final void Function(String text, {bool isUser, bool finished})? onText;

  /// Called when server sends audio data (PCM format)
  ///
  /// Audio is 16-bit PCM, 24kHz, mono, little-endian
  final void Function(Uint8List pcmData)? onAudioData;

  /// Called when server sends inline audio (base64 encoded)
  ///
  /// This is audio embedded in serverContent messages
  final void Function(InlineData audioData)? onInlineAudio;

  /// Called when server sends a complete content response
  ///
  /// This is the raw response containing all parts (text + audio)
  final void Function(ServerContentData content)? onServerContent;

  /// Called when server requests tool execution
  ///
  /// The app should execute the tool and send back a ToolResponseMessage
  final void Function(ToolCallData toolCall)? onToolCall;

  /// Called when server cancels a tool call
  final void Function(String toolCallId)? onToolCallCancellation;

  /// Called when a turn is complete (turnComplete: true)
  final void Function()? onTurnComplete;

  /// Called when generation is interrupted
  final void Function()? onInterrupted;

  /// Called when raw response is received (for debugging)
  final void Function(LiveResponse response)? onRawResponse;

  /// Called when audio recording starts
  final void Function()? onRecordingStarted;

  /// Called when audio recording stops
  final void Function()? onRecordingStopped;

  /// Called when audio playback starts
  final void Function()? onPlaybackStarted;

  /// Called when audio playback completes
  final void Function()? onPlaybackCompleted;

  /// Called when session resumption update is received
  final void Function(SessionResumptionUpdateData update)?
      onSessionResumptionUpdate;

  /// Called when server sends GoAway (will disconnect soon)
  final void Function(GoAwayData goAway)? onGoAway;

  /// Called when usage metadata is received from the server
  final void Function(UsageMetadataData usage)? onUsageMetadata;

  const LiveCallbacks({
    this.onConnected,
    this.onDisconnected,
    this.onConnectionStateChanged,
    this.onAudioStateChanged,
    this.onSessionStateChanged,
    this.onError,
    this.onText,
    this.onAudioData,
    this.onInlineAudio,
    this.onServerContent,
    this.onToolCall,
    this.onToolCallCancellation,
    this.onTurnComplete,
    this.onInterrupted,
    this.onRawResponse,
    this.onRecordingStarted,
    this.onRecordingStopped,
    this.onPlaybackStarted,
    this.onPlaybackCompleted,
    this.onSessionResumptionUpdate,
    this.onGoAway,
    this.onUsageMetadata,
  });

  /// Create empty callbacks (no-op)
  factory LiveCallbacks.empty() => const LiveCallbacks();

  /// Create callbacks for debugging (logs all events)
  factory LiveCallbacks.debug({
    void Function(String)? log,
  }) {
    final logger = log ?? print;

    return LiveCallbacks(
      onConnected: () => logger('[LiveAPI] Connected'),
      onDisconnected: (reason) => logger('[LiveAPI] Disconnected: $reason'),
      onConnectionStateChanged: (state) =>
          logger('[LiveAPI] Connection: ${state.name}'),
      onAudioStateChanged: (state) => logger('[LiveAPI] Audio: ${state.name}'),
      onSessionStateChanged: (state) => logger('[LiveAPI] Session: $state'),
      onError: (error) => logger('[LiveAPI] Error: $error'),
      onText: (text, {isUser = false, finished = false}) =>
          logger('[LiveAPI] Text (${isUser ? "user" : "ai"}, finished: $finished): $text'),
      onAudioData: (data) => logger('[LiveAPI] Audio data: ${data.length} bytes'),
      onServerContent: (content) =>
          logger('[LiveAPI] Server content: ${content.parts.length} parts'),
      onToolCall: (toolCall) => logger('[LiveAPI] Tool call: ${toolCall.name}'),
      onToolCallCancellation: (id) =>
          logger('[LiveAPI] Tool cancelled: $id'),
      onTurnComplete: () => logger('[LiveAPI] Turn complete'),
      onInterrupted: () => logger('[LiveAPI] Interrupted'),
      onRawResponse: (response) =>
          logger('[LiveAPI] Raw response: ${response.type.name}'),
      onRecordingStarted: () => logger('[LiveAPI] Recording started'),
      onRecordingStopped: () => logger('[LiveAPI] Recording stopped'),
      onPlaybackStarted: () => logger('[LiveAPI] Playback started'),
      onPlaybackCompleted: () => logger('[LiveAPI] Playback completed'),
    );
  }

  /// Copy with updated callbacks
  LiveCallbacks copyWith({
    void Function()? onConnected,
    void Function(String)? onDisconnected,
    void Function(ConnectionState)? onConnectionStateChanged,
    void Function(AudioState)? onAudioStateChanged,
    void Function(LiveSessionState)? onSessionStateChanged,
    void Function(LiveError)? onError,
    void Function(String, {bool isUser, bool finished})? onText,
    void Function(Uint8List)? onAudioData,
    void Function(InlineData)? onInlineAudio,
    void Function(ServerContentData)? onServerContent,
    void Function(ToolCallData)? onToolCall,
    void Function(String)? onToolCallCancellation,
    void Function()? onTurnComplete,
    void Function()? onInterrupted,
    void Function(LiveResponse)? onRawResponse,
    void Function()? onRecordingStarted,
    void Function()? onRecordingStopped,
    void Function()? onPlaybackStarted,
    void Function()? onPlaybackCompleted,
    void Function(SessionResumptionUpdateData)? onSessionResumptionUpdate,
    void Function(GoAwayData)? onGoAway,
    void Function(UsageMetadataData)? onUsageMetadata,
  }) {
    return LiveCallbacks(
      onConnected: onConnected ?? this.onConnected,
      onDisconnected: onDisconnected ?? this.onDisconnected,
      onConnectionStateChanged:
          onConnectionStateChanged ?? this.onConnectionStateChanged,
      onAudioStateChanged: onAudioStateChanged ?? this.onAudioStateChanged,
      onSessionStateChanged:
          onSessionStateChanged ?? this.onSessionStateChanged,
      onError: onError ?? this.onError,
      onText: onText ?? this.onText,
      onAudioData: onAudioData ?? this.onAudioData,
      onInlineAudio: onInlineAudio ?? this.onInlineAudio,
      onServerContent: onServerContent ?? this.onServerContent,
      onToolCall: onToolCall ?? this.onToolCall,
      onToolCallCancellation:
          onToolCallCancellation ?? this.onToolCallCancellation,
      onTurnComplete: onTurnComplete ?? this.onTurnComplete,
      onInterrupted: onInterrupted ?? this.onInterrupted,
      onRawResponse: onRawResponse ?? this.onRawResponse,
      onRecordingStarted: onRecordingStarted ?? this.onRecordingStarted,
      onRecordingStopped: onRecordingStopped ?? this.onRecordingStopped,
      onPlaybackStarted: onPlaybackStarted ?? this.onPlaybackStarted,
      onPlaybackCompleted: onPlaybackCompleted ?? this.onPlaybackCompleted,
      onSessionResumptionUpdate:
          onSessionResumptionUpdate ?? this.onSessionResumptionUpdate,
      onGoAway: onGoAway ?? this.onGoAway,
      onUsageMetadata: onUsageMetadata ?? this.onUsageMetadata,
    );
  }
}
