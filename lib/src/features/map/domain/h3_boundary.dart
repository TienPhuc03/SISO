import 'package:flutter/foundation.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';

/// Tính ranh giới cho cả lô ô H3 (chuỗi hex) → danh sách đỉnh lat/lng.
/// Ô không hợp lệ bị bỏ khỏi kết quả.
typedef HexBoundariesFn = Future<Map<String, List<LatLng>>> Function(List<String> h3Indexes);

/// Sinh `count` ô quanh `center` kèm ranh giới (bảng đo hiệu năng).
typedef SyntheticCellsFn = Future<Map<String, List<LatLng>>> Function(LatLng center, int count);

// Biến top-level được khởi tạo lười và riêng cho từng Isolate:
// trong Isolate phụ, thư viện native H3 được nạp lại ở lần dùng đầu tiên.
final H3 _h3 = const H3Factory().load();

/// Bản dùng thư viện H3 thật, chạy trong Isolate phụ để không chặn luồng UI khi tải
/// vài trăm ô. Trên web không có Isolate, `compute` chạy luôn trên luồng chính.
/// Test truyền hàm giả để khỏi nạp thư viện native.
Future<Map<String, List<LatLng>>> h3BoundariesInIsolate(List<String> h3Indexes) async {
  if (h3Indexes.isEmpty) return const {};
  return compute(h3BoundariesSync, h3Indexes, debugLabel: 'h3_boundaries');
}

/// Phần tính toán thật (đồng bộ). Public để Isolate gọi được và để đo/so sánh.
Map<String, List<LatLng>> h3BoundariesSync(List<String> h3Indexes) {
  final result = <String, List<LatLng>>{};
  for (final h3Index in h3Indexes) {
    final cell = BigInt.tryParse(h3Index, radix: 16);
    if (cell == null || !_h3.h3IsValid(cell)) continue;
    result[h3Index] = _h3
        .h3ToGeoBoundary(cell)
        .map((g) => LatLng(g.lat, g.lon))
        .toList(growable: false);
  }
  return result;
}

/// Đổi một điểm GPS sang ô H3 (chuỗi hex, mặc định res 10) trong Isolate phụ.
/// Dùng chung cho bản đồ và module tracking.
Future<String> latLngToCell(LatLng point, {int? resolution}) => compute(
      _latLngToCellSync,
      (point.latitude, point.longitude, resolution ?? AppConstants.h3Resolution),
      debugLabel: 'h3_latlng_to_cell',
    );

String _latLngToCellSync((double, double, int) args) {
  final (lat, lng, res) = args;
  return _h3.geoToH3(GeoCoord(lat: lat, lon: lng), res).toRadixString(16);
}

/// Sinh [count] ô H3 res 10 quanh [center], xếp theo vòng từ trong ra ngoài, kèm ranh giới.
/// Chỉ dùng cho bảng đo hiệu năng (ô giả, không ghi DB). Chạy trong Isolate phụ.
Future<Map<String, List<LatLng>>> syntheticCellsAround(LatLng center, int count) => compute(
      _syntheticCellsSync,
      (center.latitude, center.longitude, count),
      debugLabel: 'h3_synthetic_cells',
    );

Map<String, List<LatLng>> _syntheticCellsSync((double, double, int) args) {
  final (lat, lng, count) = args;
  final origin = _h3.geoToH3(GeoCoord(lat: lat, lon: lng), 10);
  final ids = <String>[origin.toRadixString(16)];
  for (var k = 1; ids.length < count; k++) {
    ids.addAll(_h3.hexRing(origin, k).map((c) => c.toRadixString(16)));
  }
  return h3BoundariesSync(ids.take(count).toList());
}
