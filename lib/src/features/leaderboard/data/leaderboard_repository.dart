import 'package:siso_project/src/core/network/api_client.dart';

import '../../map/data/hexagon_repository.dart' show parseListPayload;
import '../domain/leaderboard_models.dart';

/// Đọc Bảng xếp hạng và Đại sảnh Danh vọng. Lỗi mạng hoặc máy chủ được ném ra để màn hình báo lỗi.
class LeaderboardRepository {
  /// Bảng xếp hạng một Cụm; [cluster] null = mọi Cụm.
  Future<List<CampusScore>> fetchScores({String? cluster}) async {
    final response = await ApiClient.dio
        .get('/api/v1/leaderboard/scores', queryParameters: {if (cluster != null) 'cluster': cluster});
    return [for (final row in parseListPayload(response.data)) CampusScore.fromJson(row)];
  }

  /// Mùa giải đang mở, hoặc null nếu server báo không có Mùa nào mở.
  Future<ActiveSeason?> fetchActiveSeason() async {
    final body = (await ApiClient.dio.get('/api/v1/leaderboard/season')).data;
    final data = body is Map && body['success'] == true ? body['data'] : null;
    return data is Map ? ActiveSeason.fromJson(Map<String, dynamic>.from(data)) : null;
  }

  Future<List<HallOfFameEntry>> fetchHallOfFame({String? cluster}) async {
    final response = await ApiClient.dio
        .get('/api/v1/leaderboard/hall-of-fame', queryParameters: {if (cluster != null) 'cluster': cluster});
    return [for (final row in parseListPayload(response.data)) HallOfFameEntry.fromJson(row)];
  }
}
