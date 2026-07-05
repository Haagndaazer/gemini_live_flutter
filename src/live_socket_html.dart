import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WP-5 (audit L8) web-platform counterpart to live_socket_io.dart.
/// `package:web_socket_channel/html.dart`'s `HtmlWebSocketChannel.connect`
/// has no `pingInterval` parameter — the underlying `package:web`
/// `WebSocket` it now wraps (this package's `html.dart` moved off
/// `dart:html` internally) has no equivalent knob, so the web build keeps
/// the plain, unconfigured connect. `web/` is a configured platform in
/// this repo (`.metadata` + `web/` directory both exist), so this file
/// must stay compilable even though `flutter build web` may not be an
/// actively-shipped target today.
WebSocketChannel connectLiveSocket(Uri uri) => HtmlWebSocketChannel.connect(uri);
