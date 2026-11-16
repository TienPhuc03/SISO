import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/hex_cell.dart';
import '../providers/map_state_notifier.dart';

/// Lớp vẽ lưới ô lục giác H3 res 10. Phải nằm trong `children` của `FlutterMap`.
class HexagonLayer extends ConsumerWidget {
  const HexagonLayer({super.key});

  static const double ownedAlpha = 0.45;
  static const double neutralAlpha = 0.35;

  /// Ô có chủ mờ dần theo Độ bền: Hao mòn còn 50 thì độ đậm còn một nửa (SRS mục 20).
  static double fillAlpha(HexCell cell) =>
      cell.isNeutral ? neutralAlpha : ownedAlpha * cell.shieldHp.clamp(0, 100) / 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cells = ref.watch(mapStateNotifierProvider);

    if (cells.isEmpty) {
      return const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 32),
          child: Chip(label: Text('Chưa có dữ liệu ô đất')),
        ),
      );
    }

    return PolygonLayer(
      polygonLabels: false,
      polygons: [for (final cell in cells.values) _toPolygon(cell)],
    );
  }

  Polygon _toPolygon(HexCell cell) => Polygon(
        points: cell.boundary,
        color: (cell.isNeutral ? Colors.white : cell.color).withValues(alpha: fillAlpha(cell)),
        borderColor: Colors.black26,
        borderStrokeWidth: 1,
      );
}
