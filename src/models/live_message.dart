import 'dart:convert';
import 'dart:typed_data';

/// Base class for messages sent to Gemini Live API
abstract class LiveMessage {
  /// Convert message to JSON for transmission
  Map<String, dynamic> toJson();

  /// Convert to JSON string for WebSocket
  String toJsonString() => jsonEncode(toJson());
}

/// Client content message — restricted to initial history seeding only on 3.1+.
/// For mid-session text input, use [RealtimeTextInputMessage] instead.
class ClientContentMessage extends LiveMessage {
  final String text;
  final bool? turnComplete;

  ClientContentMessage({
    required this.text,
    this.turnComplete = true,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text}
            ]
          }
        ],
        if (turnComplete != null) 'turnComplete': turnComplete,
      }
    };
  }

  @override
  String toString() => 'ClientContent("${text.substring(0, text.length > 50 ? 50 : text.length)}...")';
}

/// Realtime text input message — use for mid-session text on Gemini 3.1+.
/// Sends text via realtimeInput instead of clientContent.
class RealtimeTextInputMessage extends LiveMessage {
  final String text;

  RealtimeTextInputMessage({required this.text});

  @override
  Map<String, dynamic> toJson() {
    return {
      'realtimeInput': {
        'text': text,
      }
    };
  }

  @override
  String toString() =>
      'RealtimeTextInput("${text.substring(0, text.length > 50 ? 50 : text.length)}...")';
}

/// Realtime input message (audio input)
class RealtimeInputMessage extends LiveMessage {
  final Uint8List audioPcm;
  final String mimeType;

  RealtimeInputMessage({
    required this.audioPcm,
    this.mimeType = 'audio/pcm;rate=16000',
  });

  /// Create from base64 encoded audio
  factory RealtimeInputMessage.fromBase64({
    required String base64Audio,
    String mimeType = 'audio/pcm;rate=16000',
  }) {
    return RealtimeInputMessage(
      audioPcm: base64Decode(base64Audio),
      mimeType: mimeType,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': mimeType,
            'data': base64Encode(audioPcm),
          }
        ]
      }
    };
  }

  @override
  String toString() => 'RealtimeInput(${audioPcm.length} bytes, $mimeType)';
}

/// Tool response message (function execution result)
class ToolResponseMessage extends LiveMessage {
  final String toolCallId;
  final Map<String, dynamic> response;

  ToolResponseMessage({
    required this.toolCallId,
    required this.response,
  });

  /// Create success response
  factory ToolResponseMessage.success({
    required String toolCallId,
    required Map<String, dynamic> result,
  }) {
    return ToolResponseMessage(
      toolCallId: toolCallId,
      response: result,
    );
  }

  /// Create error response
  factory ToolResponseMessage.error({
    required String toolCallId,
    required String errorMessage,
  }) {
    return ToolResponseMessage(
      toolCallId: toolCallId,
      response: {'error': errorMessage},
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'toolResponse': {
        'functionResponses': [
          {
            'id': toolCallId,
            'response': response,
          }
        ]
      }
    };
  }

  @override
  String toString() => 'ToolResponse(id: $toolCallId, response: $response)';
}

/// Batch tool response message — sends all function responses in a single message.
/// Required for Gemini 3.1+ which expects batched responses for parallel tool calls.
class BatchToolResponseMessage extends LiveMessage {
  final List<({String id, Map<String, dynamic> response})> responses;

  BatchToolResponseMessage({required this.responses});

  @override
  Map<String, dynamic> toJson() {
    return {
      'toolResponse': {
        'functionResponses': responses
            .map((r) => {
                  'id': r.id,
                  'response': r.response,
                })
            .toList(),
      }
    };
  }

  @override
  String toString() => 'BatchToolResponse(${responses.length} responses)';
}

/// Update config message (change settings mid-session)
/// NOTE: Mid-session config updates are NOT supported on Gemini 3.1+.
/// This class is kept for backward compatibility with 2.5.
@Deprecated('Mid-session config updates are not supported on Gemini 3.1+')
class UpdateConfigMessage extends LiveMessage {
  final List<String>? responseModalities;
  final Map<String, dynamic>? generationConfig;

  UpdateConfigMessage({
    this.responseModalities,
    this.generationConfig,
  });

  @override
  Map<String, dynamic> toJson() {
    final config = <String, dynamic>{};

    if (responseModalities != null && responseModalities!.isNotEmpty) {
      config['response_modalities'] =
          responseModalities!.map((m) => m.toUpperCase()).toList();
    }

    if (generationConfig != null) {
      config.addAll(generationConfig!);
    }

    return {
      'clientContent': {
        'generationConfig': config,
      }
    };
  }

  @override
  String toString() =>
      'UpdateConfig(modalities: $responseModalities, config: $generationConfig)';
}

/// End of turn signal.
/// On Gemini 3.1+, clientContent is restricted to initial history seeding.
/// During live conversation, the model relies on VAD or audioStreamEnd instead.
class EndOfTurnMessage extends LiveMessage {
  EndOfTurnMessage();

  @override
  Map<String, dynamic> toJson() {
    return {
      'clientContent': {
        'turnComplete': true,
      }
    };
  }

  @override
  String toString() => 'EndOfTurn()';
}

/// Audio stream end signal (flush cached audio, trigger response)
class AudioStreamEndMessage extends LiveMessage {
  AudioStreamEndMessage();

  @override
  Map<String, dynamic> toJson() {
    return {
      'realtimeInput': {
        'audioStreamEnd': true,
      }
    };
  }

  @override
  String toString() => 'AudioStreamEnd()';
}

/// Interrupt message (stop current generation).
/// NOTE: The 'interrupt' field does NOT exist in the API spec.
/// Interruption is implicit — sending any clientContent during generation
/// causes interruption. On 3.1+, interruption is handled by VAD.
@Deprecated('Interruption is implicit via VAD on 3.1+, not via explicit message')
class InterruptMessage extends LiveMessage {
  InterruptMessage();

  @override
  Map<String, dynamic> toJson() {
    return {
      'clientContent': {
        'interrupt': true,
      }
    };
  }

  @override
  String toString() => 'Interrupt()';
}
