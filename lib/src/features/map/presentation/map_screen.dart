import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/siso_theme.dart';
import '../../auth/presentation/logout_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../forum/presentation/forum_screen.dart';
import '../../leaderboard/presentation/leaderboard_screen.dart';
import '../../leaderboard/providers/season_rank_provider.dart';
import '../../profile/presentation/profile_button.dart';
import '../../tracking/presentation/active_run_screen.dart';
import '../../tracking/presentation/sensor_log_screen.dart';
import '../data/user_location_source.dart';
import '../domain/hex_cell.dart' show parseHexColor;
import '../domain/play_area.dart';
import 'hex_pulse_layer.dart';
import 'hexagon_layer.dart';
import 'percent_dominance_bar.dart';
import 'perf_panel.dart';
import 'siso_bottom_nav.dart';

/// Màn hình Bản đồ Chiếm đất Liên trường (Campus Turf War)
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.tileProvider});

  /// Nguồn tile nền; `null` = tải qua mạng. Test truyền nguồn giả để không gọi mạng.
  final TileProvider? tileProvider;

  static const LatLng initialCenter = PlayArea.defaultCenter;
  static const String title = 'SISO';
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

  /// Người dùng đã bấm "Vị trí của tôi" và đang chờ kết quả (kể cả khi bấm lúc lần lấy GPS
  /// tự động còn chạy ngầm): hiện vòng xoay, luôn căn camera và báo lý do nếu không căn được.
  bool _userWaiting = false;

  /// Người dùng đã tự kéo/zoom bản đồ: lần căn TỰ ĐỘNG không được giật camera về nữa.
  bool _userMovedMap = false;
  Timer? _holdTimer;

  /// Theo dõi vị trí liên tục (chỉ cập nhật chấm vị trí, không di chuyển camera).
  StreamSubscription<LatLng>? _positionSub;

  @override
  void dispose() {
    _positionSub?.cancel();
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
  ///
  /// - Căn ngay bằng vị trí gần nhất máy còn nhớ (nếu có), rồi tinh chỉnh bằng lần đo GPS mới.
  /// - [userInitiated] = bấm nút "Vị trí của tôi": luôn căn camera và báo lý do nếu không căn được.
  ///   Bấm khi lần lấy GPS tự động còn đang chạy thì chờ chung kết quả đó (không gọi GPS lần hai).
  /// - Lần căn tự động bỏ qua việc di chuyển camera nếu người dùng đã tự kéo/zoom bản đồ.
  Future<void> _locateUser({required bool userInitiated}) async {
    if (userInitiated) setState(() => _userWaiting = true);
    if (_locating) return;
    _locating = true;

    final source = ref.read(userLocationSourceProvider);
    final lastKnown = cameraTargetFor(await source.lastKnownPosition());
    if (!mounted) return;
    if (lastKnown != null) {
      setState(() => _userPosition = lastKnown);
      _moveCameraIfAllowed(lastKnown);
    }

    // Mở Bản đồ không xin quyền vị trí: chỉ xin khi chuẩn bị chạy, hoặc khi bấm "Vị trí của tôi".
    final position = await source.currentPosition(requestPermission: userInitiated);
    if (!mounted) return;
    final userWaiting = _userWaiting;
    setState(() {
      _locating = false;
      _userWaiting = false;
      if (position != null) _userPosition = position;
    });

    if (position != null) _followPosition(source);

    final target = cameraTargetFor(position);
    if (target != null) {
      _moveCameraIfAllowed(target, force: userWaiting);
      return;
    }
    if (!userWaiting) return;

    final String message;
    if (position != null) {
      // Người dùng chủ động bấm: luôn đưa bản đồ tới chỗ họ, kể cả ngoài khu thi đấu.
      _moveCameraIfAllowed(position, force: true);
      message = 'Bạn đang ở ngoài khu thi đấu Bình Thạnh. Chạy ở đây vẫn được cộng km, '
          'nhưng chỉ chiếm được đất trong các Đấu trường.';
    } else if (lastKnown != null) {
      _moveCameraIfAllowed(lastKnown, force: true);
      message = 'Chưa lấy được vị trí mới, đang hiện vị trí gần nhất máy còn nhớ.';
    } else {
      message = 'Không lấy được vị trí. Hãy bật định vị và cho phép SISO dùng vị trí.';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Bắt đầu nghe vị trí liên tục (một lần, sau khi đã có quyền vị trí).
  void _followPosition(UserLocationSource source) {
    _positionSub ??= source.positionStream().listen((p) {
      if (mounted) setState(() => _userPosition = p);
    });
  }

  /// Căn camera tới [target]. Lần tự động ([force] = false) không giật camera nếu người dùng
  /// đã tự kéo/zoom bản đồ; khi người dùng bấm nút thì luôn căn.
  void _moveCameraIfAllowed(LatLng target, {bool force = false}) {
    if (!_mapReady) return;
    if (!force && _userMovedMap) return;
    _mapController.move(target, MapScreen.userZoom);
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) _userMovedMap = true;
  }

  void _startHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer(MapScreen.perfPanelHold, () {
      ref.read(perfPanelOpenProvider.notifier).state = true;
    });
  }

  void _cancelHold() => _holdTimer?.cancel();

  void _openLeaderboard() {
    // Bản đồ giữ seasonRankProvider sống nên số cũ không tự hết hạn: lấy số mới (kể cả km của trường khác).
    ref.invalidate(seasonRankProvider);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen()));
  }

  void _openRun() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ActiveRunScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final perfOpen = ref.watch(perfPanelOpenProvider);
    final session = ref.watch(authSessionProvider);
    final campus = session is AuthSignedIn ? session.user.university : null;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: MapScreen.initialCenter,
              initialZoom: MapScreen.initialZoom,
              onMapReady: _onMapReady,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.mapTileUrl,
                userAgentPackageName: 'com.siso.app',
                tileProvider: widget.tileProvider,
              ),
              const HexagonLayer(),
              const HexPulseLayer(),
              if (_userPosition case final p?)
                MarkerLayer(markers: [
                  Marker(
                    point: p,
                    width: 44,
                    height: 44,
                    child: const UserLocationDot(key: Key('user_location_marker')),
                  ),
                ]),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          // Thanh nổi trên cùng + Dual-Metric Live HUD (% Đất & % Km)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: sisoCard(radius: 20).copyWith(
                      color: SisoColors.card.withValues(alpha: 0.95),
                      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          key: const Key('map_title'),
                          onTapDown: (_) => _startHold(),
                          onTapUp: (_) => _cancelHold(),
                          onTapCancel: _cancelHold,
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: SisoColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const HexIcon(size: 16),
                              ),
                              const SizedBox(width: 8),
                              const Text(MapScreen.title,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (campus != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: SisoColors.bg,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: SisoColors.border),
                            ),
                            child: Row(
                              children: [
                                CampusDot(color: parseHexColor(campus.color)),
                                const SizedBox(width: 6),
                                Text(campus.shortName,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const ProfileButton(),
                        const SizedBox(width: 8),
                        const LogoutButton(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const PercentDominanceBar(),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 124,
            child: SafeArea(
              top: false,
              child: Material(
                key: const Key('my_location_button'),
                color: SisoColors.card,
                shape: const CircleBorder(side: BorderSide(color: SisoColors.border)),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _userWaiting ? null : () => _locateUser(userInitiated: true),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: _userWaiting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, color: SisoColors.primary, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (perfOpen)
            const Positioned(
              left: 8,
              right: 8,
              bottom: 180,
              child: PerfPanel(),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SisoBottomNav(
              active: SisoTab.map,
              onMap: () {},
              onRun: _openRun,
              onLeaderboard: _openLeaderboard,
              onForum: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ForumScreen())),
              onRunLongPress: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SensorLogScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chấm vị trí người dùng: lõi teal, vòng trắng, quầng mờ.
class UserLocationDot extends StatelessWidget {
  const UserLocationDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: SisoColors.primary.withValues(alpha: 0.2), shape: BoxShape.circle),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: SisoColors.primary,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 4)),
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
      ),
    );
  }
}
