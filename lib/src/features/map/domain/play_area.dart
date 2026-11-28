import 'package:latlong2/latlong.dart';

/// Khung bao khu thi đấu của 4 Cụm: phủ mọi Đấu trường (Nam Viên ở phía nam, Hồ Đá ĐHQG ở phía bắc,
/// Lê Văn Tám ở phía tây, ĐHQG ở phía đông) với lề khoảng 1 km. Chỉ dùng để căn camera;
/// khung chiếm đất khi không gửi arenaId ở backend (PLAY_AREA) vẫn là Bình Thạnh.
class PlayArea {
  PlayArea._();

  static const double minLat = 10.710;
  static const double maxLat = 10.895;
  static const double minLng = 106.680;
  static const double maxLng = 106.812;

  /// Tâm mặc định khi chưa có GPS: giữa cụm Đại học D2 và Landmark 81.
  static const LatLng defaultCenter = LatLng(10.800, 106.718);

  /// Tâm cụm ô giả của bảng đo hiệu năng.
  static const LatLng landmark81 = LatLng(10.7951, 106.7219);

  static bool contains(LatLng p) =>
      p.latitude >= minLat && p.latitude <= maxLat && p.longitude >= minLng && p.longitude <= maxLng;
}

/// Điểm camera nên căn tới: vị trí người dùng nếu đang ở trong khu thi đấu,
/// `null` (giữ nguyên camera) khi không có GPS hoặc đang ở ngoài khu.
LatLng? cameraTargetFor(LatLng? userPosition) =>
    userPosition != null && PlayArea.contains(userPosition) ? userPosition : null;
