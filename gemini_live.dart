/// Gemini Live API Client Package
///
/// This package provides a Flutter interface to the Gemini Live API for
/// real-time voice and text conversations with function calling support.
///
/// Example usage:
/// ```dart
/// final client = GeminiLiveClient(
///   config: LiveConfig(
///     apiKey: 'your-api-key',
///     model: 'models/gemini-2.5-flash-native-audio-preview-09-2025',
///     responseModalities: [ResponseModality.audio],
///   ),
///   callbacks: LiveCallbacks(
///     onConnected: () => print('Connected!'),
///     onText: (text, {isUser = false}) => print(isUser ? 'User' : 'AI': $text'),
///     onAudioData: (pcmData) => playAudio(pcmData),
///     onToolCall: (toolCall) => executeTool(toolCall),
///     onError: (error) => print('Error: $error'),
///   ),
/// );
///
/// await client.connect();
/// await client.sendText('Hello!');
/// // or
/// await client.sendAudio(pcmAudioData);
/// ```

// Core client
export 'src/gemini_live_client.dart';

// Configuration
export 'src/models/live_config.dart';

// State management
export 'src/models/live_state.dart';

// Error handling
export 'src/models/live_error.dart';

// Messages
export 'src/models/live_message.dart';

// Responses
export 'src/models/live_response.dart';

// Callbacks
export 'src/callbacks/live_callbacks.dart';

// Audio services
export 'src/services/audio_recording_service.dart';
export 'src/services/audio_playback_service.dart';
