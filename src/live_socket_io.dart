import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WP-5 (audit L8): non-web platforms get a protocol-level keepalive so a
/// push-to-talk socket idle for minutes between turns isn't silently reaped
/// by a mobile NAT/carrier middlebox. 20s matches the plan's chosen
/// interval — comfortably under the common 30-120s idle-reap window while
/// not spamming the connection.
WebSocketChannel connectLiveSocket(Uri uri) => IOWebSocketChannel.connect(
      uri,
      pingInterval: const Duration(seconds: 20),
    );
