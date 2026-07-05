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
    } else if (json.containsKey('sessionResumptionUpdate')) {
      return LiveResponseType.sessionResumptionUpdate;
    } else if (json.containsKey('goAway')) {
      return LiveResponseType.goAway;
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

  /// Get first tool call data (backward compat)
  ToolCallData? get toolCall {
    if (type != LiveResponseType.toolCall) return null;
    return ToolCallData.fromJson(rawData['toolCall']);
  }

  /// Get all tool calls from a batched response (Gemini 3.1+)
  List<ToolCallData>? get toolCalls {
    if (type != LiveResponseType.toolCall) return null;
    return ToolCallData.allFromJson(rawData['toolCall']);
  }

  /// Get tool call cancellation ID (single, backward compat)
  String? get toolCallCancellationId {
    if (type != LiveResponseType.toolCallCancellation) return null;
    final data = rawData['toolCallCancellation'] as Map<String, dynamic>;
    return data['id'] as String?;
  }

  /// Get all tool call cancellation IDs (supports batched cancellations on 3.1+)
  List<String>? get toolCallCancellationIds {
    if (type != LiveResponseType.toolCallCancellation) return null;
    final data = rawData['toolCallCancellation'] as Map<String, dynamic>;
    // Support both single 'id' (2.5) and plural 'ids' (3.1)
    if (data['ids'] != null) return List<String>.from(data['ids'] as List);
    if (data['id'] != null) return [data['id'] as String];
    return null;
  }

  /// Get error data
  ErrorData? get error {
    if (type != LiveResponseType.error) return null;
    return ErrorData.fromJson(rawData['error']);
  }

  /// Get session resumption update data
  SessionResumptionUpdateData? get sessionResumptionUpdate {
    if (type != LiveResponseType.sessionResumptionUpdate) return null;
    return SessionResumptionUpdateData.fromJson(
        rawData['sessionResumptionUpdate'] as Map<String, dynamic>);
  }

  /// Get go away data
  GoAwayData? get goAway {
    if (type != LiveResponseType.goAway) return null;
    return GoAwayData.fromJson(rawData['goAway'] as Map<String, dynamic>);
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

  /// Get usage metadata (WP-7, audit L12) — parsed independently of [type]
  /// /[_determineType], since `usageMetadata` can arrive standalone or
  /// alongside another top-level field in the same server message (verified
  /// against ai.google.dev/api/live: it's documented as its own top-level
  /// field on `BidiGenerateContentServerMessage`, not scoped under any of
  /// the other response types this class switches on).
  UsageMetadataData? get usageMetadata {
    final raw = rawData['usageMetadata'];
    if (raw == null) return null;
    return UsageMetadataData.fromJson(raw as Map<String, dynamic>);
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

  /// Session resumption update
  sessionResumptionUpdate,

  /// GoAway — server will disconnect soon
  goAway,

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
  final ModelTurn? modelTurn;
  final bool? turnComplete;
  final bool? interrupted;
  final bool? generationComplete;
  final int? groundingChunkCount;
  final TranscriptionData? inputTranscription;
  final TranscriptionData? outputTranscription;

  const ServerContentData({
    this.modelTurn,
    this.turnComplete,
    this.interrupted,
    this.generationComplete,
    this.groundingChunkCount,
    this.inputTranscription,
    this.outputTranscription,
  });

  factory ServerContentData.fromJson(Map<String, dynamic> json) {
    return ServerContentData(
      modelTurn: json['modelTurn'] != null
          ? ModelTurn.fromJson(json['modelTurn'] as Map<String, dynamic>)
          : null,
      turnComplete: json['turnComplete'] as bool?,
      interrupted: json['interrupted'] as bool?,
      generationComplete: json['generationComplete'] as bool?,
      groundingChunkCount: json['grounding_chunk_count'] as int?,
      inputTranscription: json['inputTranscription'] != null
          ? TranscriptionData.fromJson(
              json['inputTranscription'] as Map<String, dynamic>)
          : null,
      outputTranscription: json['outputTranscription'] != null
          ? TranscriptionData.fromJson(
              json['outputTranscription'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Get parts from modelTurn (backward compatibility helper)
  List<ContentPart> get parts => modelTurn?.parts ?? [];

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
      'ServerContent(parts: ${parts.length}, complete: $turnComplete, interrupted: $interrupted)';
}

/// Transcription data (user speech or AI speech to text)
class TranscriptionData {
  final String text;
  final bool? finished;

  const TranscriptionData({
    required this.text,
    this.finished,
  });

  factory TranscriptionData.fromJson(Map<String, dynamic> json) {
    return TranscriptionData(
      text: json['text'] as String? ?? '',
      finished: json['finished'] as bool?,
    );
  }

  @override
  String toString() => 'Transcription("$text", finished: $finished)';
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

/// Model turn containing generated content parts
class ModelTurn {
  final List<ContentPart> parts;

  const ModelTurn({required this.parts});

  factory ModelTurn.fromJson(Map<String, dynamic> json) {
    final partsJson = json['parts'] as List<dynamic>? ?? [];
    final parts = partsJson
        .map((p) => ContentPart.fromJson(p as Map<String, dynamic>))
        .toList();
    return ModelTurn(parts: parts);
  }

  @override
  String toString() => 'ModelTurn(${parts.length} parts)';
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
  /// Raw metadata from the function call (e.g., thought signatures on Gemini 3).
  /// Preserved for passthrough in tool responses.
  final Map<String, dynamic>? rawMetadata;

  const ToolCallData({
    required this.id,
    required this.name,
    required this.args,
    this.rawMetadata,
  });

  /// Parse a single function call entry from the functionCalls array.
  factory ToolCallData._fromFunctionCall(Map<String, dynamic> fc) {
    // Preserve any fields beyond id/name/args as rawMetadata
    final knownKeys = {'id', 'name', 'args'};
    final metadata = <String, dynamic>{};
    for (final entry in fc.entries) {
      if (!knownKeys.contains(entry.key)) {
        metadata[entry.key] = entry.value;
      }
    }

    return ToolCallData(
      id: fc['id'] as String? ?? '',
      name: fc['name'] as String,
      args: fc['args'] as Map<String, dynamic>? ?? {},
      rawMetadata: metadata.isEmpty ? null : metadata,
    );
  }

  /// Parse first tool call (backward compat for single-call responses).
  factory ToolCallData.fromJson(Map<String, dynamic> json) {
    final functionCalls = json['functionCalls'] as List<dynamic>? ?? [];
    if (functionCalls.isEmpty) {
      throw FormatException('Tool call missing functionCalls');
    }
    return ToolCallData._fromFunctionCall(
        functionCalls[0] as Map<String, dynamic>);
  }

  /// Parse ALL tool calls from a batched response (Gemini 3.1+).
  static List<ToolCallData> allFromJson(Map<String, dynamic> json) {
    final functionCalls = json['functionCalls'] as List<dynamic>? ?? [];
    if (functionCalls.isEmpty) {
      throw FormatException('Tool call missing functionCalls');
    }
    return functionCalls
        .map((fc) =>
            ToolCallData._fromFunctionCall(fc as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() => 'ToolCall(id: $id, name: $name, args: $args)';
}

/// Session resumption update data from the server
class SessionResumptionUpdateData {
  /// New resumption handle for reconnecting
  final String? newHandle;

  /// Whether the session is resumable
  final bool resumable;

  const SessionResumptionUpdateData({
    this.newHandle,
    this.resumable = false,
  });

  factory SessionResumptionUpdateData.fromJson(Map<String, dynamic> json) {
    return SessionResumptionUpdateData(
      newHandle: json['newHandle'] as String?,
      resumable: json['resumable'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'SessionResumptionUpdate(handle: ${newHandle != null ? "present" : "null"}, resumable: $resumable)';
}

/// GoAway message data — server is about to disconnect
class GoAwayData {
  /// Time remaining before disconnect (e.g., "30s")
  final String? timeLeft;

  const GoAwayData({
    this.timeLeft,
  });

  factory GoAwayData.fromJson(Map<String, dynamic> json) {
    return GoAwayData(
      timeLeft: json['timeLeft'] as String?,
    );
  }

  @override
  String toString() => 'GoAway(timeLeft: $timeLeft)';
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

/// Token usage for the most recent generation (WP-7, audit L12).
/// See ai.google.dev/api/live — UsageMetadata. Docs describe
/// `totalTokenCount` as "for the generation request" (singular), not the
/// whole session — treated here as PER-TURN, not cumulative across the
/// session (matches how usageMetadata behaves on the REST generateContent
/// API); the doc doesn't explicitly confirm this for the Live/bidi
/// protocol, so the client takes the safer "latest value this turn wins,
/// applied once" approach rather than summing every message, to avoid
/// double-counting if the server ever does send incremental updates
/// within one turn.
class UsageMetadataData {
  final int? promptTokenCount;
  final int? responseTokenCount;
  final int? totalTokenCount;
  final List<ModalityTokenCount>? promptTokensDetails;
  final List<ModalityTokenCount>? responseTokensDetails;

  const UsageMetadataData({
    this.promptTokenCount,
    this.responseTokenCount,
    this.totalTokenCount,
    this.promptTokensDetails,
    this.responseTokensDetails,
  });

  factory UsageMetadataData.fromJson(Map<String, dynamic> json) {
    List<ModalityTokenCount>? parseDetails(String key) {
      final list = json[key] as List<dynamic>?;
      if (list == null) return null;
      return list
          .map((e) => ModalityTokenCount.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return UsageMetadataData(
      promptTokenCount: json['promptTokenCount'] as int?,
      responseTokenCount: json['responseTokenCount'] as int?,
      totalTokenCount: json['totalTokenCount'] as int?,
      promptTokensDetails: parseDetails('promptTokensDetails'),
      responseTokensDetails: parseDetails('responseTokensDetails'),
    );
  }

  @override
  String toString() =>
      'UsageMetadata(prompt: $promptTokenCount, response: $responseTokenCount, '
      'total: $totalTokenCount)';
}

/// Per-modality token count entry within [UsageMetadataData]'s details
/// arrays. `modality` is a string enum (e.g. 'TEXT', 'AUDIO', 'IMAGE') per
/// ai.google.dev's ModalityTokenCount type.
class ModalityTokenCount {
  final String modality;
  final int tokenCount;

  const ModalityTokenCount({
    required this.modality,
    required this.tokenCount,
  });

  factory ModalityTokenCount.fromJson(Map<String, dynamic> json) {
    return ModalityTokenCount(
      modality: json['modality'] as String? ?? 'MODALITY_UNSPECIFIED',
      tokenCount: json['tokenCount'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'ModalityTokenCount($modality: $tokenCount)';
}
