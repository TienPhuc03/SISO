import 'package:flutter/material.dart';
import 'hexagon_layer.dart';
import 'percent_dominance_bar.dart';

/// [Dev A] Màn hình Bản đồ Chiếm đất Liên trường (Campus Turf War)
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SISO — Đại Chiến Bình Thạnh'),
        centerTitle: true,
      ),
      body: const Stack(
        children: [
          // Lớp bản đồ CartoDB + Lưới lục giác Uber H3 (Resolution 10)
          HexagonLayer(),
          // Thanh Dual-Metric Live HUD (% Đất & % Km Toàn cầu) ở đỉnh màn hình
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: PercentDominanceBar(),
          ),
        ],
      ),
    );
  }
}
