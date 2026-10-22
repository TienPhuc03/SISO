import 'package:siso_project/src/core/constants/app_constants.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/core/network/api_client.dart';

/// [Dev 1] Repository xử lý xác thực Email sinh viên (@*.edu.vn) qua NestJS REST API
class AuthRepository {
  /// Kiểm tra đuôi email có thuộc 5 trường Đại học Bình Thạnh hay không (Tầng 0: Identity Gate)
  bool isValidCampusEmail(String email) {
    final parts = email.trim().toLowerCase().split('@');
    if (parts.length != 2) return false;
    final domain = parts[1];
    return AppConstants.allowedCampusDomains.contains(domain);
  }

  /// Gửi yêu cầu đăng nhập và nhận mã OTP về email trường
  Future<Map<String, dynamic>> requestEduLogin(String email) async {
    if (!isValidCampusEmail(email)) {
      throw const SisoException(
        code: SisoErrorCodes.invalidDomain,
        message: 'Vui lòng sử dụng email sinh viên thuộc các trường Bình Thạnh.',
      );
    }

    try {
      final response = await ApiClient.dio.post(
        '/api/v1/auth/edu-login',
        data: {'email': email.trim().toLowerCase()},
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw const SisoException(
        code: SisoErrorCodes.invalidDomain,
        message: 'Không thể kết nối đến máy chủ xác thực.',
      );
    }
  }

  /// Alias tương thích cho phương thức đăng nhập bằng email sinh viên
  Future<Map<String, dynamic>> signInWithEduEmail(String email) async {
    return requestEduLogin(email);
  }

  /// Xác thực mã OTP và lưu JWT Token
  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    try {
      final response = await ApiClient.dio.post(
        '/api/v1/auth/verify-otp',
        data: {
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
        },
      );
      final data = response.data as Map<String, dynamic>;
      final token = data['accessToken'] as String?;
      ApiClient.setAccessToken(token);
      return data;
    } catch (e) {
      throw const SisoException(
        code: 'ERR_AUTH_OTP',
        message: 'Mã OTP không chính xác hoặc đã hết hạn.',
      );
    }
  }
}
