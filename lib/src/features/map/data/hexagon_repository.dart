import 'package:siso_project/src/core/network/api_client.dart';
import 'package:siso_project/src/core/network/socket_manager.dart';

/// [Dev 2] Repository truy vấn & lắng nghe Realtime các ô lục giác H3 từ NestJS Backend
class HexagonRepository {
  /// Lấy các ô lục giác H3 (bỏ trống [arenaId] để lấy toàn bộ). Lỗi hoặc sai dạng → mảng rỗng.
  Future<List<Map<String, dynamic>>> fetchArenaHexagons([String? arenaId]) async {
    try {
      final response = await ApiClient.dio.get(
        '/api/v1/turf/hexagons',
        queryParameters: arenaId != null ? {'arenaId': arenaId} : null,
      );
      return parseListPayload(response.data);
    } catch (e) {
      return [];
    }
  }

  /// Lấy danh sách Đấu trường đang hoạt động (`id`, `name`, `description`, `hexCount`, `boundary`).
  /// Lỗi hoặc sai dạng → mảng rỗng.
  Future<List<Map<String, dynamic>>> fetchArenas() async {
    try {
      final response = await ApiClient.dio.get('/api/v1/turf/arenas');
      return parseListPayload(response.data);
    } catch (e) {
      return [];
    }
  }

  /// Lắng nghe sự kiện đổi màu ô lục giác theo thời gian thực qua WebSocket
  void subscribeHexClaimed(Function(dynamic event) onClaimed) {
    SocketManager.onHexClaimed(onClaimed);
  }

  /// Ngừng lắng nghe: truyền đúng callback đã đưa vào [subscribeHexClaimed].
  void unsubscribeHexClaimed(Function(dynamic event) onClaimed) {
    SocketManager.offHexClaimed(onClaimed);
  }
}

/// Đọc mảng trong `BaseResponseDto` của backend: `{ success, message, data: [...], timestamp }`.
/// `success` khác true, thiếu `data` hoặc phần tử không phải object → bỏ qua.
List<Map<String, dynamic>> parseListPayload(Object? body) {
  if (body is! Map || body['success'] != true) return [];
  final data = body['data'];
  if (data is! List) return [];
  return [
    for (final item in data)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}
