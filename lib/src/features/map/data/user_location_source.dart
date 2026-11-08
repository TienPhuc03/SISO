import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Lấy vị trí hiện tại của người dùng để căn camera bản đồ.
abstract class UserLocationSource {
  /// Vị trí hiện tại, hoặc `null` khi tắt định vị, bị từ chối quyền, hết thời gian hay lỗi.
  /// Không bao giờ ném lỗi.
  Future<LatLng?> currentPosition();
}

/// Bản dùng Geolocator (CoreLocation trên iOS). Xin quyền "khi dùng app" nếu chưa có.
class GeolocatorLocationSource implements UserLocationSource {
  const GeolocatorLocationSource({this.timeLimit = const Duration(seconds: 10)});

  final Duration timeLimit;

  @override
  Future<LatLng?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }
}

final userLocationSourceProvider =
    Provider<UserLocationSource>((ref) => const GeolocatorLocationSource());
