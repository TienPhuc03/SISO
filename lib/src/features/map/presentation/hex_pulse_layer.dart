import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/map_state_notifier.dart';

/// Hiệu ứng Pulse trên các ô vừa bị chiếm: màu mới bùng lên rồi mờ dần.
///
/// Màu thật đã đổi ngay ở [HexagonLayer] khi nhận `hex_claimed`; lớp này tách riêng và chỉ vẽ
/// các ô đang nháy, nên mỗi khung hình không phải dựng lại toàn bộ lưới. Phải nằm trong
/// `children` của `FlutterMap`.
class HexPulseLayer extends ConsumerStatefulWidget {
  const HexPulseLayer({super.key});

  static const Duration duration = Duration(milliseconds: 700);

  @override
  ConsumerState<HexPulseLayer> createState() => _HexPulseLayerState();
}

class _HexPulseLayerState extends ConsumerState<HexPulseLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final StreamSubscription<Set<String>> _subscription;
  Set<String> _pulsing = const {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: HexPulseLayer.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) setState(() => _pulsing = const {});
      });
    _subscription = ref.read(mapStateNotifierProvider.notifier).claimedCells.listen((cells) {
      // Sự kiện mới tới khi đang nháy: gộp lại để các ô trước không tắt đột ngột.
      setState(() => _pulsing = {..._pulsing, ...cells});
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pulsing.isEmpty) return const SizedBox.shrink();

    final cells = ref.watch(mapStateNotifierProvider);
    return AnimatedBuilder(
      key: const Key('hex_pulse_layer'),
      animation: _controller,
      builder: (context, _) {
        final fade = 1 - Curves.easeOut.transform(_controller.value);
        return PolygonLayer(
          polygonLabels: false,
          polygons: [
            for (final id in _pulsing)
              if (cells[id] case final cell?)
                Polygon(
                  points: cell.boundary,
                  color: cell.color.withValues(alpha: 0.85 * fade),
                  borderColor: Colors.white.withValues(alpha: fade),
                  borderStrokeWidth: 3,
                ),
          ],
        );
      },
    );
  }
}
