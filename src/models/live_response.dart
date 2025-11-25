import 'dart:convert';
import 'dart:typed_data';

/// Response from Gemini Live API
///
/// Handles all response types including setup, content, tool calls, and audio
class LiveResponse {
  final LiveResponseType type;
  final Map<String, dynamic> rawData;

  const LiveResponse({
    required this.type,
    required this.rawData,
  });

  /// Parse response from WebSocket message
  factory LiveResponse.parse(dynamic message) {
    Map<String, dynamic>? jsonData;

    // Handle both text and binary responses
    if (message is String) {
      jsonData = jsonDecode(message) as Map<String, dynamic>;
    } else if (message is List<int>) {
      try {
        final textResponse = utf8.decode(message);
        jsonData = jsonDecode(textResponse) as Map<String, dynamic>;
      } catch (e) {
        // Binary audio data - wrap in audio response
        return LiveResponse(
          type: LiveResponseType.audioPcm,
          rawData: {'data': message},
        );
      }
    }

    if (jsonData == null) {
      throw FormatException('Unable to parse response: $message');
    }

    // Determine response type from JSON structure
    final type = _determineType(jsonData);

    return LiveResponse(
      type: type,
      rawData: jsonData,
    );
  }

  /// Determine response type from JSON structure
  static LiveResponseType _determineType(Map<String, dynamic> json) {
    if (json.containsKey('setupComplete')) {
      return LiveResponseType.setupComplete;
    } else if (json.containsKey('serverContent')) {
      return LiveResponseType.serverContent;
    } else if (json.containsKey('toolCall')) {
      return LiveResponseType.toolCall;
    } else if (json.containsKey('toolCallCancellation')) {
      return LiveResponseType.toolCallCancellation;
    } else if (json.containsKey('error')) {
      return LiveResponseType.error;
    } else {
      return LiveResponseType.unknown;
    }
  }

  /// Get setup complete data
  SetupCompleteData? get setupComplete {
    if (type != LiveResponseType.setupComplete) return null;
    return SetupCompleteData.fromJson(rawData['setupComplete']);
  }

  /// Get server content data
  ServerContentData? get serverContent {
    if (type != LiveResponseType.serverContent) return null;
    return ServerContentData.fromJson(rawData['serverContent']);
  }

  /// Get tool call data
  ToolCallData? get toolCall {
    if (type != LiveResponseType.toolCall) return null;
    return ToolCallData.fromJson(rawData['toolCall']);
  }

  /// Get tool call cancellation ID
  String? get toolCallCancellationId {
    if (type != LiveResponseType.toolCallCancellation) return null;
    return rawData['toolCallCancellation']['id'] as String?;
  }

  /// Get error data
  ErrorData? get error {
    if (type != LiveResponseType.error) return null;
    return ErrorData.fromJson(rawData['error']);
  }

  /// Get raw PCM audio data (if binary response)
  Uint8List? get audioPcm {
    if (type != LiveResponseType.audioPcm) return null;
    final data = rawData['data'];
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    return null;
  }

  @override
  String toString() => 'LiveResponse(type: ${type.name}, data: $rawData)';
}

/// Types of responses from the API
enum LiveResponseType {
  /// Setup completed successfully
  setupComplete,

  /// Server generated content (text/audio)
  serverContent,

  /// Server requesting tool execution
  toolCall,

  /// Server cancelled a tool call
  toolCallCancellation,

  /// Binary PCM audio data
  audioPcm,

  /// Error response
  error,

  /// Unknown response type
  unknown;
}

/// Setup complete response data
class SetupCompleteData {
  const SetupCompleteData();

  factory SetupCompleteData.fromJson(Map<String, dynamic> json) {
    return const SetupCompleteData();
  }

  @override
  String toString() => 'SetupComplete()';
}

/// Server content response data
class ServerContentData {
  final bool? modelTurn;
  final List<ContentPart> parts;
  final bool? turnComplete;
  final bool? interrupted;
  final int? groundingChunkCount;

  const ServerContentData({
    this.modelTurn,
    required this.parts,
    this.turnComplete,
    this.interrupted,
    this.groundingChunkCount,
  });

  factory ServerContentData.fromJson(Map<String, dynamic> json) {
    final partsJson = json['parts'] as List<dynamic>? ?? [];
    final parts = partsJson
        .map((p) => ContentPart.fromJson(p as Map<String, dynamic>))
        .toList();

    return ServerContentData(
      modelTurn: json['modelTurn'] as bool?,
      parts: parts,
      turnComplete: json['turnComplete'] as bool?,
      interrupted: json['interrupted'] as bool?,
      groundingChunkCount: json['grounding_chunk_count'] as int?,
    );
  }

  /// Get all text from parts
  String get text {
    return parts
        .where((p) => p.text != null)
        .map((p) => p.text!)
        .join(' ')
        .trim();
  }

  /// Check if contains audio
  bool get hasAudio => parts.any((p) => p.inlineData != null);

  @override
  String toString() =>
      'ServerContent(turn: $modelTurn, parts: ${parts.length}, complete: $turnComplete)';
}

/// Content part (text or audio)
class ContentPart {
  final String? text;
  final InlineData? inlineData;

  const ContentPart({
    this.text,
    this.inlineData,
  });

  factory ContentPart.fromJson(Map<String, dynamic> json) {
    return ContentPart(
      text: json['text'] as String?,
      inlineData: json['inlineData'] != null
          ? InlineData.fromJson(json['inlineData'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  String toString() {
    if (text != null) return 'Text("${text!.substring(0, text!.length > 50 ? 50 : text!.length)}...")';
    if (inlineData != null) return 'InlineData(${inlineData!.mimeType})';
    return 'EmptyPart';
  }
}

/// Inline data (base64 encoded audio/image)
class InlineData {
  final String mimeType;
  final String data;

  const InlineData({
    required this.mimeType,
    required this.data,
  });

  factory InlineData.fromJson(Map<String, dynamic> json) {
    return InlineData(
      mimeType: json['mimeType'] as String,
      data: json['data'] as String,
    );
  }

  /// Decode base64 data to bytes
  Uint8List get bytes => base64Decode(data);

  @override
  String toString() => 'InlineData($mimeType, ${data.length} chars)';
}

/// Tool call request from server
class ToolCallData {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  const ToolCallData({
    required this.id,
    required this.name,
    required this.args,
  });

  factory ToolCallData.fromJson(Map<String, dynamic> json) {
    final functionCalls = json['functionCalls'] as List<dynamic>? ?? [];
    if (functionCalls.isEmpty) {
      throw FormatException('Tool call missing functionCalls');
    }

    final firstCall = functionCalls[0] as Map<String, dynamic>;

    return ToolCallData(
      id: firstCall['id'] as String? ?? '',
      name: firstCall['name'] as String,
      args: firstCall['args'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  String toString() => 'ToolCall(id: $id, name: $name, args: $args)';
}

/// Error response data
class ErrorData {
  final int? code;
  final String message;
  final String? status;

  const ErrorData({
    this.code,
    required this.message,
    this.status,
  });

  factory ErrorData.fromJson(Map<String, dynamic> json) {
    return ErrorData(
      code: json['code'] as int?,
      message: json['message'] as String? ?? 'Unknown error',
      status: json['status'] as String?,
    );
  }

  @override
  String toString() => 'Error($code: $message)';
}
