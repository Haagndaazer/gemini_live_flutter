import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'callbacks/live_callbacks.dart';
import 'live_socket_io.dart'
    if (dart.library.html) 'live_socket_html.dart' as live_socket;
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
///     model: 'models/gemini-3.1-flash-live-preview',
///   ),
///   callbacks: LiveCallbacks(
///     onConnected: () => print('Connected!'),
///     onText: (text) => print('AI: $text'),
///     onToolCallBatch: (calls) => executeTools(calls),
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

  /// Guards `onDisconnected` to fire at most once per connection attempt —
  /// both the passive `_handleDisconnect` (socket closed by the server) and
  /// the explicit `disconnect()` call can race to deliver it. Reset in
  /// [connect].
  bool _disconnectDelivered = false;

  /// Test seam: swap in a fake channel so lifecycle logic (disconnect
  /// cleanup, close codes, error-state handling) can be driven without a
  /// real WebSocket. Defaults to [live_socket.connectLiveSocket] — a
  /// `pingInterval` keepalive on non-web platforms (WP-5, audit L8), a
  /// plain connect on web (no `dart:html` equivalent knob).
  final WebSocketChannel Function(Uri uri) _channelFactory;

  /// Create a new Gemini Live client
  GeminiLiveClient({
    required this.config,
    required this.callbacks,
    @visibleForTesting
    WebSocketChannel Function(Uri uri)? channelFactory,
  }) : _channelFactory = channelFactory ?? live_socket.connectLiveSocket;

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
      _disconnectDelivered = false;
      _updateState(_state.copyWith(
        connectionState: ConnectionState.connecting,
        errorMessage: null,
      ));

      // Create WebSocket connection
      final uri = Uri.parse(config.webSocketUrl);
      _channel = _channelFactory(uri);

      // Set up message listener
      final broadcastStream = _channel!.stream.asBroadcastStream();
      _subscription = broadcastStream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      // Send setup message
      final setupMessage = config.toSetupMessage();
      final setupJson = jsonEncode(setupMessage);
      debugPrint('📤 Sending setup message: ${setupJson.substring(0, setupJson.length > 500 ? 500 : setupJson.length)}...');
      _channel!.sink.add(setupJson);

      // Wait for setupComplete response (with timeout)
      debugPrint('⏳ Waiting for setupComplete response (10s timeout)...');
      final setupCompleted = await _waitForSetupComplete(broadcastStream)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('❌ Setup timeout - no setupComplete received within 10 seconds');
          return throw LiveError.timeout('setup response');
        },
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
        debugPrint('📥 Received WebSocket message during setup: ${message.toString().substring(0, message.toString().length > 200 ? 200 : message.toString().length)}...');
        final response = LiveResponse.parse(message);
        debugPrint('✅ Parsed response type: ${response.type.name}');

        if (response.type == LiveResponseType.setupComplete) {
          debugPrint('🎉 Setup complete received!');
          return true;
        } else if (response.type == LiveResponseType.error) {
          debugPrint('❌ Error response during setup: ${response.error?.message}');
          throw LiveError(
            type: LiveErrorType.connectionFailed,
            message: 'Setup failed: ${response.error?.message ?? "Unknown error"}',
          );
        }
      } on LiveError {
        // WP-3 (audit L13): the LiveError just thrown above for a genuine
        // setup-error frame must surface immediately with the server's
        // real message — the catch-all below is only for parse hiccups on
        // an unrelated frame shape, and used to swallow this one too,
        // turning a real rejection into a generic 10s timeout.
        //
        // This `on LiveError` selectivity is precise ONLY because
        // `LiveResponse.parse` itself never throws a `LiveError` (just
        // `FormatException`/`TypeError` on malformed JSON) — if parse ever
        // started throwing `LiveError`, that would be rethrown here too
        // and abort setup on what should be a skippable parse hiccup.
        rethrow;
      } catch (e) {
        debugPrint('⚠️ Error parsing setup response: $e');
        // Continue waiting for valid response
      }
    }
    debugPrint('❌ Stream ended without setupComplete');
    return false;
  }

  /// Disconnect from Gemini Live API
  ///
  /// Always tears down the socket/subscription regardless of the current
  /// state (fixes L3: an error state or a mid-connect timeout used to leave
  /// the socket open forever). `onDisconnected` only fires if the connection
  /// was actually active, and at most once per connection attempt (shared
  /// guard with [_handleDisconnect] so a racing server-side close can't
  /// double-deliver).
  Future<void> disconnect() async {
    final wasActive = _state.connectionState.isConnected ||
        _state.connectionState.isConnecting;

    await _cleanup();
    _updateState(LiveSessionState.disconnected());

    if (wasActive && !_disconnectDelivered) {
      _disconnectDelivered = true;
      callbacks.onDisconnected?.call('User requested disconnect');
    }
  }

  /// Send text message via realtimeInput (Gemini 3.1+ compatible).
  Future<void> sendText(String text) async {
    if (!isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Not connected',
      );
    }

    final message = RealtimeTextInputMessage(text: text);
    await _sendMessage(message);
  }

  /// Seed initial conversation history via clientContent.
  /// Only works before the first model turn on Gemini 3.1+.
  Future<void> sendHistorySeed(String text, {bool turnComplete = true}) async {
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

  /// Send a batch of tool responses in one message — the sole way to
  /// answer tool calls (WP-4, audit L4/L10). See [BatchToolResponseMessage]
  /// for why: `functionResponses[]` entries require `name` (previously
  /// omitted), and Gemini 3.1+ expects one combined response per batch of
  /// parallel calls rather than one message per call. Covers a single call
  /// too — pass a one-entry list.
  Future<void> sendToolResponseBatch(
    List<({String id, String name, Map<String, dynamic> response})>
        responses,
  ) async {
    if (!isConnected) {
      throw LiveError(
        type: LiveErrorType.connectionFailed,
        message: 'Not connected',
      );
    }

    final message = BatchToolResponseMessage(responses: responses);
    await _sendMessage(message);
  }

  /// Send end of turn signal
  Future<void> sendEndOfTurn() async {
    if (!isConnected) return;

    final message = EndOfTurnMessage();
    await _sendMessage(message);
  }

  /// Send audio stream end signal (flush cached audio)
  Future<void> sendAudioStreamEnd() async {
    if (!isConnected) return;

    final message = AudioStreamEndMessage();
    await _sendMessage(message);
  }

  /// WP-5 Option A (manual VAD, config-plumbing-only for now — see
  /// AutomaticActivityDetectionConfig doc): marks the start of a user
  /// utterance. Only legal when automaticActivityDetection.disabled=true.
  Future<void> sendActivityStart() async {
    if (!isConnected) return;

    final message = ActivityStartMessage();
    await _sendMessage(message);
  }

  /// WP-5 Option A counterpart to [sendActivityStart].
  Future<void> sendActivityEnd() async {
    if (!isConnected) return;

    final message = ActivityEndMessage();
    await _sendMessage(message);
  }

  /// Send interrupt signal (stop current generation).
  /// On 3.1+, uses audioStreamEnd to trigger implicit interruption
  /// since the explicit 'interrupt' field does not exist in the API spec.
  Future<void> interrupt() async {
    if (!isConnected) return;

    final message = AudioStreamEndMessage();
    await _sendMessage(message);
  }

  /// Update response modalities mid-session.
  /// NOTE: Not supported on Gemini 3.1+. Use session resumption to change config.
  @Deprecated('Mid-session config updates are not supported on Gemini 3.1+')
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
      final preview = jsonString.length > 200
          ? '${jsonString.substring(0, 200)}…'
          : jsonString;
      debugPrint(
          '📤 [LiveClient] send ${message.runtimeType} ${jsonString.length}B: $preview');
      _channel!.sink.add(jsonString);

      _updateState(_state.copyWith(
        messagesSent: _state.messagesSent + 1,
      ));
    } catch (e, stackTrace) {
      debugPrint('❌ [LiveClient] send ${message.runtimeType} failed: $e');
      final error = LiveError.messageFormat(e, stackTrace);
      _handleError(error);
      rethrow;
    }
  }

  /// Handle incoming WebSocket message
  ///
  /// WP-3 (audit L2): parsing and dispatch are separate failure domains.
  /// A malformed frame is reported via `onError` WITHOUT touching
  /// connection state — only a real transport event (the stream's own
  /// onError/onDone) or an explicit disconnect may change that. Each
  /// dispatched callback is individually guarded ([_safeDispatch]) so an
  /// exception thrown by app code (onText, onToolCall, a DB write inside a
  /// handler, ...) can never poison the client into believing the
  /// connection died — pre-fix, ANY such exception here routed to
  /// `_handleError`, which set state to `error` and made every subsequent
  /// send throw `'Not connected'` even though the socket was fine.
  void _handleMessage(dynamic message) {
    final LiveResponse response;
    try {
      response = LiveResponse.parse(message);
    } catch (e, stackTrace) {
      debugPrint('❌ [LiveClient] failed to parse message: $e');
      _safeDispatch(
        'onError (parse failure)',
        () => callbacks.onError?.call(LiveError.messageFormat(e, stackTrace)),
      );
      return;
    }

    // Update message count
    _updateState(_state.copyWith(
      messagesReceived: _state.messagesReceived + 1,
    ));

    // Trigger raw response callback (for debugging)
    _safeDispatch(
        'onRawResponse', () => callbacks.onRawResponse?.call(response));

    // WP-7 (audit L12): usageMetadata can arrive standalone or alongside
    // another top-level field, so it's checked independently of — and
    // before — the type switch below, not as one of its cases.
    final usage = _safeGet('usageMetadata', () => response.usageMetadata);
    if (usage != null) {
      _safeDispatch('onUsageMetadata', () => callbacks.onUsageMetadata?.call(usage));
    }

    // Handle specific response types
    switch (response.type) {
      case LiveResponseType.setupComplete:
        // Already handled in connect()
        break;

      case LiveResponseType.serverContent:
        final content =
            _safeGet('serverContent', () => response.serverContent);
        if (content != null) _handleServerContent(content);
        break;

      case LiveResponseType.toolCall:
        // Dispatch all tool calls in the batch (Gemini 3.1+ can send multiple)
        // WP-4 (audit L10): dispatch the WHOLE batch in one callback — the
        // app must answer it with one combined BatchToolResponseMessage,
        // not one message per call.
        final toolCalls = _safeGet('toolCall', () => response.toolCalls);
        if (toolCalls != null && toolCalls.isNotEmpty) {
          _safeDispatch('onToolCallBatch',
              () => callbacks.onToolCallBatch?.call(toolCalls));
        }
        break;

      case LiveResponseType.toolCallCancellation:
        final ids = _safeGet(
            'toolCallCancellation', () => response.toolCallCancellationIds);
        if (ids != null) {
          for (final id in ids) {
            _safeDispatch('onToolCallCancellation',
                () => callbacks.onToolCallCancellation?.call(id));
          }
        }
        break;

      case LiveResponseType.audioPcm:
        final pcmData = _safeGet('audioPcm', () => response.audioPcm);
        if (pcmData != null) {
          _safeDispatch(
              'onAudioData', () => callbacks.onAudioData?.call(pcmData));
        }
        break;

      case LiveResponseType.error:
        final errorData = _safeGet('error', () => response.error);
        if (errorData != null) {
          // Transport-fatal: an explicit error frame FROM THE SERVER is a
          // genuine error, unlike a local parse/callback failure — state
          // change here is correct, not the bug this WP fixes.
          _handleError(LiveError.apiError(errorData.message));
        }
        break;

      case LiveResponseType.sessionResumptionUpdate:
        final update = _safeGet('sessionResumptionUpdate',
            () => response.sessionResumptionUpdate);
        if (update != null) {
          _safeDispatch('onSessionResumptionUpdate',
              () => callbacks.onSessionResumptionUpdate?.call(update));
        }
        break;

      case LiveResponseType.goAway:
        final goAway = _safeGet('goAway', () => response.goAway);
        if (goAway != null) {
          _safeDispatch('onGoAway', () => callbacks.onGoAway?.call(goAway));
        }
        break;

      case LiveResponseType.unknown:
        // Ignore unknown responses
        break;
    }
  }

  /// WP-3 addendum (adversarial review of the original fix): `LiveResponse
  /// .parse` only decodes the JSON envelope — the real nested parsing
  /// happens in these per-type getters (`ServerContentData.fromJson`,
  /// `ToolCallData.allFromJson`, `GoAwayData.fromJson`, ...), which throw
  /// on a JSON-valid-but-structurally-invalid frame (`{"serverContent":
  /// null}`, `{"toolCall": {}}` with no functionCalls, `{"goAway": null}`).
  /// Those calls used to sit unguarded between the parse try/catch and
  /// dispatch, so a throw there escaped as an UNCAUGHT exception on the
  /// subscription's synchronous onData callback (worse than pre-fix, which
  /// at least routed it through onError). Treats a getter throw exactly
  /// like a parse failure: reported via onError, connection state
  /// untouched.
  T? _safeGet<T>(String label, T? Function() getter) {
    try {
      return getter();
    } catch (e, stackTrace) {
      debugPrint(
          '❌ [LiveClient] $label: structurally invalid frame: $e');
      _safeDispatch(
        'onError ($label structural failure)',
        () => callbacks.onError?.call(LiveError.messageFormat(e, stackTrace)),
      );
      return null;
    }
  }

  /// Runs [action], logging and swallowing any exception instead of
  /// letting it propagate (WP-3, audit L2) — see [_handleMessage].
  void _safeDispatch(String label, void Function() action) {
    try {
      action();
    } catch (e, stackTrace) {
      debugPrint('❌ [LiveClient] $label threw, ignoring: $e\n$stackTrace');
    }
  }

  /// Handle server content response
  void _handleServerContent(ServerContentData content) {
    // Trigger full content callback
    _safeDispatch(
        'onServerContent', () => callbacks.onServerContent?.call(content));

    // Extract and trigger user transcription callback
    if (content.inputTranscription != null &&
        content.inputTranscription!.text.isNotEmpty) {
      _safeDispatch(
        'onText (user transcription)',
        () => callbacks.onText?.call(
          content.inputTranscription!.text,
          isUser: true,
          finished: content.inputTranscription!.finished ?? false,
        ),
      );
    }

    // Extract and trigger AI output-transcription callback. Kept on its OWN
    // callback (never onText): a turn can carry BOTH this and modelTurn text,
    // and forwarding both into onText rendered the turn twice. The consumer
    // chooses exactly one AI text source per configured response modality.
    if (content.outputTranscription != null &&
        content.outputTranscription!.text.isNotEmpty) {
      _safeDispatch(
        'onOutputTranscription (ai transcription)',
        () => callbacks.onOutputTranscription?.call(
          content.outputTranscription!.text,
          finished: content.outputTranscription!.finished ?? false,
        ),
      );
    }

    // Extract and trigger text callback (from modelTurn)
    if (content.text.isNotEmpty) {
      _safeDispatch(
        'onText (modelTurn)',
        () => callbacks.onText?.call(content.text, isUser: false, finished: false),
      );
    }

    // Extract and trigger inline audio callback
    for (final part in content.parts) {
      if (part.inlineData != null) {
        _safeDispatch('onInlineAudio',
            () => callbacks.onInlineAudio?.call(part.inlineData!));
      }
    }

    // Handle turn complete
    if (content.turnComplete == true) {
      _safeDispatch('onTurnComplete', () => callbacks.onTurnComplete?.call());
    }

    // Handle interrupted
    if (content.interrupted == true) {
      _safeDispatch('onInterrupted', () => callbacks.onInterrupted?.call());
    }

    // Handle generation complete (Gemini 3.1+)
    if (content.generationComplete == true) {
      _safeDispatch(
          'onGenerationComplete', () => callbacks.onGenerationComplete?.call());
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
    _safeDispatch('onError', () => callbacks.onError?.call(liveError));
  }

  /// Handle WebSocket disconnect (the stream's `onDone`)
  ///
  /// Always delivers `onDisconnected` — including from an `error` state —
  /// because the transport is gone either way and the teacher must always
  /// learn that (fixes L2/L7: a callback exception used to leave the
  /// service believing the socket was still up). Close code/reason are
  /// captured before `_channel` is nulled out and folded into the reason
  /// string so `classifyErrorText` has real signal instead of a generic
  /// message. Guarded to fire at most once per connection (shared with
  /// [disconnect]).
  void _handleDisconnect() {
    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;
    final reason =
        'Connection closed by server (code=$closeCode, reason=$closeReason)';

    _updateState(LiveSessionState.disconnected());

    if (!_disconnectDelivered) {
      _disconnectDelivered = true;
      callbacks.onDisconnected?.call(reason);
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
