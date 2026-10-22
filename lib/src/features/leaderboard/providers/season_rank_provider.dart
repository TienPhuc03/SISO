import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siso_project/src/core/network/api_client.dart';

/// [Dev 2] Provider cung cấp dữ liệu xếp hạng mùa giải từ NestJS API
final seasonRankProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final response = await ApiClient.dio.get('/api/v1/leaderboard/scores');
    final List list = response.data as List;
    return list.cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
  }
});
