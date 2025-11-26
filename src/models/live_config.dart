/// Configuration for Gemini Live API connection
///
/// This class encapsulates all settings needed to connect to and configure
/// the Gemini Live API WebSocket session.
class LiveConfig {
  /// Gemini API key for authentication
  final String apiKey;

  /// Model name (e.g., 'models/gemini-2.5-flash-native-audio-preview-09-2025')
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
  });

  /// Get the full WebSocket URL with authentication
  /// Uses v1alpha for affective audio and advanced voice features
  String get webSocketUrl {
    final base = wsEndpoint ??
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent';
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
          'response_modalities':
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
      setup['input_audio_transcription'] = <String, dynamic>{};
    }

    if (outputAudioTranscription) {
      setup['output_audio_transcription'] = <String, dynamic>{};
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
  final bool? enableAffectiveDialog;

  const GenerationConfig({
    this.candidateCount,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
    this.speechConfig,
    this.enableAffectiveDialog,
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
    if (speechConfig != null) json['speech_config'] = speechConfig!.toJson();
    if (enableAffectiveDialog != null) {
      json['enable_affective_dialog'] = enableAffectiveDialog;
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
      'voice_config': voiceConfig.toJson(),
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
      'prebuilt_voice_config': prebuiltVoiceConfig.toJson(),
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
      'voice_name': voiceName,
    };
  }
}
