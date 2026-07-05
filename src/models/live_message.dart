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
    // Gemini 3.1+: modality-specific `audio` field replaces the deprecated
    // `realtimeInput.mediaChunks[]`. See ai.google.dev/api/live —
    // BidiGenerateContentRealtimeInput. RealtimeTextInputMessage above
    // already uses the same modality-specific pattern (realtimeInput.text).
    return {
      'realtimeInput': {
        'audio': {
          'mimeType': mimeType,
          'data': base64Encode(audioPcm),
        }
      }
    };
  }

  @override
  String toString() => 'RealtimeInput(${audioPcm.length} bytes, $mimeType)';
}

/// Batch tool response message — sends function responses (one or many) in
/// a single message.
///
/// This is the sole way to answer tool calls (WP-4, audit L4/L10):
/// `functionResponses[]` entries require `id`, `name`, AND `response`
/// per /gemini-api/docs/live-tools (verified — `name` was previously
/// omitted here, and forum reports tie a missing `name` to spurious 1008
/// closes landing right after the first tool response, i.e. on essentially
/// every turn since `record_turn_observation` fires on every one). Gemini
/// 3.1+ batches parallel tool calls together and expects one combined
/// response — this same shape also covers the single-call case, so every
/// turn goes through one code path instead of two.
///
/// Thought-signature passthrough was considered for this message
/// ([VERIFY]ed against ai.google.dev/api/live and
/// /gemini-api/docs/generate-content/thought-signatures): thought
/// signatures are a REST `generateContent` history-reconstruction
/// mechanism — a sibling field to `functionCall` in a `parts` array that
/// the client echoes back when replaying prior turns from scratch. The
/// Live API's `BidiGenerateContentToolResponse`/`FunctionResponse` has no
/// documented field for it (the bidi session already holds server-side
/// turn state, so there is nothing to reconstruct), so it is deliberately
/// NOT threaded through here rather than guessed at.
class BatchToolResponseMessage extends LiveMessage {
  final List<({String id, String name, Map<String, dynamic> response})>
      responses;

  BatchToolResponseMessage({required this.responses});

  @override
  Map<String, dynamic> toJson() {
    return {
      'toolResponse': {
        'functionResponses': responses
            .map((r) => {
                  'id': r.id,
                  'name': r.name,
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

/// Marks the start of a user utterance — only legal when
/// realtimeInputConfig.automaticActivityDetection.disabled is true (manual
/// VAD / WP-5 Option A). See ai.google.dev/api/live —
/// BidiGenerateContentRealtimeInput.activityStart.
class ActivityStartMessage extends LiveMessage {
  @override
  Map<String, dynamic> toJson() {
    return {
      'realtimeInput': {
        'activityStart': <String, dynamic>{},
      }
    };
  }

  @override
  String toString() => 'ActivityStart()';
}

/// Marks the end of a user utterance — the manual-VAD counterpart to
/// [ActivityStartMessage]. See ai.google.dev/api/live —
/// BidiGenerateContentRealtimeInput.activityEnd.
class ActivityEndMessage extends LiveMessage {
  @override
  Map<String, dynamic> toJson() {
    return {
      'realtimeInput': {
        'activityEnd': <String, dynamic>{},
      }
    };
  }

  @override
  String toString() => 'ActivityEnd()';
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
