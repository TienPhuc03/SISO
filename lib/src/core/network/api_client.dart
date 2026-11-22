import 'package:dio/dio.dart';
import '../constants/app_constants.dart';

/// Singleton quản lý các yêu cầu HTTP REST tới NestJS Backend
class ApiClient {
  ApiClient._();

  static late final Dio dio;
  static String? _accessToken;

  /// Gọi khi backend trả 401 cho một request có gửi JWT (token hết hạn/không hợp lệ).
  /// `AuthSessionNotifier` gán callback này để tự đăng xuất về màn hình Login.
  static void Function()? onUnauthorized;

  static void initialize() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          // Chỉ đăng xuất khi 401 là của token hiện tại: request gửi bằng token cũ (trước khi
          // đăng nhập lại) về muộn không được đá phiên mới ra.
          final sentCurrentToken = _accessToken != null &&
              error.requestOptions.headers['Authorization'] == 'Bearer $_accessToken';
          if (error.response?.statusCode == 401 && sentCurrentToken) {
            onUnauthorized?.call();
          }
          return handler.next(error);
        },
      ),
    );
  }

  static String? get accessToken => _accessToken;

  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  static bool get hasAccessToken => _accessToken != null && _accessToken!.isNotEmpty;
}
