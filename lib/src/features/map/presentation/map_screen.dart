import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/logout_button.dart';
import '../../tracking/presentation/active_run_screen.dart';
import '../../tracking/presentation/sensor_log_screen.dart';
import '../data/user_location_source.dart';
import '../domain/play_area.dart';
import 'hexagon_layer.dart';
import 'percent_dominance_bar.dart';
import 'perf_panel.dart';

/// Màn hình Bản đồ Chiếm đất Liên trường (Campus Turf War)
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.tileProvider});

  /// Nguồn tile nền; `null` = tải qua mạng. Test truyền nguồn giả để không gọi mạng.
  final TileProvider? tileProvider;

  static const LatLng initialCenter = PlayArea.defaultCenter;
  static const double initialZoom = 15;
  static const double userZoom = 16;

  /// Nhấn giữ tiêu đề lâu chừng này để mở bảng đo hiệu năng.
  static const Duration perfPanelHold = Duration(seconds: 3);

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  LatLng? _userPosition;
  bool _locating = false;

  /// Chỉ hiện vòng xoay trên nút khi người dùng tự bấm (lần căn tự động lúc mở bản đồ thì chạy ngầm).
  bool _showLocatingSpinner = false;
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    // Căn camera một lần khi mở bản đồ; lỗi/không có GPS thì giữ tâm mặc định, không báo gì.
    _locateUser(userInitiated: false);
  }

  /// Lấy vị trí rồi căn camera nếu người dùng đang ở trong khu thi đấu.
  /// [userInitiated] = bấm nút "Vị trí của tôi": khi đó báo lý do nếu không căn được.
  Future<void> _locateUser({required bool userInitiated}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _showLocatingSpinner = userInitiated;
    });
    final position = await ref.read(userLocationSourceProvider).currentPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _showLocatingSpinner = false;
      _userPosition = position;
    });

    final target = cameraTargetFor(position);
    if (target != null && _mapReady) {
      _mapController.move(target, MapScreen.userZoom);
      return;
    }
    if (!userInitiated) return;

    final message = position == null
        ? 'Không lấy được vị trí. Hãy bật định vị và cho phép SISO dùng vị trí.'
        : 'Bạn đang ở ngoài khu thi đấu Bình Thạnh, bản đồ giữ nguyên khu vực Đấu trường.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _startHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer(MapScreen.perfPanelHold, () {
      ref.read(perfPanelOpenProvider.notifier).state = true;
    });
  }

  void _cancelHold() => _holdTimer?.cancel();

  @override
  Widget build(BuildContext context) {
    final perfOpen = ref.watch(perfPanelOpenProvider);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          key: const Key('map_title'),
          onTapDown: (_) => _startHold(),
          onTapUp: (_) => _cancelHold(),
          onTapCancel: _cancelHold,
          child: const Text('SISO — Đại Chiến Bình Thạnh'),
        ),
        centerTitle: true,
        actions: const [LogoutButton()],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: MapScreen.initialCenter,
              initialZoom: MapScreen.initialZoom,
              onMapReady: _onMapReady,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.mapTileUrl,
                userAgentPackageName: 'com.siso.app',
                tileProvider: widget.tileProvider,
              ),
              const HexagonLayer(),
              if (_userPosition case final p?)
                MarkerLayer(markers: [
                  Marker(
                    point: p,
                    width: 22,
                    height: 22,
                    child: const DecoratedBox(
                      key: Key('user_location_marker'),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 3)),
                      ),
                    ),
                  ),
                ]),
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
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              key: const Key('my_location_button'),
              heroTag: 'my_location',
              tooltip: 'Vị trí của tôi',
              onPressed: _locating ? null : () => _locateUser(userInitiated: true),
              child: _showLocatingSpinner
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          if (perfOpen)
            const Positioned(
              left: 8,
              right: 8,
              bottom: 80,
              child: PerfPanel(),
            ),
        ],
      ),
      // Nhấn giữ nút "Chạy" mở màn Ghi log cảm biến (issue #8; ẩn, dùng được cả bản release IPA)
      floatingActionButton: GestureDetector(
        key: const Key('run_fab_hold'),
        onLongPress: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SensorLogScreen()),
        ),
        child: FloatingActionButton.extended(
          heroTag: 'run',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ActiveRunScreen()),
          ),
          icon: const Icon(Icons.directions_run),
          label: const Text('Chạy'),
        ),
      ),
    );
  }
}
