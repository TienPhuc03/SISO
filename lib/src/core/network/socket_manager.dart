import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../constants/app_constants.dart';

/// Singleton quản lý kết nối WebSocket Realtime tới NestJS TurfGateway
class SocketManager {
  SocketManager._();

  static IO.Socket? _socket;

  static void initialize() {
    _socket = IO.io(
      AppConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket?.connect();

    _socket?.onConnect((_) {
      // Đã kết nối thành công tới WebSocket Server
    });

    _socket?.onDisconnect((_) {
      // Đã ngắt kết nối WebSocket
    });
  }

  static void onHexClaimed(Function(dynamic) callback) {
    _socket?.on('hex_claimed', callback);
  }

  static void disconnect() {
    _socket?.disconnect();
  }
}
