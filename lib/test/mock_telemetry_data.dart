/// Mock Telemetry Data phục vụ kiểm thử bộ lọc Anti-GIGO và Demo Simulator
class MockTelemetryData {
  MockTelemetryData._();

  /// Dữ liệu giả lập sinh viên chạy bộ thật quanh khu vực Bình Thạnh (f_peak ~ 2.7Hz)
  static const List<Map<String, double>> validRunnerSamples = [];

  /// Dữ liệu giả lập người đi xe máy rà chậm 12km/h (f_peak > 8.0Hz, biên độ đứng < 0.25G)
  static const List<Map<String, double>> motorbikeCheatSamples = [];
}
