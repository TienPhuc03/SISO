import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Một mẫu gia tốc kế thô (m/s², có trọng lực) kèm giờ của cảm biến.
class AccelReading {
  const AccelReading({required this.x, required this.y, required this.z, required this.timestamp});

  final double x;
  final double y;
  final double z;
  final DateTime timestamp;
}

/// Một lần nhận vị trí GPS thô.
class GpsReading {
  const GpsReading({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.speedMps,
    required this.isMocked,
    required this.timestamp,
  });

  final double lat;
  final double lng;
  final double accuracyM;

  /// iOS trả -1 khi chưa có tốc độ hợp lệ; giữ nguyên để log phản ánh đúng thiết bị.
  final double speedMps;
  final bool isMocked;
  final DateTime timestamp;
}

/// Luồng cảm biến thô (không lọc, không gom cửa sổ). Dùng cho màn Ghi log (issue #8)
/// và là nền cho nguồn cảm biến thật của Module 3.
abstract class RawSensorStreams {
  Stream<AccelReading> accelerometer();
  Stream<GpsReading> gps();

  /// Xin quyền vị trí; trả thông báo lỗi (tiếng Việt) nếu không dùng được GPS, null nếu ổn.
  Future<String?> ensureLocationPermission();
}

/// Cảm biến thật của thiết bị: `sensors_plus` 50 Hz + `geolocator` (độ chính xác cao nhất).
class DeviceSensorStreams implements RawSensorStreams {
  const DeviceSensorStreams({this.accelPeriod = const Duration(milliseconds: 20)});

  /// 20 ms = 50 Hz.
  final Duration accelPeriod;

  @override
  Stream<AccelReading> accelerometer() =>
      accelerometerEventStream(samplingPeriod: accelPeriod).map(
        (e) => AccelReading(x: e.x, y: e.y, z: e.z, timestamp: e.timestamp),
      );

  @override
  Stream<GpsReading> gps() => Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.fitness,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
        ),
      ).map(
        (p) => GpsReading(
          lat: p.latitude,
          lng: p.longitude,
          accuracyM: p.accuracy,
          speedMps: p.speed,
          isMocked: p.isMocked,
          timestamp: p.timestamp,
        ),
      );

  @override
  Future<String?> ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Định vị (Location Services) đang tắt. Bật trong Cài đặt rồi thử lại.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return 'SISO chưa được cấp quyền vị trí. Vào Cài đặt > SISO > Vị trí để cấp quyền.';
    }
    return null;
  }
}
