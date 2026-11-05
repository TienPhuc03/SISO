import 'package:h3_flutter/h3_flutter.dart';
import 'package:latlong2/latlong.dart';

/// Hàm tính ranh giới một ô H3 (chuỗi hex) thành danh sách đỉnh lat/lng.
typedef HexBoundaryFn = List<LatLng> Function(String h3Index);

// Biến top-level trong Dart được khởi tạo lười: thư viện H3 chỉ nạp khi cần lần đầu.
final H3 _h3 = const H3Factory().load();

/// Bản dùng thư viện H3 thật. Test truyền hàm giả để khỏi nạp thư viện native.
List<LatLng> h3BoundaryOf(String h3Index) => _h3
    .h3ToGeoBoundary(BigInt.parse(h3Index, radix: 16))
    .map((g) => LatLng(g.lat, g.lon))
    .toList(growable: false);
