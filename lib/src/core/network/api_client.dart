import 'package:dio/dio.dart';
import '../constants/app_constants.dart';

/// Singleton quản lý các yêu cầu HTTP REST tới NestJS Backend
class ApiClient {
  ApiClient._();

  static late final Dio dio;
  static String? _accessToken;

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
      ),
    );
  }

  static void setAccessToken(String? token) {
    _accessToken = token;
  }
}
