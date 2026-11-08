import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:siso_project/src/core/constants/app_constants.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/core/network/api_client.dart';
import 'package:siso_project/src/core/storage/token_storage.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';

/// Email thuộc 5 trường Bình Thạnh (chấp nhận cả subdomain như `st.hutech.edu.vn`).
/// Cùng quy tắc với `matchCampusDomain` ở backend.
bool isValidCampusEmail(String email) {
  final parts = email.trim().toLowerCase().split('@');
  if (parts.length != 2 || parts[0].isEmpty) return false;
  final domain = parts[1];
  return AppConstants.allowedCampusDomains
      .any((d) => domain == d || domain.endsWith('.$d'));
}

/// Thông báo cho lỗi không lường trước (không phải lỗi nghiệp vụ từ backend).
const unexpectedAuthError =
    'Đã xảy ra lỗi không mong muốn. Vui lòng thử lại.';

/// Đọc `exp` (giây) trong JWT; trả null nếu token không đọc được.
DateTime? jwtExpiry(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final exp = payload['exp'];
    if (exp is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  } catch (_) {
    return null;
  }
}

/// [Dev 1] Xác thực Email sinh viên qua NestJS REST API (`/api/v1/auth/*`).
class AuthRepository {
  AuthRepository({Dio? dio, TokenStorage? storage, DateTime Function()? clock})
      : _dioOverride = dio,
        _storage = storage ?? SecureTokenStorage(),
        _clock = clock ?? DateTime.now;

  static const tokenKey = 'siso_access_token';
  static const userKey = 'siso_user';

  final Dio? _dioOverride;
  final TokenStorage _storage;
  final DateTime Function() _clock;

  Dio get _dio => _dioOverride ?? ApiClient.dio;

  /// Bước 1: gửi OTP về email trường.
  Future<OtpRequestResult> requestOtp(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (!isValidCampusEmail(email)) {
      throw const SisoException(
        code: SisoErrorCodes.invalidDomain,
        message: 'SISO hiện chỉ hỗ trợ email HUTECH, UEF, UTH, FTU2, HIU.',
      );
    }

    final body = await _post('/api/v1/auth/edu-login', {'email': email});
    final data = body['data'] as Map<String, dynamic>;
    return OtpRequestResult(
      email: data['email'] as String,
      message: body['message'] as String? ?? '',
      expiresInSeconds: data['expiresInSeconds'] as int,
      resendAfterSeconds: data['resendAfterSeconds'] as int,
      university:
          CampusInfo.fromJson(data['university'] as Map<String, dynamic>),
      sentAt: _clock(),
    );
  }

  /// Bước 2: xác thực OTP, lưu JWT vào secure storage và gắn vào ApiClient.
  Future<AuthUser> verifyOtp(String rawEmail, String otp) async {
    final body = await _post('/api/v1/auth/verify-otp', {
      'email': rawEmail.trim().toLowerCase(),
      'otp': otp.trim(),
    });
    final data = body['data'] as Map<String, dynamic>;
    final token = data['accessToken'] as String;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);

    await _storage.write(tokenKey, token);
    await _storage.write(userKey, jsonEncode(user.toJson()));
    ApiClient.setAccessToken(token);
    return user;
  }

  /// Khôi phục phiên khi mở app. Trả null nếu phải đăng nhập lại.
  /// - Server xác nhận token (`/auth/me`) -> user mới nhất.
  /// - Server trả 401 -> xoá token.
  /// - Mất mạng hoặc server lỗi tạm thời (5xx) -> dùng hồ sơ đã lưu nếu token chưa hết hạn.
  /// - Lỗi bất ngờ (đọc storage hỏng, response sai định dạng) -> đăng nhập lại, không ném lỗi.
  Future<AuthUser?> restoreSession() async {
    try {
      final token = await _storage.read(tokenKey);
      if (token == null) return null;

      final expiry = jwtExpiry(token);
      if (expiry == null || !expiry.isAfter(_clock())) {
        await _safeLogout();
        return null;
      }

      ApiClient.setAccessToken(token);
      try {
        final response = await _dio.get(
          '/api/v1/auth/me',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final data = (response.data as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
        final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
        await _storage.write(userKey, jsonEncode(user.toJson()));
        return user;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == null || status >= 500) {
          final cached = await _storage.read(userKey);
          if (cached != null) {
            return AuthUser.fromJson(
                jsonDecode(cached) as Map<String, dynamic>);
          }
        }
        // 401/4xx (hoặc không có hồ sơ lưu sẵn): đăng nhập lại
        await _safeLogout();
        return null;
      }
    } catch (_) {
      await _safeLogout();
      return null;
    }
  }

  Future<void> _safeLogout() async {
    try {
      await logout();
    } catch (_) {
      ApiClient.setAccessToken(null);
    }
  }

  Future<void> logout() async {
    await _storage.delete(tokenKey);
    await _storage.delete(userKey);
    ApiClient.setAccessToken(null);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw mapAuthError(e);
    }
  }
}

/// Đổi lỗi Dio thành [SisoException], giữ nguyên `code`/`message` backend trả về.
SisoException mapAuthError(DioException e) {
  final body = e.response?.data;
  if (body is Map && body['code'] is String) {
    final message = body['message'];
    return SisoException(
      code: body['code'] as String,
      message: message is List
          ? message.join('\n')
          : (message as String? ?? 'Yêu cầu không hợp lệ.'),
    );
  }
  if (e.response == null) {
    return const SisoException(
      code: SisoErrorCodes.network,
      message: 'Không thể kết nối máy chủ. Kiểm tra mạng hoặc API_BASE_URL.',
    );
  }
  return SisoException(
    code: 'HTTP_${e.response!.statusCode}',
    message: 'Máy chủ gặp lỗi. Vui lòng thử lại sau.',
  );
}
