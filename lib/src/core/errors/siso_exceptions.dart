/// Bảng mã lỗi hệ thống theo chuẩn SRS Mục 5 (System Error Codes)
class SisoErrorCodes {
  SisoErrorCodes._();

  /// ERR_101: Email không thuộc danh sách trường Bình Thạnh
  static const String invalidDomain = 'ERR_101';

  /// ERR_102: Mã OTP sai hoặc đã hết hạn
  static const String otpInvalid = 'ERR_102';

  /// ERR_103: Nhập sai OTP quá 5 lần hoặc gửi lại mã quá nhanh (< 60s)
  static const String otpLocked = 'ERR_103';

  /// Lỗi phía client: không kết nối được máy chủ (không có trong bảng mã của backend)
  static const String network = 'ERR_NETWORK';

  /// ERR_201: Phát hiện phần mềm giả lập tọa độ (Fake GPS)
  static const String mockGpsDetected = 'ERR_201';

  /// ERR_202: Tốc độ cao nhưng nhịp bước chân không khớp (Xe máy)
  static const String vehicleSpeedMismatch = 'ERR_202';

  /// ERR_203: Độ sai số vệ tinh > 20m (trong nhà/dưới hầm)
  static const String gpsAccuracyLow = 'ERR_203';

  /// ERR_204: sessionId không tồn tại, của Sinh viên khác, hoặc Phiên chạy đã kết thúc
  static const String sessionNotFound = 'ERR_204';

  /// ERR_301: Diện tích vòng khép vượt giới hạn 150 ô H3
  static const String loopTooLarge = 'ERR_301';

  /// ERR_302: Đường chạy cắt chéo hình số 8 không hợp lệ
  static const String selfIntersect = 'ERR_302';

  /// ERR_303: arenaId không tồn tại (GET /api/v1/turf/hexagons)
  static const String arenaNotFound = 'ERR_303';
}

class SisoException implements Exception {
  final String code;
  final String message;

  const SisoException({required this.code, required this.message});

  @override
  String toString() => '[$code] $message';
}
