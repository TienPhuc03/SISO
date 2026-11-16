import 'telemetry_log.dart';

/// Nguồn dữ liệu đang chọn cho màn Chạy.
sealed class TelemetrySourceChoice {
  const TelemetrySourceChoice();
}

/// Cảm biến thật của máy (mặc định, và là nguồn duy nhất trong bản phát hành).
class DeviceSourceChoice extends TelemetrySourceChoice {
  const DeviceSourceChoice();
}

/// Nguồn giả lập tổng hợp (chỉ khi debug hoặc demo).
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
