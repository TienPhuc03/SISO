import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Lấy vị trí hiện tại của người dùng để căn camera bản đồ.
abstract class UserLocationSource {
  /// Vị trí hiện tại, hoặc `null` khi tắt định vị, bị từ chối quyền, hết thời gian hay lỗi.
  /// Không bao giờ ném lỗi.
  Future<LatLng?> currentPosition();

  /// Vị trí gần nhất máy còn nhớ (trả ngay, có thể cũ), để căn camera tức thì khi mở bản đồ.
  /// `null` khi không có, chưa có quyền, trên web, hay lỗi. Không xin quyền, không bao giờ ném lỗi.
  Future<LatLng?> lastKnownPosition();
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

  @override
  Future<LatLng?> lastKnownPosition() async {
    // Geolocator không hỗ trợ getLastKnownPosition trên web.
    if (kIsWeb) return null;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : LatLng(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }
}

final userLocationSourceProvider =
    Provider<UserLocationSource>((ref) => const GeolocatorLocationSource());
