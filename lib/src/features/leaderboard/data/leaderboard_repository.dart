import 'package:siso_project/src/core/network/api_client.dart';

import '../../map/data/hexagon_repository.dart' show parseListPayload;
import '../domain/leaderboard_models.dart';

/// Đọc Bảng xếp hạng và Đại sảnh Danh vọng. Lỗi mạng hoặc máy chủ được ném ra để màn hình báo lỗi.
class LeaderboardRepository {
  Future<List<CampusScore>> fetchScores() async {
    final response = await ApiClient.dio.get('/api/v1/leaderboard/scores');
    return [for (final row in parseListPayload(response.data)) CampusScore.fromJson(row)];
  }

  Future<List<HallOfFameEntry>> fetchHallOfFame() async {
    final response = await ApiClient.dio.get('/api/v1/leaderboard/hall-of-fame');
    return [for (final row in parseListPayload(response.data)) HallOfFameEntry.fromJson(row)];
  }
}
