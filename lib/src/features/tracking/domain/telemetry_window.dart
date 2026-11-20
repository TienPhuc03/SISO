import 'biometric_model.dart';

/// Một lần định vị GPS gửi kèm cửa sổ (`gpsPoints`) và dùng để vẽ Đường chạy.
class GpsFix {
  const GpsFix({required this.lat, required this.lng, required this.timestampMs, required this.accuracy});

  final double lat;
  final double lng;

  /// Epoch mili giây, cùng mốc với `timestampMs` của mẫu gia tốc.
  final int timestampMs;

  /// Sai số ngang (m); iOS trả -1 khi chưa có tín hiệu.
  final double accuracy;

  /// Cùng ngưỡng 20 m với Cổng Động học: điểm tệ hơn không được vẽ hay lưu.
  bool get trusted => accuracy >= 0 && accuracy <= 20;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'timestamp': timestampMs, 'accuracy': accuracy};
}

/// Server nhận tối đa bấy nhiêu điểm mỗi cửa sổ (`MAX_GPS_POINTS_PER_WINDOW`).
const maxGpsPointsPerWindow = 20;

/// Lấy đều tối đa [maxGpsPointsPerWindow] điểm, giữ điểm đầu và cuối.
List<GpsFix> capGpsPoints(List<GpsFix> points) {
  if (points.length <= maxGpsPointsPerWindow) return points;
  final step = (points.length - 1) / (maxGpsPointsPerWindow - 1);
  return [for (var i = 0; i < maxGpsPointsPerWindow; i++) points[(i * step).round()]];
}

/// Một cửa sổ cảm biến gửi lên `POST /api/v1/telemetry/verify`: đúng 256 mẫu gia tốc
/// (đơn vị m/s², chưa quy đổi) kèm số liệu GPS trong cùng khoảng thời gian.
class TelemetryWindow {
  const TelemetryWindow({
    required this.samples,
    required this.averageSpeedMps,
    required this.horizontalAccuracy,
    required this.isMocked,
    this.gpsPoints = const [],
  });

  /// Số mẫu cố định của một cửa sổ (5,12 s ở 50 Hz), theo hợp đồng #3.
  static const int size = 256;

  final List<ImuSample> samples;
  final double averageSpeedMps;
  final double horizontalAccuracy;
  final bool isMocked;

  /// Vệt GPS trong khoảng thời gian của cửa sổ (tối đa [maxGpsPointsPerWindow] điểm).
  final List<GpsFix> gpsPoints;

  Map<String, dynamic> toJson({String? sessionId, int? seq}) => {
        if (sessionId != null) 'sessionId': sessionId,
        if (seq != null) 'seq': seq,
        'averageSpeedMps': averageSpeedMps,
        'horizontalAccuracy': horizontalAccuracy,
        'isMocked': isMocked,
        'imuSamples': [for (final s in samples) s.toJson()],
        if (gpsPoints.isNotEmpty) 'gpsPoints': [for (final p in gpsPoints) p.toJson()],
      };
}

/// Nguồn dữ liệu cho màn hình chạy.
///
/// - Bản giả lập ([SimulatedTelemetrySource]) dùng khi dev trên Chrome và cho Demo Simulator.
/// - Bản thật (`DeviceTelemetrySource`) đọc GPS + gia tốc kế 50 Hz, gom 256 mẫu
///   rồi phát một [TelemetryWindow] và xoá đệm (các cửa sổ không chồng nhau).
abstract class TelemetryWindowSource {
  /// Tốc độ tức thời (m/s) để hiện HUD liên tục, khoảng 1 giá trị mỗi giây.
  Stream<double> get speedMps;

  /// Mỗi cửa sổ 256 mẫu, khoảng 5,12 giây một lần.
  Stream<TelemetryWindow> get windows;

  /// Mỗi lần định vị (~1 lần/giây), để bản đồ bám theo và vẽ Đường chạy.
  Stream<GpsFix> get positions;

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
    this.signingKey,
  });

  final String sessionId;

  /// Khoá HMAC của Phiên chạy; server chỉ trả ở cửa sổ đầu tiên.
  final String? signingKey;
  final bool windowPassed;
  final int consecutiveFailures;
  final bool biometricApplied;
  final int cadenceSpm;
  final String message;
}
