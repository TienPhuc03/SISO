/// [Dev B] Mô hình dữ liệu cảm biến sinh cơ học (IMU Sample & Telemetry Payload)
class ImuSample {
  final double ax;
  final double ay;
  final double az;
  final int timestampMs;

  const ImuSample({
    required this.ax,
    required this.ay,
    required this.az,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'ax': ax,
        'ay': ay,
        'az': az,
        'timestamp': timestampMs,
      };
}
