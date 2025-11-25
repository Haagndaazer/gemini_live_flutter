/// Connection state for Gemini Live API
enum ConnectionState {
  /// Not connected
  disconnected,

  /// Attempting to connect
  connecting,

  /// Connected and ready
  connected,

  /// Connection error occurred
  error;

  bool get isConnected => this == ConnectionState.connected;
  bool get isDisconnected => this == ConnectionState.disconnected;
  bool get isConnecting => this == ConnectionState.connecting;
  bool get hasError => this == ConnectionState.error;
}

/// Audio processing state
enum AudioState {
  /// No audio activity
  idle,

  /// Listening to user input
  listening,

  /// Processing audio (transcribing/analyzing)
  processing,

  /// AI is speaking/playing response
  speaking;

  bool get isIdle => this == AudioState.idle;
  bool get isListening => this == AudioState.listening;
  bool get isProcessing => this == AudioState.processing;
  bool get isSpeaking => this == AudioState.speaking;
}

/// Overall session state combining connection and audio states
class LiveSessionState {
  final ConnectionState connectionState;
  final AudioState audioState;
  final String? errorMessage;
  final DateTime? connectedAt;
  final int messagesReceived;
  final int messagesSent;

  const LiveSessionState({
    required this.connectionState,
    this.audioState = AudioState.idle,
    this.errorMessage,
    this.connectedAt,
    this.messagesReceived = 0,
    this.messagesSent = 0,
  });

  /// Initial disconnected state
  factory LiveSessionState.disconnected() => const LiveSessionState(
        connectionState: ConnectionState.disconnected,
      );

  /// Connected state
  factory LiveSessionState.connected() => LiveSessionState(
        connectionState: ConnectionState.connected,
        connectedAt: DateTime.now(),
      );

  /// Error state with message
  factory LiveSessionState.error(String message) => LiveSessionState(
        connectionState: ConnectionState.error,
        errorMessage: message,
      );

  /// Copy with new values
  LiveSessionState copyWith({
    ConnectionState? connectionState,
    AudioState? audioState,
    String? errorMessage,
    DateTime? connectedAt,
    int? messagesReceived,
    int? messagesSent,
  }) {
    return LiveSessionState(
      connectionState: connectionState ?? this.connectionState,
      audioState: audioState ?? this.audioState,
      errorMessage: errorMessage ?? this.errorMessage,
      connectedAt: connectedAt ?? this.connectedAt,
      messagesReceived: messagesReceived ?? this.messagesReceived,
      messagesSent: messagesSent ?? this.messagesSent,
    );
  }

  /// Get duration since connection (if connected)
  Duration? get connectionDuration {
    if (connectedAt == null) return null;
    return DateTime.now().difference(connectedAt!);
  }

  /// Check if in a good state to send messages
  bool get canSendMessages =>
      connectionState.isConnected && !connectionState.hasError;

  @override
  String toString() => 'LiveSessionState('
      'connection: ${connectionState.name}, '
      'audio: ${audioState.name}, '
      'error: $errorMessage, '
      'messages: $messagesSent sent / $messagesReceived received'
      ')';
}
