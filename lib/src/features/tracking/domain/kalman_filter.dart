/// [Dev B] Tầng 1 (Kinematic Gate): Bộ lọc Kalman & Cổng chặn vận tốc (< 9.0 m/s)
/// Khử nhiễu dội sóng GPS (Urban Multipath Drift) cạnh nhà cao tầng
class KalmanFilter {
  static const double maxHumanSpeedMps = 9.0; // 32.4 km/h

  /// Kiểm tra vận tốc tức thời có hợp lệ với sinh học con người hay không
  bool isValidVelocity(double deltaDistanceMeters, double deltaTimeSeconds) {
    if (deltaTimeSeconds <= 0) return false;
    final velocity = deltaDistanceMeters / deltaTimeSeconds;
    return velocity <= maxHumanSpeedMps;
  }
}
