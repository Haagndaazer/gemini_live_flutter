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
