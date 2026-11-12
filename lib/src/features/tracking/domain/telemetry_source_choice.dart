import 'telemetry_log.dart';

/// Nguồn dữ liệu đang chọn cho màn Chạy.
sealed class TelemetrySourceChoice {
  const TelemetrySourceChoice();
}

/// Nguồn giả lập tổng hợp (mặc định).
class SimulatedSourceChoice extends TelemetrySourceChoice {
  const SimulatedSourceChoice();
}

/// Phát lại một log GPS/IMU thật (issue #8).
class ReplaySourceChoice extends TelemetrySourceChoice {
  const ReplaySourceChoice({required this.name, required this.log, this.speedFactor = 1});

  final String name;
  final TelemetryLog log;
  final double speedFactor;
}
