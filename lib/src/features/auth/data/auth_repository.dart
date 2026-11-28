import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/core/network/api_client.dart';
import 'package:siso_project/src/core/storage/token_storage.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';

/// Kiểm tra sơ bộ dạng `ten@mien.xx`; backend kiểm tra lại (IsEmail).
bool isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

/// Đăng nhập Google qua Firebase Auth, trả Firebase ID token; null nếu người dùng huỷ.
/// Không giữ phiên Firebase: phiên SISO là JWT do backend ký.
Future<String?> firebaseGoogleIdToken() async {
  final auth = FirebaseAuth.instance;
  try {
    final credential = await auth.signInWithProvider(
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
    );
    final token = await credential.user?.getIdToken();
    await auth.signOut();
    return token;
  } on FirebaseAuthException catch (e) {
    if (e.code.contains('cancel')) return null;
    throw SisoException(
      code: SisoErrorCodes.googleFailed,
      message: 'Không đăng nhập được bằng Google (${e.code}). Hãy thử lại hoặc dùng email.',
    );
  }
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
  AuthRepository({
    Dio? dio,
    TokenStorage? storage,
    DateTime Function()? clock,
    Future<String?> Function()? googleIdToken,
  })  : _dioOverride = dio,
        _storage = storage ?? SecureTokenStorage(),
        _clock = clock ?? DateTime.now,
        _googleIdTokenOverride = googleIdToken;

  static const tokenKey = 'siso_access_token';
  static const userKey = 'siso_user';

  final Dio? _dioOverride;
  final TokenStorage _storage;
  final DateTime Function() _clock;
  final Future<String?> Function()? _googleIdTokenOverride;

  /// Nút Google chỉ hiện khi Firebase đã khởi tạo (máy thật có google-services.json / GoogleService-Info.plist).
  bool get googleAvailable {
    if (_googleIdTokenOverride != null) return true;
    if (kIsWeb) return false;
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Dio get _dio => _dioOverride ?? ApiClient.dio;

  /// Bước 1: gửi OTP về email (email bất kỳ).
  Future<OtpRequestResult> requestOtp(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    final body = await _post('/api/v1/auth/email-login', {'email': email});
    final data = body['data'] as Map<String, dynamic>;
    return OtpRequestResult(
      email: data['email'] as String,
      message: body['message'] as String? ?? '',
      expiresInSeconds: data['expiresInSeconds'] as int,
      resendAfterSeconds: data['resendAfterSeconds'] as int,
      university: switch (data['university']) {
        Map<String, dynamic> u => CampusInfo.fromJson(u),
        _ => null,
      },
      sentAt: _clock(),
    );
  }

  /// Bước 2: xác thực OTP, lưu JWT vào secure storage và gắn vào ApiClient.
  Future<AuthUser> verifyOtp(String rawEmail, String otp) async {
    final body = await _post('/api/v1/auth/verify-otp', {
      'email': rawEmail.trim().toLowerCase(),
      'otp': otp.trim(),
    });
    return _saveSession(body);
  }

  /// Đăng nhập Google: lấy Firebase ID token rồi đổi lấy JWT SISO. Trả null nếu người dùng huỷ.
  Future<AuthUser?> signInWithGoogle() async {
    final idToken = await (_googleIdTokenOverride ?? firebaseGoogleIdToken)();
    if (idToken == null) return null;
    return _saveSession(await _post('/api/v1/auth/google', {'idToken': idToken}));
  }

  /// Chọn / đổi Trường: Trường có sẵn ([universityId]) hoặc thêm mới ([name] + [shortName] + [district]).
  /// Server trả phiên mới (JWT mang universityId) nên lưu lại như lúc đăng nhập.
  Future<AuthUser> chooseUniversity({String? universityId, String? name, String? shortName, String? district}) async {
    try {
      final response = await _dio.put('/api/v1/universities/mine', data: {
        if (universityId != null) 'universityId': universityId,
        if (universityId == null) ...{'name': name?.trim(), 'shortName': shortName?.trim(), 'district': district},
      });
      return await _saveSession(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapAuthError(e);
    }
  }

  /// Lưu JWT + hồ sơ vào secure storage và gắn token vào ApiClient.
  Future<AuthUser> _saveSession(Map<String, dynamic> body) async {
    final data = body['data'] as Map<String, dynamic>;
    final token = data['accessToken'] as String;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);

    await _storage.write(tokenKey, token);
    await _storage.write(userKey, jsonEncode(user.toJson()));
    ApiClient.setAccessToken(token);
    return user;
  }

  /// Khôi phục phiên khi mở app. Trả null nếu phải đăng nhập lại.
  /// - Server xác nhận token (`/auth/me`) -> user mới nhất, và lưu token mới server trả (gia hạn phiên).
  /// - Server trả 401/403 -> xoá token.
  /// - Lỗi khác (mất mạng, 5xx, 404 do sai API_BASE_URL, 429...) -> dùng hồ sơ đã lưu nếu token chưa hết hạn,
  ///   vì token chưa bị server từ chối.
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
        final renewed = data['accessToken'];
        if (renewed is String && renewed.isNotEmpty) {
          await _storage.write(tokenKey, renewed);
          ApiClient.setAccessToken(renewed);
        }
        await _storage.write(userKey, jsonEncode(user.toJson()));
        return user;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status != 401 && status != 403) {
          final cached = await _storage.read(userKey);
          if (cached != null) {
            return AuthUser.fromJson(
                jsonDecode(cached) as Map<String, dynamic>);
          }
        }
        // 401/403 (hoặc không có hồ sơ lưu sẵn): đăng nhập lại
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
