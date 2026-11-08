import 'biometric_model.dart';

/// Một cửa sổ cảm biến gửi lên `POST /api/v1/telemetry/verify`: đúng 256 mẫu gia tốc
/// (đơn vị m/s², chưa quy đổi) kèm số liệu GPS trong cùng khoảng thời gian.
class TelemetryWindow {
  const TelemetryWindow({
    required this.samples,
    required this.averageSpeedMps,
    required this.horizontalAccuracy,
    required this.isMocked,
  });

  /// Số mẫu cố định của một cửa sổ (5,12 s ở 50 Hz), theo hợp đồng #3.
  static const int size = 256;

  final List<ImuSample> samples;
  final double averageSpeedMps;
  final double horizontalAccuracy;
  final bool isMocked;

  Map<String, dynamic> toJson({String? sessionId}) => {
        if (sessionId != null) 'sessionId': sessionId,
        'averageSpeedMps': averageSpeedMps,
        'horizontalAccuracy': horizontalAccuracy,
        'isMocked': isMocked,
        'imuSamples': [for (final s in samples) s.toJson()],
      };
}

/// Nguồn dữ liệu cho màn hình chạy.
///
/// - Bản giả lập ([SimulatedTelemetrySource]) dùng khi dev trên Chrome và cho Demo Simulator.
/// - Bản thật (DEV 1, Module 3) đọc GPS + gia tốc kế 50 Hz, gom 256 mẫu bằng `AccelBuffer`
///   rồi phát một [TelemetryWindow] và xoá đệm (các cửa sổ không chồng nhau).
abstract class TelemetryWindowSource {
  /// Tốc độ tức thời (m/s) để hiện HUD liên tục, khoảng 1 giá trị mỗi giây.
  Stream<double> get speedMps;

  /// Mỗi cửa sổ 256 mẫu, khoảng 5,12 giây một lần.
  Stream<TelemetryWindow> get windows;

  void start();
  void stop();
}

/// Kết quả server trả cho một cửa sổ (phần `data` của BaseResponseDto).
class VerifyWindowResult {
  const VerifyWindowResult({
    required this.sessionId,
    required this.windowPassed,
    required this.consecutiveFailures,
    required this.biometricApplied,
    required this.cadenceSpm,
    required this.message,
  });

  final String sessionId;
  final bool windowPassed;
  final int consecutiveFailures;
  final bool biometricApplied;
  final int cadenceSpm;
  final String message;
}
