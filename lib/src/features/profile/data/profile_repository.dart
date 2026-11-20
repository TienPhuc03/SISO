import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../tracking/data/telemetry_repository.dart' show parseErrorBody;
import '../domain/profile_models.dart';

/// Hồ sơ Sinh viên và Lịch sử Phiên chạy. Lỗi server ném [SisoException]; lỗi mạng ném nguyên [DioException].
class ProfileRepository {
  Future<Profile> fetchProfile() async => Profile.fromJson(await _send(() => ApiClient.dio.get('/api/v1/profile')));

  Future<Profile> updateDisplayName(String displayName) async => Profile.fromJson(
        await _send(() => ApiClient.dio.patch('/api/v1/profile', data: {'displayName': displayName})),
      );

  /// [bytes] là ảnh đã thu nhỏ trên máy; server tự nhận diện JPEG/PNG/WebP theo byte đầu file.
  Future<Profile> uploadAvatar(Uint8List bytes, String filename) async => Profile.fromJson(
        await _send(() => ApiClient.dio.put(
              '/api/v1/profile/avatar',
              data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
              // BaseOptions đặt sẵn application/json: phải ghi đè để Dio tự thêm boundary.
              options: Options(contentType: 'multipart/form-data'),
            )),
      );

  /// shortcut: chỉ lấy 50 Phiên chạy gần nhất (trang 1); thêm "Xem thêm" khi Sinh viên chạy nhiều hơn.
  Future<List<RunSummary>> fetchRuns({int limit = 50}) async {
    final data = await _send(
      () => ApiClient.dio.get('/api/v1/telemetry/sessions', queryParameters: {'page': 1, 'limit': limit}),
    );
    return [for (final row in data as List) RunSummary.fromJson(row as Map<String, dynamic>)];
  }

  Future<RunDetail> fetchRun(String sessionId) async =>
      RunDetail.fromJson(await _send(() => ApiClient.dio.get('/api/v1/telemetry/sessions/$sessionId')));

  /// Trả phần `data` của BaseResponseDto.
  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return (response.data as Map)['data'];
    } on DioException catch (e) {
      final error = parseErrorBody(e.response?.data);
      if (error != null) throw error;
      rethrow;
    }
  }
}
