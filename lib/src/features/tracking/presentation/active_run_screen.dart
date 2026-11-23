import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/siso_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../leaderboard/providers/season_rank_provider.dart';
import '../../map/data/user_location_source.dart';
import '../../profile/providers/profile_providers.dart';
import '../../map/domain/hex_cell.dart' show parseHexColor;
import '../../map/domain/play_area.dart';
import '../data/simulated_telemetry_source.dart';
import '../providers/tracking_session_notifier.dart';
import 'telemetry_source_picker.dart';

/// Màn hình Phiên chạy: S-05 Chuẩn bị chạy, S-06 Đang chạy (cảnh báo vàng, mất GPS / mạng),
/// màn hình đỏ khi Phiên chạy bị loại và Tổng kết khi kết thúc hợp lệ.
class ActiveRunScreen extends ConsumerStatefulWidget {
  const ActiveRunScreen({super.key, this.tileProvider});

  /// Nguồn tile nền; `null` = tải qua mạng. Test truyền nguồn giả để không gọi mạng.
  final TileProvider? tileProvider;

  @override
  ConsumerState<ActiveRunScreen> createState() => _ActiveRunScreenState();
}

class _ActiveRunScreenState extends ConsumerState<ActiveRunScreen> {
  Timer? _ticker;
  DateTime? _startedAt;
  int _seconds = 0;

  // shortcut: quãng đường hiển thị lúc chạy là ước lượng (tích phân tốc độ mỗi giây trên máy);
  // số km chính thức là số server trả khi kết thúc. Đổi sang số server nếu API trả km theo từng cửa sổ.
  double _km = 0;
  int _cadenceSum = 0;
  int _cadenceCount = 0;

  /// Phiên chạy kết thúc hợp lệ ngay trên màn này: hiện Tổng kết (mở lại màn thì về Chuẩn bị chạy).
  bool _showSummary = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onRunChanged(RunState? previous, RunState next) {
    final wasRunning = previous?.status == TrackingStatus.tracking;
    final running = next.status == TrackingStatus.tracking;
    if (!wasRunning && running) {
      _ticker?.cancel();
      setState(() {
        _startedAt = DateTime.now();
        _seconds = 0;
        _km = 0;
        _cadenceSum = 0;
        _cadenceCount = 0;
        _showSummary = false;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (wasRunning && !running) {
      _ticker?.cancel();
      // Thanh % trên Bản đồ giữ seasonRankProvider sống suốt app nên phải tải lại tay, không thì km mới không hiện.
      if (next.addedKm != null) {
        ref.invalidate(seasonRankProvider);
        ref.invalidate(profileProvider); // Km cá nhân, số Phiên chạy
      }
      if (next.status == TrackingStatus.idle && next.addedKm != null && next.errorCode == null) {
        setState(() => _showSummary = true);
      }
    }
    if (previous?.status != TrackingStatus.rejected && next.status == TrackingStatus.rejected) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
    }
  }

  void _tick() {
    if (!mounted) return;
    final run = ref.read(trackingSessionNotifierProvider);
    if (run.paused) return; // Tạm dừng: không tính thời gian, quãng đường, Nhịp bước
    setState(() {
      _seconds++;
      if (!run.gpsSearching) _km += run.speedKmh / 3600;
      if (run.cadenceSpm case final spm?) {
        _cadenceSum += spm;
        _cadenceCount++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(trackingSessionNotifierProvider);
    ref.listen(trackingSessionNotifierProvider, _onRunChanged);

    if (run.status == TrackingStatus.rejected) {
      return _RejectedScreen(code: run.errorCode ?? 'ERR_202', message: run.errorMessage ?? '');
    }
    if (_showSummary && run.status == TrackingStatus.idle && run.addedKm != null) {
      return _SummaryScreen(
        km: run.addedKm!,
        seconds: _seconds,
        startedAt: _startedAt ?? DateTime.now(),
        avgCadence: _cadenceCount == 0 ? null : (_cadenceSum / _cadenceCount).round(),
      );
    }

    final running = run.status == TrackingStatus.tracking || run.status == TrackingStatus.evaluatingLoop;
    // Rời màn khi đang chạy sẽ huỷ Phiên chạy (provider autoDispose): chặn Back lỡ tay, bắt bấm Dừng.
    // Đăng xuất (AuthGate gọi popUntil) không bị chặn vì Navigator.pop không hỏi PopScope.
    return PopScope(
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            key: Key('run_back_blocked'),
            content: Text('Đang chạy: bấm Dừng để kết thúc Phiên chạy trước khi thoát.'),
          ));
      },
      child: Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mapHeight = constraints.maxHeight * (running ? 0.48 : 0.55);
          return Stack(
            children: [
              SizedBox(height: mapHeight + 28, child: _RunMap(tileProvider: widget.tileProvider)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      SisoCircleButton(
                        icon: Icons.chevron_left,
                        tooltip: 'Quay lại',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(child: Center(child: _StatusPill(run: run, running: running))),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                top: mapHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    color: SisoColors.card,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: SisoColors.border)),
                    boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 24, offset: Offset(0, -8))],
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCE4E5),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (running) ..._runningPanel(run) else ..._readyPanel(run),
                      ..._devTools(run),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  List<Widget> _readyPanel(RunState run) {
    final notifier = ref.read(trackingSessionNotifierProvider.notifier);
    return [
      Container(
        padding: const EdgeInsets.only(bottom: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SisoColors.divider))),
        child: const Row(
          children: [
            Expanded(child: _Stat(value: '00:00', label: 'Thời gian', muted: true)),
            Expanded(child: _Stat(value: '0,00', unit: 'km', label: 'Quãng đường', muted: true)),
            Expanded(child: _Stat(value: '--', unit: 'SPM', label: 'Nhịp bước', muted: true)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Chạy khép vòng trong Đấu trường để chiếm đất. Chạy ở bất kỳ đâu cũng được cộng km cho trường.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, height: 1.45, color: SisoColors.body),
      ),
      if (run.errorCode == pauseTimeoutCode) ...[
        // Không phải lỗi: Phiên tự kết thúc vì Tạm dừng quá lâu.
        const SizedBox(height: 12),
        _Banner.info(Icons.timer_off_outlined, run.errorMessage ?? ''),
      ] else if (run.errorCode != null) ...[
        const SizedBox(height: 12),
        _Banner.error('[${run.errorCode}] ${runErrorText(run.errorCode!, run.errorMessage ?? '')}'),
      ],
      const SizedBox(height: 20),
      Center(
        child: _RoundAction(
          size: 88,
          color: SisoColors.primary,
          onPressed: notifier.startRun,
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 52),
        ),
      ),
      const SizedBox(height: 10),
      const Center(child: Text('Bắt đầu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
    ];
  }

  List<Widget> _runningPanel(RunState run) {
    final notifier = ref.read(trackingSessionNotifierProvider.notifier);
    return [
      Center(
        child: Text(
          formatDuration(_seconds),
          style: const TextStyle(
            fontSize: 54,
            height: 1,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 4),
      const Center(
        child: Text('THỜI GIAN',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: SisoColors.body)),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: SisoColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(child: _Stat(value: viDecimal(_km, 2), unit: 'km', label: 'Quãng đường')),
            const _VDivider(),
            Expanded(child: _Stat(value: formatPace(run.speedKmh), unit: '/km', label: 'Pace')),
            const _VDivider(),
            Expanded(child: _Stat(value: run.cadenceSpm?.toString() ?? '--', unit: 'SPM', label: 'Nhịp bước')),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        switch (run) {
          RunState(paused: false) => 'Tốc độ hiện tại ${viDecimal(run.speedKmh)} km/h · Nhịp bước cập nhật mỗi ~5 giây',
          RunState(autoPaused: true) =>
            'Tự tạm dừng vì bạn đang đứng yên, chạy lại là tự tiếp tục. Không tính thời gian và quãng đường lúc này.',
          _ => 'Đã tạm dừng: không tính thời gian và quãng đường. Tạm dừng quá 30 phút Phiên chạy sẽ tự kết thúc.',
        },
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: SisoColors.caption),
      ),
      if (run.paused && run.pauseExpiring)
        _Banner.warning('Bạn đã tạm dừng 25 phút. Phiên chạy sẽ tự kết thúc sau 5 phút nữa nếu không chạy tiếp.'),
      if (run.windowWarning)
        _Banner.warning('Nhịp bước không khớp tốc độ. Thêm một lần nữa Phiên chạy sẽ bị loại.'),
      if (run.gpsSearching)
        _Banner.info(Icons.satellite_alt_outlined, 'Đang tìm tín hiệu vệ tinh... Quãng đường lúc này chưa được tính.'),
      if (run.connectionIssue) _Banner.info(Icons.wifi_off, 'Mất kết nối, cửa sổ vừa rồi chưa được kiểm định.'),
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          run.paused
              ? _LabeledAction(
                  key: const Key('run_resume'),
                  label: 'Tiếp tục',
                  labelColor: SisoColors.primary,
                  button: _RoundAction(
                    size: 76,
                    color: SisoColors.primary,
                    onPressed: notifier.resumeRun,
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                  ),
                )
              : _LabeledAction(
                  key: const Key('run_pause'),
                  label: 'Tạm dừng',
                  labelColor: SisoColors.ink,
                  button: _RoundAction(
                    size: 76,
                    color: SisoColors.card,
                    borderColor: SisoColors.ink,
                    onPressed: notifier.pauseRun,
                    child: const Icon(Icons.pause_rounded, color: SisoColors.ink, size: 40),
                  ),
                ),
          _LabeledAction(
            key: const Key('run_stop'),
            label: 'Kết thúc',
            labelColor: SisoColors.danger,
            button: _RoundAction(
              size: 76,
              color: SisoColors.card,
              borderColor: SisoColors.danger,
              onPressed: notifier.stopRun,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: SisoColors.danger, borderRadius: BorderRadius.circular(5)),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _devTools(RunState run) {
    final source = ref.watch(telemetryWindowSourceProvider);
    final allowFakeSources = ref.watch(allowFakeSourcesProvider);
    return [
      if (allowFakeSources) ...[
        const SizedBox(height: 16),
        TelemetrySourcePicker(enabled: run.status != TrackingStatus.tracking),
      ],
      if (allowFakeSources && source is SimulatedTelemetrySource) _SimulatorPanel(source: source),
    ];
  }
}

/// 08:42 hoặc 1:08:42
String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = (seconds ~/ 60) % 60, s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Pace (phút/km) từ tốc độ km/h: 10,2 km/h -> 5:53. Đứng yên -> --:--.
String formatPace(double speedKmh) {
  if (speedKmh < 1) return '--:--';
  final secPerKm = (3600 / speedKmh).round();
  return '${secPerKm ~/ 60}:${(secPerKm % 60).toString().padLeft(2, '0')}';
}

/// Bản đồ phía trên màn Chạy: bám theo vị trí mới nhất và vẽ Đường chạy của Phiên hiện tại.
class _RunMap extends ConsumerStatefulWidget {
  const _RunMap({this.tileProvider});

  final TileProvider? tileProvider;

  @override
  ConsumerState<_RunMap> createState() => _RunMapState();
}

class _RunMapState extends ConsumerState<_RunMap> {
  final _controller = MapController();
  bool _ready = false;

  /// Vị trí của máy trước khi bắt đầu chạy (chưa có Đường chạy).
  LatLng? _userPosition;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final source = ref.read(userLocationSourceProvider);
    final position = await source.lastKnownPosition() ?? await source.currentPosition();
    if (!mounted || position == null) return;
    setState(() => _userPosition = position);
    if (ref.read(trackingSessionNotifierProvider).route.isEmpty) _follow(position);
  }

  void _follow(LatLng point) {
    if (_ready) _controller.move(point, _controller.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(trackingSessionNotifierProvider.select((s) => s.route));
    ref.listen(trackingSessionNotifierProvider.select((s) => s.route), (_, next) {
      if (next.isNotEmpty) _follow(next.last);
    });
    final here = route.isNotEmpty ? route.last : _userPosition;

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: here ?? PlayArea.defaultCenter,
        initialZoom: 17,
        onMapReady: () {
          _ready = true;
          final target = ref.read(trackingSessionNotifierProvider).route.lastOrNull ?? _userPosition;
          if (target != null) _follow(target);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: AppConstants.mapTileUrl,
          userAgentPackageName: 'com.siso.app',
          tileProvider: widget.tileProvider,
        ),
        if (route.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: route,
              strokeWidth: 5,
              color: SisoColors.primary,
              borderStrokeWidth: 1.5,
              borderColor: Colors.white,
            ),
          ]),
        if (here != null)
          CircleLayer(circles: [
            CircleMarker(
              point: here,
              radius: 8,
              color: SisoColors.primary,
              borderColor: Colors.white,
              borderStrokeWidth: 3,
            ),
          ]),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.run, required this.running});

  final RunState run;
  final bool running;

  @override
  Widget build(BuildContext context) {
    Widget item(Color dot, String text, {bool bold = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                  color: bold ? SisoColors.ink : SisoColors.body,
                )),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: SisoColors.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: SisoColors.border),
      ),
      child: running
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                run.paused
                    ? item(SisoColors.caption, run.autoPaused ? 'Tự tạm dừng' : 'Tạm dừng', bold: true)
                    : item(SisoColors.recording, 'Đang ghi', bold: true),
                Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 12), color: SisoColors.border),
                run.gpsSearching
                    ? item(SisoColors.gpsSearching, 'Đang tìm GPS')
                    : item(SisoColors.gpsGood, 'GPS tốt'),
              ],
            )
          : item(SisoColors.ready, 'GPS sẵn sàng', bold: true),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.unit, this.muted = false});

  final String value;
  final String label;
  final String? unit;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final valueColor = muted ? SisoColors.caption : SisoColors.ink;
    return Column(
      children: [
        Text.rich(
          TextSpan(
            text: value,
            children: [
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted ? valueColor : SisoColors.body),
                ),
            ],
          ),
          style: TextStyle(
            fontSize: muted ? 22 : 21,
            fontWeight: FontWeight.w700,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: muted ? 12 : 11, fontWeight: FontWeight.w500, color: SisoColors.caption)),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 36, color: SisoColors.border);
}

/// Nút tròn kèm nhãn bên dưới; key đặt ở đây để test tìm cả cụm.
class _LabeledAction extends StatelessWidget {
  const _LabeledAction({super.key, required this.button, required this.label, required this.labelColor});

  final Widget button;
  final String label;
  final Color labelColor;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        // Trình đọc màn hình đọc nút kèm nhãn ("Tạm dừng, nút") thay vì một nút không tên.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button,
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: labelColor)),
          ],
        ),
      );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.size,
    required this.color,
    required this.onPressed,
    required this.child,
    this.borderColor,
  });

  final double size;
  final Color color;
  final Color? borderColor;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: borderColor == null ? 8 : 1,
      shadowColor: borderColor == null ? const Color(0x59008689) : null,
      shape: CircleBorder(
        side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!, width: 2.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(dimension: size, child: Center(child: child)),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner._(this.bg, this.border, this.fg, this.icon, this.text);

  factory _Banner.warning(String text) => _Banner._(SisoColors.warningBg, SisoColors.warningBorder,
      SisoColors.warningText, Icons.warning_amber_rounded, text);

  factory _Banner.info(IconData icon, String text) =>
      _Banner._(SisoColors.infoBg, SisoColors.infoBorder, SisoColors.body, icon, text);

  factory _Banner.error(String text) =>
      _Banner._(const Color(0xFFFDECEC), const Color(0xFFF5C6C6), SisoColors.danger, Icons.error_outline, text);

  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w500, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Màn hình đỏ khi Phiên chạy bị loại (bằng chứng "còi đỏ" cho buổi test thực địa).
class _RejectedScreen extends StatelessWidget {
  const _RejectedScreen({required this.code, required this.message});

  final String code;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SisoColors.danger,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block, size: 96, color: Colors.white),
                    const SizedBox(height: 28),
                    const Text(
                      'PHIÊN CHẠY BỊ LOẠI',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      code,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 290),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95), fontSize: 16, height: 1.6, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: Colors.white, width: 1.75),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Về bản đồ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tổng kết Phiên chạy hợp lệ. Km là số server đã cộng; thời gian, pace, nhịp bước đo trên máy.
class _SummaryScreen extends ConsumerWidget {
  const _SummaryScreen({required this.km, required this.seconds, required this.startedAt, this.avgCadence});

  final double km;
  final int seconds;
  final DateTime startedAt;
  final int? avgCadence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final campus = session is AuthSignedIn ? session.user.university : null;
    final avgSpeed = seconds == 0 ? 0.0 : km / (seconds / 3600);
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(startedAt.day)}/${two(startedAt.month)}/${startedAt.year} · '
        '${two(startedAt.hour)}:${two(startedAt.minute)}';
    final kmText = viDecimal(km, 2);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
              children: [
                Row(
                  children: [
                    SisoCircleButton(
                      icon: Icons.close,
                      size: 36,
                      tooltip: 'Đóng',
                      background: const Color(0xFFEAEAEA),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tổng kết phiên chạy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(when,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SisoColors.body)),
                        ],
                      ),
                    ),
                    if (campus != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: SisoColors.tint,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: SisoColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CampusDot(color: parseHexColor(campus.color), size: 8),
                            const SizedBox(width: 6),
                            Text(campus.shortCode,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: SisoColors.primaryDark)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SisoColors.successBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SisoColors.successBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, color: SisoColors.successText, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('+$kmText km cho ${campus?.shortCode ?? 'trường'}',
                                      style: const TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700, color: SisoColors.successText)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: SisoColors.successText,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Text('HỢP LỆ',
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.8)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('Đã kết thúc Phiên chạy, cộng $kmText km cho bạn và trường.',
                                style: const TextStyle(fontSize: 12, height: 1.35, color: SisoColors.successText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.1,
                  children: [
                    _SummaryStat(label: 'Quãng đường', value: kmText, unit: 'km'),
                    _SummaryStat(label: 'Thời gian', value: formatDuration(seconds)),
                    _SummaryStat(label: 'Pace trung bình', value: formatPace(avgSpeed), unit: '/km'),
                    _SummaryStat(label: 'Tốc độ trung bình', value: viDecimal(avgSpeed), unit: 'km/h'),
                    _SummaryStat(label: 'Nhịp bước trung bình', value: avgCadence?.toString() ?? '--', unit: 'SPM'),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Text('Về bản đồ'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 20)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: sisoCard(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: SisoColors.caption)),
          Text.rich(
            TextSpan(
              text: value,
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SisoColors.body),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Lời giải thích tiếng Việt cho lỗi làm dừng Phiên chạy (không phải bị loại).
/// Thông báo gốc của server (thường là tiếng Anh, do kiểm tra DTO) chỉ giữ lại cho mã lạ.
String runErrorText(String code, String message) => switch (code) {
      'HTTP_400' => 'Dữ liệu cảm biến gửi lên không đúng định dạng nên Phiên chạy đã dừng. '
          'Đây không phải gian lận; hãy chạy lại, nếu lặp lại thì báo nhóm phát triển.',
      'HTTP_401' => 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại rồi chạy tiếp.',
      SisoErrorCodes.sessionNotFound => 'Phiên chạy đã kết thúc hoặc không còn trên máy chủ. Bấm "Bắt đầu chạy" để mở Phiên mới.',
      SisoErrorCodes.network when message.isEmpty => 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
      _ when code.startsWith('HTTP_5') => 'Máy chủ đang gặp sự cố. Thử lại sau ít phút.',
      _ => message,
    };

/// Bảng điều khiển nguồn GIẢ LẬP: đổi dáng di chuyển giữa chừng và (khi dev) dán JWT.
class _SimulatorPanel extends StatefulWidget {
  const _SimulatorPanel({required this.source});

  final SimulatedTelemetrySource source;

  @override
  State<_SimulatorPanel> createState() => _SimulatorPanelState();
}

class _SimulatorPanelState extends State<_SimulatorPanel> {
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nguồn giả lập (không phải cảm biến thật)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<SimulatedGait>(
              segments: [
                for (final g in SimulatedGait.values) ButtonSegment(value: g, label: Text(g.label)),
              ],
              selected: {widget.source.gait},
              onSelectionChanged: (s) => setState(() => widget.source.gait = s.first),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              Text(
                ApiClient.hasAccessToken ? 'Đã có JWT.' : 'Chưa có JWT: dán accessToken lấy từ Swagger (verify-otp).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(labelText: 'accessToken (chỉ khi dev)'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => ApiClient.setAccessToken(_tokenController.text.trim())),
                    child: const Text('Dùng'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
