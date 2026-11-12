import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../domain/telemetry_window.dart';

/// Gửi từng cửa sổ cảm biến lên server để kiểm định (Cổng Động học + Cổng Sinh trắc).
class TelemetryRepository {
  /// Ném [SisoException] khi server từ chối (ERR_2xx, HTTP_401...); lỗi mạng ném nguyên [DioException].
  ///
  /// Có [signingKey] thì ký nguyên văn body đã mã hoá, nên phải gửi đúng chuỗi JSON này.
  Future<VerifyWindowResult> verifyWindow(
    TelemetryWindow window, {
    String? sessionId,
    String? signingKey,
    int? seq,
  }) async {
    final body = jsonEncode(window.toJson(sessionId: sessionId, seq: seq));
    try {
      final response = await ApiClient.dio.post(
        '/api/v1/telemetry/verify',
        data: body,
        options: Options(
          headers: {if (signingKey != null) 'X-Siso-Signature': signTelemetryBody(signingKey, body)},
        ),
      );
      return parseVerifyResult(response.data);
    } on DioException catch (e) {
      final error = parseErrorBody(e.response?.data);
      if (error != null) throw error;
      rethrow;
    }
  }
}

/// HMAC-SHA256 (hex) của body. Phải khớp `signBody` ở `backend/.../telemetry-signature.ts`.
String signTelemetryBody(String signingKey, String body) =>
    Hmac(sha256, utf8.encode(signingKey)).convert(utf8.encode(body)).toString();

/// Đọc `data` của BaseResponseDto trả về từ `verify`.
VerifyWindowResult parseVerifyResult(Object? body) {
  if (body is! Map || body['success'] != true || body['data'] is! Map) {
    throw const FormatException('Phản hồi verify không đúng định dạng BaseResponseDto.');
  }
  final data = body['data'] as Map;
  return VerifyWindowResult(
    sessionId: data['sessionId'] as String,
    signingKey: data['signingKey'] as String?,
    windowPassed: data['windowPassed'] == true,
    consecutiveFailures: (data['consecutiveFailures'] as num?)?.toInt() ?? 0,
    biometricApplied: data['biometricApplied'] == true,
    cadenceSpm: (data['cadenceSpm'] as num?)?.toInt() ?? 0,
    message: data['message'] as String? ?? '',
  );
}

/// Đọc body lỗi của AllExceptionsFilter: `{ success: false, code, message }`. Không phải dạng đó thì trả null.
SisoException? parseErrorBody(Object? body) {
  if (body is! Map || body['success'] != false || body['code'] is! String) return null;
  final message = body['message'];
  return SisoException(
    code: body['code'] as String,
    message: message is List ? message.join('; ') : '${message ?? ''}',
  );
}
