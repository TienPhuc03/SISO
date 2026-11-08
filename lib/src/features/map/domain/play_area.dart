import 'package:latlong2/latlong.dart';

/// Khung bao khu thi đấu Bình Thạnh & lân cận: phủ cả 4 Đấu trường
/// (Sala ở phía nam, Bờ kè Thanh Đa ở phía bắc) với lề khoảng 1 km.
class PlayArea {
  PlayArea._();

  static const double minLat = 10.755;
  static const double maxLat = 10.830;
  static const double minLng = 106.695;
  static const double maxLng = 106.745;

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
