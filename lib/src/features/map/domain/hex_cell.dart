import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/colors.dart';

/// Một ô lục giác H3 res 10 trên bản đồ, kèm ranh giới đã tính sẵn để vẽ.
class HexCell {
  const HexCell({
    required this.h3Index,
    required this.universityId,
    required this.color,
    required this.shieldHp,
    required this.boundary,
  });

  final String h3Index;

  /// `null` nghĩa là ô trung lập, chưa trường nào chiếm.
  final String? universityId;

  /// Màu nhận diện của trường đang giữ ô (chưa áp độ trong suốt).
  final Color color;

  final int shieldHp;

  /// Các đỉnh của lục giác, tính một lần lúc tải.
  final List<LatLng> boundary;

  bool get isNeutral => universityId == null;

  HexCell copyWith({String? universityId, Color? color, int? shieldHp}) => HexCell(
        h3Index: h3Index,
        universityId: universityId ?? this.universityId,
        color: color ?? this.color,
        shieldHp: shieldHp ?? this.shieldHp,
        boundary: boundary,
      );
}

/// Đọc màu từ backend: chấp nhận `#RRGGBB` và `#AARRGGBB`.
/// Giá trị rỗng hoặc sai định dạng trả về màu ô trung lập.
Color parseHexColor(Object? value) {
  if (value is! String) return CampusColors.neutralHex;
  final hex = value.startsWith('#') ? value.substring(1) : value;
  final argb = switch (hex.length) {
    6 => int.tryParse('FF$hex', radix: 16),
    8 => int.tryParse(hex, radix: 16),
    _ => null,
  };
  return argb == null ? CampusColors.neutralHex : Color(argb);
}
