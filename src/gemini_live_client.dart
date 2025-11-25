import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'callbacks/live_callbacks.dart';
import 'models/live_config.dart';
import 'models/live_error.dart';
import 'models/live_message.dart';
import 'models/live_response.dart';
import 'models/live_state.dart';

/// Gemini Live API WebSocket Client
///
/// This is the core client for interacting with the Gemini Live API.
/// It manages WebSocket connections, message sending/receiving, and state.
///
/// Usage:
/// ```dart
/// final client = GeminiLiveClient(
///   config: LiveConfig(
///     apiKey: 'your-api-key',
///     model: 'models/gemini-2.5-flash-native-audio-preview-09-2025',
///   ),
///   callbacks: LiveCallbacks(
///     onConnected: () => print('Connected!'),
///     onText: (text) => print('AI: $text'),
///     onToolCall: (call) => executeTool(call),
///   ),
/// );
///
/// await client.connect();
/// await client.sendText('Hello, Gemini!');
/// await client.disconnect();
/// ```
class GeminiLiveClient {
  final LiveConfig config;
  final LiveCallbacks callbacks;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  LiveSessionState _state = LiveSessionState.disconnected();

  /// Create a new Gemini Live client
  GeminiLiveClient({
    required this.config,
    required this.callbacks,
  });

  /// Current session state
  LiveSessionState get state => _state;

  /// Check if connected
  bool get isConnected => _state.connectionState.isConnected;

  /// Connect to Gemini Live API
  ///
  /// Establishes WebSocket connection and sends setup message.
  /// Waits for setupComplete response before returning.
  ///
  /// Throws [LiveError] if connection fails or setup times out.
  Future<void> connect() async {
    if (isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Already connected',
      );
    }

    try {
      _updateState(_state.copyWith(
        connectionState: ConnectionState.connecting,
        errorMessage: null,
      ));

      // Create WebSocket connection
      final uri = Uri.parse(config.webSocketUrl);
      _channel = WebSocketChannel.connect(uri);

      // Set up message listener
      final broadcastStream = _channel!.stream.asBroadcastStream();
      _subscription = broadcastStream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      // Send setup message
      final setupMessage = config.toSetupMessage();
      _channel!.sink.add(jsonEncode(setupMessage));

      // Wait for setupComplete response (with timeout)
      final setupCompleted = await _waitForSetupComplete(broadcastStream)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw LiveError.timeout('setup response'),
      );

      if (!setupCompleted) {
        throw LiveError(
          type: LiveErrorType.connectionFailed,
          message: 'Setup failed - no setupComplete received',
        );
      }

      _updateState(LiveSessionState.connected());
      callbacks.onConnected?.call();
    } catch (e, stackTrace) {
      await _cleanup();

      if (e is LiveError) {
        _handleError(e);
        rethrow;
      }

      final error = LiveError.connectionFailed(e, stackTrace);
      _handleError(error);
      throw error;
    }
  }

  /// Wait for setupComplete response
  Future<bool> _waitForSetupComplete(Stream<dynamic> stream) async {
    await for (final message in stream) {
      try {
        final response = LiveResponse.parse(message);
        if (response.type == LiveResponseType.setupComplete) {
          return true;
        }
      } catch (e) {
        // Continue waiting
      }
    }
    return false;
  }

  /// Disconnect from Gemini Live API
  Future<void> disconnect() async {
    if (!isConnected) return;

    await _cleanup();
    _updateState(LiveSessionState.disconnected());
    callbacks.onDisconnected?.call('User requested disconnect');
  }

  /// Send text message
  Future<void> sendText(String text, {bool turnComplete = true}) async {
    if (!isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Not connected',
      );
    }

    final message = ClientContentMessage(
      text: text,
      turnComplete: turnComplete,
    );

    await _sendMessage(message);
  }

  /// Send audio data (PCM format)
  Future<void> sendAudio(List<int> pcmData) async {
    if (!isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Not connected',
      );
    }

    final message = RealtimeInputMessage(
      audioPcm: pcmData as dynamic,
    );

    await _sendMessage(message);
  }

  /// Send tool response
  Future<void> sendToolResponse({
    required String toolCallId,
    required Map<String, dynamic> response,
  }) async {
    if (!isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Not connected',
      );
    }

    final message = ToolResponseMessage(
      toolCallId: toolCallId,
      response: response,
    );

    await _sendMessage(message);
  }

  /// Send tool error
  Future<void> sendToolError({
    required String toolCallId,
    required String errorMessage,
  }) async {
    await sendToolResponse(
      toolCallId: toolCallId,
      response: {'error': errorMessage},
    );
  }

  /// Send end of turn signal
  Future<void> sendEndOfTurn() async {
    if (!isConnected) return;

    final message = EndOfTurnMessage();
    await _sendMessage(message);
  }

  /// Send interrupt signal (stop current generation)
  Future<void> interrupt() async {
    if (!isConnected) return;

    final message = InterruptMessage();
    await _sendMessage(message);
  }

  /// Update response modalities mid-session
  Future<void> updateModalities(List<ResponseModality> modalities) async {
    if (!isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Not connected',
      );
    }

    final message = UpdateConfigMessage(
      responseModalities: modalities.map((m) => m.name).toList(),
    );

    await _sendMessage(message);
  }

  /// Send a custom message
  Future<void> _sendMessage(LiveMessage message) async {
    try {
      final jsonString = message.toJsonString();
      _channel!.sink.add(jsonString);

      _updateState(_state.copyWith(
        messagesSent: _state.messagesSent + 1,
      ));
    } catch (e, stackTrace) {
      final error = LiveError.messageFormat(e, stackTrace);
      _handleError(error);
      rethrow;
    }
  }

  /// Handle incoming WebSocket message
  void _handleMessage(dynamic message) {
    try {
      final response = LiveResponse.parse(message);

      // Update message count
      _updateState(_state.copyWith(
        messagesReceived: _state.messagesReceived + 1,
      ));

      // Trigger raw response callback (for debugging)
      callbacks.onRawResponse?.call(response);

      // Handle specific response types
      switch (response.type) {
        case LiveResponseType.setupComplete:
          // Already handled in connect()
          break;

        case LiveResponseType.serverContent:
          _handleServerContent(response.serverContent!);
          break;

        case LiveResponseType.toolCall:
          callbacks.onToolCall?.call(response.toolCall!);
          break;

        case LiveResponseType.toolCallCancellation:
          final id = response.toolCallCancellationId;
          if (id != null) {
            callbacks.onToolCallCancellation?.call(id);
          }
          break;

        case LiveResponseType.audioPcm:
          final pcmData = response.audioPcm;
          if (pcmData != null) {
            callbacks.onAudioData?.call(pcmData);
          }
          break;

        case LiveResponseType.error:
          final errorData = response.error;
          if (errorData != null) {
            final error = LiveError.apiError(errorData.message);
            _handleError(error);
          }
          break;

        case LiveResponseType.unknown:
          // Ignore unknown responses
          break;
      }
    } catch (e, stackTrace) {
      final error = LiveError.messageFormat(e, stackTrace);
      _handleError(error);
    }
  }

  /// Handle server content response
  void _handleServerContent(ServerContentData content) {
    // Trigger full content callback
    callbacks.onServerContent?.call(content);

    // Extract and trigger text callback
    if (content.text.isNotEmpty) {
      callbacks.onText?.call(content.text, isUser: false);
    }

    // Extract and trigger inline audio callback
    for (final part in content.parts) {
      if (part.inlineData != null) {
        callbacks.onInlineAudio?.call(part.inlineData!);
      }
    }

    // Handle turn complete
    if (content.turnComplete == true) {
      callbacks.onTurnComplete?.call();
    }

    // Handle interrupted
    if (content.interrupted == true) {
      callbacks.onInterrupted?.call();
    }
  }

  /// Handle WebSocket error
  void _handleError(dynamic error) {
    final liveError = error is LiveError
        ? error
        : LiveError(
            type: LiveErrorType.unknown,
            message: error.toString(),
            originalError: error,
          );

    _updateState(LiveSessionState.error(liveError.message));
    callbacks.onError?.call(liveError);
  }

  /// Handle WebSocket disconnect
  void _handleDisconnect() {
    if (_state.connectionState.isConnected) {
      _updateState(LiveSessionState.disconnected());
      callbacks.onDisconnected?.call('Connection closed by server');
    }
  }

  /// Update session state and trigger callbacks
  void _updateState(LiveSessionState newState) {
    final oldConnectionState = _state.connectionState;
    final oldAudioState = _state.audioState;

    _state = newState;

    // Trigger state change callbacks
    callbacks.onSessionStateChanged?.call(newState);

    if (oldConnectionState != newState.connectionState) {
      callbacks.onConnectionStateChanged?.call(newState.connectionState);
    }

    if (oldAudioState != newState.audioState) {
      callbacks.onAudioStateChanged?.call(newState.audioState);
    }
  }

  /// Clean up resources
  Future<void> _cleanup() async {
    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    await disconnect();
  }
}
