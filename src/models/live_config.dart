/// Default WebSocket endpoint for Gemini Live API.
/// Both the main client and TTS service should use this shared constant.
/// Use v1beta for API key auth; v1alpha is for ephemeral token auth only.
const String kGeminiLiveWsEndpoint =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage'
    '.v1beta.GenerativeService.BidiGenerateContent';

/// Configuration for Gemini Live API connection
///
/// This class encapsulates all settings needed to connect to and configure
/// the Gemini Live API WebSocket session.
class LiveConfig {
  /// Gemini API key for authentication
  final String apiKey;

  /// Model name (e.g., 'models/gemini-3.1-flash-live-preview')
  final String model;

  /// Response modalities (audio, text, or both)
  final List<ResponseModality> responseModalities;

  /// Optional function calling tools
  final List<Map<String, dynamic>>? tools;

  /// Optional system instruction to guide model behavior
  final String? systemInstruction;

  /// Optional generation configuration
  final GenerationConfig? generationConfig;

  /// WebSocket endpoint (defaults to v1beta)
  final String? wsEndpoint;

  /// Enable input audio transcription (user speech to text)
  final bool inputAudioTranscription;

  /// Enable output audio transcription (AI speech to text)
  final bool outputAudioTranscription;

  /// Session resumption configuration for reconnecting to sessions
  final SessionResumptionConfig? sessionResumption;

  /// Context window compression configuration
  final ContextWindowCompressionConfig? contextWindowCompression;

  /// Realtime input handling configuration — voice activity detection
  /// tuning (WP-5, audit L5) or disabling it entirely for manual VAD.
  final RealtimeInputConfig? realtimeInputConfig;

  /// WP-6 (audit L6): enables `historyConfig.initialHistoryInClientContent`
  /// so a `clientContent` message sent immediately after `setupComplete`
  /// (via `sendHistorySeed`) seeds conversation history on a FRESH (non-
  /// resumed) session. A boolean enabling flag only — the history TEXT
  /// itself travels separately via `sendHistorySeed`'s `clientContent`
  /// message, never through this setup flag ([VERIFY]ed against
  /// ai.google.dev/api/live +
  /// /gemini-api/docs/live-api/capabilities: the doc's own wording is "the
  /// server will wait and at first process clientContent messages until
  /// turnComplete is true" — i.e. this flag changes server behavior, so it
  /// must only be set when a seed message will actually be sent right
  /// after, never on an ordinary first connect).
  final bool seedInitialHistory;

  const LiveConfig({
    required this.apiKey,
    required this.model,
    this.responseModalities = const [ResponseModality.audio],
    this.tools,
    this.systemInstruction,
    this.generationConfig,
    this.wsEndpoint,
    this.inputAudioTranscription = false,
    this.outputAudioTranscription = false,
    this.sessionResumption,
    this.contextWindowCompression,
    this.realtimeInputConfig,
    this.seedInitialHistory = false,
  });

  /// Get the full WebSocket URL with authentication
  String get webSocketUrl {
    final base = wsEndpoint ?? kGeminiLiveWsEndpoint;
    return '$base?key=$apiKey';
  }

  /// Convert to setup message JSON
  Map<String, dynamic> toSetupMessage() {
    final setup = <String, dynamic>{
      'model': model,
    };

    // Add generation config if provided
    if (generationConfig != null || responseModalities.isNotEmpty) {
      setup['generationConfig'] = {
        if (generationConfig != null) ...generationConfig!.toJson(),
        if (responseModalities.isNotEmpty)
          'responseModalities':
              responseModalities.map((m) => m.name.toUpperCase()).toList(),
      };
    }

    // Add system instruction if provided
    // Note: Must be Content object with parts array, not raw string
    if (systemInstruction != null) {
      setup['systemInstruction'] = {
        'parts': [
          {'text': systemInstruction}
        ]
      };
    }

    // Add tools if provided
    // Note: Must be wrapped in functionDeclarations array
    if (tools != null && tools!.isNotEmpty) {
      setup['tools'] = [
        {
          'functionDeclarations': tools
        }
      ];
    }

    // Add transcription configs if enabled
    if (inputAudioTranscription) {
      setup['inputAudioTranscription'] = <String, dynamic>{};
    }

    if (outputAudioTranscription) {
      setup['outputAudioTranscription'] = <String, dynamic>{};
    }

    // Add session resumption config
    if (sessionResumption != null) {
      setup['sessionResumption'] = sessionResumption!.toJson();
    }

    // Add context window compression config
    if (contextWindowCompression != null) {
      setup['contextWindowCompression'] = contextWindowCompression!.toJson();
    }

    // Add realtime input config (VAD tuning or manual-VAD disable)
    if (realtimeInputConfig != null) {
      setup['realtimeInputConfig'] = realtimeInputConfig!.toJson();
    }

    // WP-6 (audit L6): enable clientContent history seeding for a fresh
    // reconnect. See [seedInitialHistory] field doc for the exact key.
    if (seedInitialHistory) {
      setup['historyConfig'] = {'initialHistoryInClientContent': true};
    }

    return {'setup': setup};
  }
}

/// Response modality options
enum ResponseModality {
  audio,
  text;

  String get name {
    switch (this) {
      case ResponseModality.audio:
        return 'audio';
      case ResponseModality.text:
        return 'text';
    }
  }
}

/// Generation configuration parameters
class GenerationConfig {
  final int? candidateCount;
  final int? maxOutputTokens;
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? presencePenalty;
  final double? frequencyPenalty;
  final SpeechConfig? speechConfig;
  /// Thinking level for Gemini 3.1+ ('minimal', 'low', 'medium', 'high')
  final String? thinkingLevel;
  /// Whether to include thought summaries in responses (Gemini 3.1+)
  final bool? includeThoughts;

  const GenerationConfig({
    this.candidateCount,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
    this.speechConfig,
    this.thinkingLevel,
    this.includeThoughts,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (candidateCount != null) json['candidateCount'] = candidateCount;
    if (maxOutputTokens != null) json['maxOutputTokens'] = maxOutputTokens;
    if (temperature != null) json['temperature'] = temperature;
    if (topP != null) json['topP'] = topP;
    if (topK != null) json['topK'] = topK;
    if (presencePenalty != null) json['presencePenalty'] = presencePenalty;
    if (frequencyPenalty != null) {
      json['frequencyPenalty'] = frequencyPenalty;
    }
    if (speechConfig != null) json['speechConfig'] = speechConfig!.toJson();
    if (thinkingLevel != null) {
      json['thinkingConfig'] = {
        'thinkingLevel': thinkingLevel,
        if (includeThoughts != null) 'includeThoughts': includeThoughts,
      };
    }

    return json;
  }
}

/// Speech configuration for voice selection
class SpeechConfig {
  final VoiceConfig voiceConfig;

  const SpeechConfig({
    required this.voiceConfig,
  });

  Map<String, dynamic> toJson() {
    return {
      'voiceConfig': voiceConfig.toJson(),
    };
  }
}

/// Voice configuration
class VoiceConfig {
  final PrebuiltVoiceConfig prebuiltVoiceConfig;

  const VoiceConfig({
    required this.prebuiltVoiceConfig,
  });

  Map<String, dynamic> toJson() {
    return {
      'prebuiltVoiceConfig': prebuiltVoiceConfig.toJson(),
    };
  }
}

/// Prebuilt voice configuration
class PrebuiltVoiceConfig {
  final String voiceName;

  const PrebuiltVoiceConfig({
    required this.voiceName,
  });

  Map<String, dynamic> toJson() {
    return {
      'voiceName': voiceName,
    };
  }
}

/// Session resumption configuration for reconnecting to a previous session
class SessionResumptionConfig {
  /// Previous session handle to resume from (null for new sessions)
  final String? handle;

  const SessionResumptionConfig({
    this.handle,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (handle != null) json['handle'] = handle;
    return json;
  }
}

/// Context window compression configuration
class ContextWindowCompressionConfig {
  /// Whether compression is enabled
  final bool enabled;

  /// Target number of tokens after compression
  final int? targetTokens;

  const ContextWindowCompressionConfig({
    this.enabled = false,
    this.targetTokens,
  });

  /// Create an enabled compression config
  const ContextWindowCompressionConfig.enabled({
    this.targetTokens,
  }) : enabled = true;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (enabled) {
      json['slidingWindow'] = <String, dynamic>{
        if (targetTokens != null) 'targetTokens': targetTokens,
      };
    }
    return json;
  }
}

/// Realtime input handling configuration.
/// See ai.google.dev/api/live — BidiGenerateContentSetup.realtimeInputConfig.
class RealtimeInputConfig {
  final AutomaticActivityDetectionConfig? automaticActivityDetection;

  const RealtimeInputConfig({this.automaticActivityDetection});

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (automaticActivityDetection != null) {
      json['automaticActivityDetection'] = automaticActivityDetection!.toJson();
    }
    return json;
  }
}

/// Configuration for server-side (automatic) voice activity detection.
/// See ai.google.dev/api/live —
/// BidiGenerateContentSetup.realtimeInputConfig.automaticActivityDetection.
///
/// WP-5 (audit L5): two independent uses —
/// - [disabled] = true switches to manual VAD (Option A): the client must
///   then wrap each utterance in activityStart/activityEnd (see
///   [ActivityStartMessage]/[ActivityEndMessage] and
///   `GeminiLiveClient.sendActivityStart`/`sendActivityEnd`). NOT the
///   default — see the WP-5 commit note on why.
/// - [endOfSpeechSensitivity]/[silenceDurationMs] tune auto-VAD (kept ON,
///   Option B, the default) so a language learner's natural mid-utterance
///   pauses don't split one utterance into multiple server-side turns.
class AutomaticActivityDetectionConfig {
  final bool? disabled;
  final String? startOfSpeechSensitivity;
  final String? endOfSpeechSensitivity;
  final int? prefixPaddingMs;
  final int? silenceDurationMs;

  const AutomaticActivityDetectionConfig({
    this.disabled,
    this.startOfSpeechSensitivity,
    this.endOfSpeechSensitivity,
    this.prefixPaddingMs,
    this.silenceDurationMs,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (disabled != null) json['disabled'] = disabled;
    if (startOfSpeechSensitivity != null) {
      json['startOfSpeechSensitivity'] = startOfSpeechSensitivity;
    }
    if (endOfSpeechSensitivity != null) {
      json['endOfSpeechSensitivity'] = endOfSpeechSensitivity;
    }
    if (prefixPaddingMs != null) json['prefixPaddingMs'] = prefixPaddingMs;
    if (silenceDurationMs != null) json['silenceDurationMs'] = silenceDurationMs;
    return json;
  }
}
