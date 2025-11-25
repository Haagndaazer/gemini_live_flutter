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

  const LiveConfig({
    required this.apiKey,
    required this.model,
    this.responseModalities = const [ResponseModality.audio],
    this.tools,
    this.systemInstruction,
    this.generationConfig,
    this.wsEndpoint,
  });

  /// Get the full WebSocket URL with authentication
  String get webSocketUrl {
    final base = wsEndpoint ??
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
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
    if (systemInstruction != null) {
      setup['systemInstruction'] = systemInstruction;
    }

    // Add tools if provided
    if (tools != null && tools!.isNotEmpty) {
      setup['tools'] = tools;
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

  const GenerationConfig({
    this.candidateCount,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
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

    return json;
  }
}
