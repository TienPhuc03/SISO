import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/app_constants.dart';

/// Singleton quản lý kết nối WebSocket Realtime tới NestJS TurfGateway
class SocketManager {
  SocketManager._();

  static io.Socket? _socket;

  static void initialize() {
    _socket = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder()
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

  /// Gỡ đúng [callback] đã đăng ký bằng [onHexClaimed]; các listener khác giữ nguyên.
  static void offHexClaimed(Function(dynamic) callback) {
    _socket?.off('hex_claimed', callback);
  }

  /// Mỗi lần kết nối (lại) thành công: dùng để tải lại dữ liệu đã lỡ trong lúc mất kết nối.
  static void onConnected(Function(dynamic) callback) {
    _socket?.on('connect', callback);
  }

  static void offConnected(Function(dynamic) callback) {
    _socket?.off('connect', callback);
  }

  static void disconnect() {
    _socket?.disconnect();
  }
}
