# Gemini Live Flutter Package

A Flutter package for real-time voice and text conversations with Google's Gemini Live API. Supports bidirectional streaming, function calling, and seamless mode switching.

## Features

- ✅ **WebSocket Connection**: Real-time bidirectional communication
- ✅ **Text & Voice Input**: Seamless switching between modalities
- ✅ **Audio Streaming**: Full implementation with recording & playback (16kHz input, 24kHz output)
- ✅ **Function Calling**: Execute tools during conversations
- ✅ **Transcriptions**: Built-in support for audio transcriptions
- ✅ **State Management**: Track connection and audio states
- ✅ **Error Handling**: Comprehensive error types and recovery
- ✅ **Permission Handling**: Microphone permission management
- ✅ **Audio Processing**: Auto-gain, echo cancellation, noise suppression
- ✅ **Zero Dependencies**: No app-specific coupling - pure, reusable package

## Installation

This package is designed as a Git submodule. See [SUBMODULE_SETUP.md](SUBMODULE_SETUP.md) for details.

```bash
git submodule add https://github.com/Haagndaazer/gemini_live_flutter.git lib/packages/gemini_live
```

Then import in your app:

```dart
import 'package:your_app/packages/gemini_live/gemini_live.dart';
```

## Quick Start

### 1. Basic Text Conversation

```dart
import 'package:your_app/packages/gemini_live/gemini_live.dart';

// Create client
final client = GeminiLiveClient(
  config: LiveConfig(
    apiKey: 'YOUR_API_KEY',
    model: 'models/gemini-2.5-flash-native-audio-preview-09-2025',
    responseModalities: [ResponseModality.text],
  ),
  callbacks: LiveCallbacks(
    onConnected: () => print('Connected!'),
    onText: (text, {isUser = false}) {
      print(isUser ? 'User: $text' : 'AI: $text');
    },
    onError: (error) => print('Error: $error'),
  ),
);

// Connect and chat
await client.connect();
await client.sendText('Hello, Gemini!');
await client.disconnect();
```

### 2. Voice Conversation

```dart
final client = GeminiLiveClient(
  config: LiveConfig(
    apiKey: 'YOUR_API_KEY',
    model: 'models/gemini-2.5-flash-native-audio-preview-09-2025',
    responseModalities: [ResponseModality.audio],
  ),
  callbacks: LiveCallbacks(
    onConnected: () => print('Ready for voice!'),
    onText: (text, {isUser = false}) {
      // Get transcriptions for both user and AI
      print('${isUser ? "You" : "AI"} said: $text');
    },
    onAudioData: (pcmData) {
      // Play AI's audio response
      playbackService.queueAudio(pcmData);
    },
  ),
);

await client.connect();

// Send audio from microphone
recordingService.audioStream?.listen((audioChunk) {
  client.sendAudio(audioChunk);
});
```

### 3. Function Calling

```dart
final client = GeminiLiveClient(
  config: LiveConfig(
    apiKey: 'YOUR_API_KEY',
    model: 'models/gemini-2.5-flash-native-audio-preview-09-2025',
    tools: [
      {
        'functionDeclarations': [
          {
            'name': 'get_weather',
            'description': 'Get current weather for a location',
            'parameters': {
              'type': 'object',
              'properties': {
                'location': {'type': 'string', 'description': 'City name'},
              },
              'required': ['location'],
            },
          }
        ]
      }
    ],
  ),
  callbacks: LiveCallbacks(
    onToolCall: (toolCall) async {
      print('Tool: ${toolCall.name}, Args: ${toolCall.args}');

      // Execute tool
      final result = await executeMyTool(toolCall);

      // Send result back
      await client.sendToolResponse(
        toolCallId: toolCall.id,
        response: result,
      );
    },
  ),
);
```

### 4. State Monitoring

```dart
final client = GeminiLiveClient(
  config: config,
  callbacks: LiveCallbacks(
    onConnectionStateChanged: (state) {
      switch (state) {
        case ConnectionState.connecting:
          showLoader();
          break;
        case ConnectionState.connected:
          hideLoader();
          break;
        case ConnectionState.error:
          showErrorDialog();
          break;
        case ConnectionState.disconnected:
          cleanup();
          break;
      }
    },
    onAudioStateChanged: (state) {
      switch (state) {
        case AudioState.listening:
          showMicrophoneIndicator();
          break;
        case AudioState.processing:
          showThinkingIndicator();
          break;
        case AudioState.speaking:
          showSpeakerIndicator();
          break;
        case AudioState.idle:
          hideAllIndicators();
          break;
      }
    },
  ),
);
```

### 5. Seamless Mode Switching

```dart
// Start in text mode
final client = GeminiLiveClient(
  config: LiveConfig(
    apiKey: apiKey,
    model: model,
    responseModalities: [ResponseModality.text],
  ),
  callbacks: callbacks,
);

await client.connect();

// Switch to voice mode mid-conversation
await client.updateModalities([ResponseModality.audio]);

// Switch back to text
await client.updateModalities([ResponseModality.text]);
```

## Architecture

```
gemini_live/
├── gemini_live.dart              # Main export file
├── src/
│   ├── gemini_live_client.dart   # Core WebSocket client
│   ├── models/
│   │   ├── live_config.dart      # Configuration
│   │   ├── live_state.dart       # State management
│   │   ├── live_error.dart       # Error types
│   │   ├── live_message.dart     # Outgoing messages
│   │   └── live_response.dart    # Incoming responses
│   ├── callbacks/
│   │   └── live_callbacks.dart   # Event callbacks
│   └── services/
│       ├── audio_recording_service.dart  # Microphone capture
│       └── audio_playback_service.dart   # Audio playback
├── README.md
└── SUBMODULE_SETUP.md
```

## API Reference

### GeminiLiveClient

Main client for interacting with Gemini Live API.

**Methods:**
- `connect()` - Establish WebSocket connection
- `disconnect()` - Close connection
- `sendText(String text)` - Send text message
- `sendAudio(List<int> pcmData)` - Send audio data
- `sendToolResponse(String id, Map result)` - Send tool execution result
- `updateModalities(List<ResponseModality>)` - Change response mode
- `interrupt()` - Stop current generation
- `dispose()` - Cleanup resources

**Properties:**
- `state` - Current LiveSessionState
- `isConnected` - Connection status

### LiveConfig

Configuration for the Live API connection.

**Parameters:**
- `apiKey` (required) - Gemini API key
- `model` (required) - Model name
- `responseModalities` - Text, audio, or both
- `tools` - Function declarations for tool calling
- `systemInstruction` - Optional system prompt
- `generationConfig` - Temperature, topP, etc.

### LiveCallbacks

Event callbacks for handling API responses.

**Available Callbacks:**
- `onConnected()` - Connection established
- `onDisconnected(String reason)` - Connection closed
- `onText(String text, {bool isUser})` - Text received
- `onAudioData(Uint8List pcm)` - Audio received
- `onToolCall(ToolCallData call)` - Tool execution requested
- `onError(LiveError error)` - Error occurred
- `onConnectionStateChanged(ConnectionState)` - State changed
- `onAudioStateChanged(AudioState)` - Audio state changed
- And more... (see source for full list)

### LiveSessionState

Tracks connection and audio state.

**States:**
- ConnectionState: `disconnected`, `connecting`, `connected`, `error`
- AudioState: `idle`, `listening`, `processing`, `speaking`

**Properties:**
- `connectionState` - Current connection status
- `audioState` - Current audio status
- `errorMessage` - Last error (if any)
- `connectedAt` - Connection timestamp
- `messagesReceived` / `messagesSent` - Message counts
- `connectionDuration` - Time since connection

### Error Types

```dart
enum LiveErrorType {
  connectionFailed,   // WebSocket connection failed
  disconnected,       // Connection closed
  audioRecording,     // Microphone error
  audioPlayback,      // Speaker error
  messageFormat,      // Invalid message
  apiError,           // API returned error
  permissionDenied,   // Missing permission
  timeout,            // Operation timed out
  unknown,            // Other errors
}
```

## Audio Services

The package includes **fully implemented** audio services for recording and playback.

### Setup

1. Add dependencies to `pubspec.yaml`:
```yaml
dependencies:
  record: ^5.1.2              # Audio recording
  permission_handler: ^11.3.1 # Runtime permissions
  audioplayers: ^6.0.0        # Audio playback (or just_audio)
```

2. Request microphone permission:
```dart
final recorder = AudioRecordingService(
  onRecordingStarted: () => print('Recording...'),
  onRecordingStopped: () => print('Stopped'),
  onError: (error) => print('Error: $error'),
);

// Check and request permission
if (!await recorder.hasPermission()) {
  final granted = await recorder.requestPermission();
  if (!granted) {
    // Handle permission denied
    return;
  }
}

// Start recording
await recorder.startRecording();

// Stream audio to Live API
recorder.audioStream?.listen((audioChunk) {
  client.sendAudio(audioChunk);
});

// Stop when done
await recorder.stopRecording();
```

3. Play AI responses:
```dart
final playback = AudioPlaybackService(
  onPlaybackStarted: () => print('Playing...'),
  onPlaybackCompleted: () => print('Done'),
  onError: (error) => print('Error: $error'),
);

// Queue audio chunks from Live API
client.callbacks = LiveCallbacks(
  onAudioData: (pcmData) {
    playback.queueAudio(pcmData);
  },
);

// Or play immediately
await playback.playAudio(pcmData);
```

### Features

**AudioRecordingService:**
- ✅ 16kHz, 16-bit PCM, mono recording
- ✅ Auto gain, echo cancellation, noise suppression
- ✅ Permission handling
- ✅ Pause/resume support
- ✅ Amplitude monitoring for visual feedback
- ✅ Stream-based for real-time processing

**AudioPlaybackService:**
- ✅ 24kHz PCM playback with automatic WAV conversion
- ✅ Audio queueing for seamless playback
- ✅ Pause/resume/stop controls
- ✅ Volume control
- ✅ Position/duration tracking
- ✅ Completes automatically after each chunk

## Audio Format Requirements

**Input (User → Gemini):**
- Format: 16-bit PCM
- Sample rate: 16kHz
- Channels: Mono
- Endianness: Little-endian

**Output (Gemini → User):**
- Format: 16-bit PCM
- Sample rate: 24kHz
- Channels: Mono
- Endianness: Little-endian

## Best Practices

1. **Always handle errors**: Use `onError` callback
2. **Monitor state changes**: Track connection/audio states
3. **Dispose properly**: Call `client.dispose()` when done
4. **Use broadcast streams**: For multiple listeners
5. **Handle tool calls**: Always send responses or errors
6. **Test with real audio**: Silent audio may timeout (VAD)
7. **Add WAV headers**: Some players need WAV format

## Examples

See the `test/phase0_poc_live_api_test.dart` file for working examples of:
- Basic WebSocket connection
- Audio streaming
- Function calling
- Latency measurement

## Troubleshooting

**Connection fails:**
- Check API key is valid
- Verify model name is correct
- Check internet connection

**No audio playback:**
- Verify `audioplayers` dependency is installed
- Check that audio data is being received (use `onAudioData` callback)
- Ensure WAV conversion is working (automatic in AudioPlaybackService)
- Check device volume settings

**Silent audio times out:**
- This is expected behavior (Voice Activity Detection)
- Use real speech, not silent test audio

**Function calling not working:**
- Check tool declaration format matches REST API
- Always send tool responses (success or error)
- Monitor `onToolCall` callback

## Contributing

This package is designed to be portable and reusable. When contributing:
- Keep zero app-specific dependencies
- Follow existing patterns
- Add tests for new features
- Update documentation

## License

MIT License - See LICENSE file for details

## Support

For issues and questions:
- GitHub Issues: https://github.com/Haagndaazer/gemini_live_flutter/issues
- Documentation: See inline code comments

## Acknowledgments

Built for the Gemini Live API (v1beta)
- Model: `gemini-2.5-flash-native-audio-preview-09-2025`
- API: Google Cloud Generative Language API
