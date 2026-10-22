import 'package:siso_project/src/core/network/api_client.dart';
import 'package:siso_project/src/core/network/socket_manager.dart';

/// [Dev 2] Repository truy vấn & lắng nghe Realtime các ô lục giác H3 từ NestJS Backend
class HexagonRepository {
  /// Lấy danh sách ô lục giác H3 trong khu vực Đấu trường từ NestJS API
  Future<List<Map<String, dynamic>>> fetchArenaHexagons([String? arenaId]) async {
    try {
      final response = await ApiClient.dio.get(
        '/api/v1/turf/hexagons',
        queryParameters: arenaId != null ? {'arenaId': arenaId} : null,
      );
      final List list = response.data as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Lắng nghe sự kiện đổi màu ô lục giác theo thời gian thực qua WebSocket
  void subscribeHexClaimed(Function(dynamic event) onClaimed) {
    SocketManager.onHexClaimed(onClaimed);
  }
}
