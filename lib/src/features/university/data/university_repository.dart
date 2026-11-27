import 'package:siso_project/src/core/network/api_client.dart';

import '../domain/university_catalog.dart';

/// Đọc danh mục chọn Trường. Lỗi mạng / máy chủ được ném ra để màn hình báo lỗi.
class UniversityRepository {
  Future<UniversityCatalog> fetchCatalog() async {
    final body = (await ApiClient.dio.get('/api/v1/universities')).data as Map<String, dynamic>;
    return UniversityCatalog.fromJson(body['data'] as Map<String, dynamic>);
  }
}
