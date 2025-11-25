/// Error types that can occur in Gemini Live API
class LiveError implements Exception {
  final LiveErrorType type;
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const LiveError({
    required this.type,
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  /// Create from WebSocket connection error
  factory LiveError.connectionFailed(dynamic error, [StackTrace? stackTrace]) {
    return LiveError(
      type: LiveErrorType.connectionFailed,
      message: 'Failed to connect to Gemini Live API: $error',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Create from WebSocket disconnection
  factory LiveError.disconnected(String reason) {
    return LiveError(
      type: LiveErrorType.disconnected,
      message: 'Connection closed: $reason',
    );
  }

  /// Create from audio recording error
  factory LiveError.audioRecording(dynamic error, [StackTrace? stackTrace]) {
    return LiveError(
      type: LiveErrorType.audioRecording,
      message: 'Audio recording failed: $error',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Create from audio playback error
  factory LiveError.audioPlayback(dynamic error, [StackTrace? stackTrace]) {
    return LiveError(
      type: LiveErrorType.audioPlayback,
      message: 'Audio playback failed: $error',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Create from message encoding/decoding error
  factory LiveError.messageFormat(dynamic error, [StackTrace? stackTrace]) {
    return LiveError(
      type: LiveErrorType.messageFormat,
      message: 'Message format error: $error',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Create from API response error
  factory LiveError.apiError(String message) {
    return LiveError(
      type: LiveErrorType.apiError,
      message: 'API error: $message',
    );
  }

  /// Create from permission denied
  factory LiveError.permissionDenied(String permission) {
    return LiveError(
      type: LiveErrorType.permissionDenied,
      message: '$permission permission denied',
    );
  }

  /// Create from timeout
  factory LiveError.timeout(String operation) {
    return LiveError(
      type: LiveErrorType.timeout,
      message: 'Timeout waiting for $operation',
    );
  }

  @override
  String toString() => 'LiveError(${type.name}): $message';
}

/// Types of errors that can occur
enum LiveErrorType {
  /// Failed to establish WebSocket connection
  connectionFailed,

  /// WebSocket connection was closed
  disconnected,

  /// Audio recording failed
  audioRecording,

  /// Audio playback failed
  audioPlayback,

  /// Message encoding/decoding failed
  messageFormat,

  /// API returned an error
  apiError,

  /// Required permission was denied
  permissionDenied,

  /// Operation timed out
  timeout,

  /// Unknown error
  unknown;
}
