import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/logout_button.dart';
import '../../tracking/presentation/active_run_screen.dart';
import 'hexagon_layer.dart';
import 'percent_dominance_bar.dart';

/// Màn hình Bản đồ Chiếm đất Liên trường (Campus Turf War)
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  /// Giữa cụm Đại học D2 và Landmark 81.
  static const LatLng initialCenter = LatLng(10.800, 106.718);
  static const double initialZoom = 15;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SISO — Đại Chiến Bình Thạnh'),
        centerTitle: true,
        actions: const [LogoutButton()],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.mapTileUrl,
                userAgentPackageName: 'com.siso.app',
              ),
              const HexagonLayer(),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          // Thanh Dual-Metric Live HUD (% Đất & % Km Toàn cầu) ở đỉnh màn hình
          const Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: PercentDominanceBar(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ActiveRunScreen()),
        ),
        icon: const Icon(Icons.directions_run),
        label: const Text('Chạy'),
      ),
    );
  }
}
