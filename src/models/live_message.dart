import 'dart:convert';
import 'dart:typed_data';

/// Base class for messages sent to Gemini Live API
abstract class LiveMessage {
  /// Convert message to JSON for transmission
  Map<String, dynamic> toJson();

  /// Convert to JSON string for WebSocket
  String toJsonString() => jsonEncode(toJson());
}

/// Client content message (text input)
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

/// Realtime input message (audio input)
class RealtimeInputMessage extends LiveMessage {
  final Uint8List audioPcm;
  final String mimeType;

  RealtimeInputMessage({
    required this.audioPcm,
    this.mimeType = 'audio/pcm',
  });

  /// Create from base64 encoded audio
  factory RealtimeInputMessage.fromBase64({
    required String base64Audio,
    String mimeType = 'audio/pcm',
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

/// Update config message (change settings mid-session)
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

/// End of turn signal
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

/// Interrupt message (stop current generation)
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
