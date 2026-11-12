import 'dart:async';

import '../domain/biometric_model.dart';
import '../domain/telemetry_log.dart';
import '../domain/telemetry_window.dart';

/// Sai số GPS dùng khi log hoàn toàn không có vị trí: cố ý > 20 m để server báo ERR_203,
/// đúng với thực tế "không có GPS" thay vì giả vờ là tín hiệu tốt.
const double noGpsAccuracyM = 999;

/// Một cửa sổ dựng từ log, kèm thời điểm (ms trong log) mẫu cuối của nó được ghi.
class ReplayWindow {
  const ReplayWindow({required this.endTMs, required this.startTMs, required this.window});

  final int startTMs;
  final int endTMs;
  final TelemetryWindow window;
}

/// Cắt log thành các cửa sổ 256 mẫu liên tiếp, không chồng nhau (bỏ phần lẻ cuối log).
///
/// - `averageSpeedMps`: trung bình tốc độ GPS hợp lệ (>= 0) trong khoảng của cửa sổ;
///   không có thì lấy lần GPS gần nhất trước đó; không có nữa thì 0.
/// - `horizontalAccuracy`: sai số TỆ NHẤT trong khoảng (hoặc lần gần nhất trước đó).
/// - `isMocked`: true nếu có bất kỳ lần GPS nào trong khoảng bị đánh dấu giả.
/// - `timestampMs` của mẫu = [baseEpochMs] + t trong log.
List<ReplayWindow> buildReplayWindows(TelemetryLog log, {required int baseEpochMs}) {
  final result = <ReplayWindow>[];
  const size = TelemetryWindow.size;
  for (var start = 0; start + size <= log.accel.length; start += size) {
    final chunk = log.accel.sublist(start, start + size);
    final t0 = chunk.first.tMs;
    final t1 = chunk.last.tMs;

    var gps = log.gps.where((g) => g.tMs >= t0 && g.tMs <= t1).toList();
    if (gps.isEmpty) {
      final before = log.gps.where((g) => g.tMs < t0);
      if (before.isNotEmpty) gps = [before.last];
    }

    final speeds = gps.map((g) => g.speedMps).where((s) => s >= 0).toList();
    final avgSpeed = speeds.isEmpty ? 0.0 : speeds.reduce((a, b) => a + b) / speeds.length;
    final accuracy =
        gps.isEmpty ? noGpsAccuracyM : gps.map((g) => g.accuracyM).reduce((a, b) => a > b ? a : b);

    result.add(ReplayWindow(
      startTMs: t0,
      endTMs: t1,
      window: TelemetryWindow(
        samples: [
          for (final a in chunk)
            ImuSample(ax: a.x, ay: a.y, az: a.z, timestampMs: baseEpochMs + a.tMs),
        ],
        averageSpeedMps: avgSpeed,
        horizontalAccuracy: accuracy,
        isMocked: gps.any((g) => g.isMocked),
      ),
    ));
  }
  return result;
}

/// Nguồn PHÁT LẠI log GPS/IMU thật (issue #8): dùng trên Chrome/emulator và cho Demo Simulator.
///
/// Phát theo nhịp thời gian của log nhân [speedFactor] (1 = thời gian thật). Tốc độ HUD lấy từ
/// các bản ghi GPS; mỗi cửa sổ 256 mẫu phát ra khi tới thời điểm mẫu cuối của nó. Hết log thì dừng.
class ReplayTelemetrySource implements TelemetryWindowSource {
  ReplayTelemetrySource({
    required this.log,
    required this.name,
    this.speedFactor = 1,
    this.tick = const Duration(milliseconds: 100),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TelemetryLog log;

  /// Tên hiển thị (tên file log).
  final String name;

  /// Đổi được trước khi bấm Bắt đầu.
  double speedFactor;
  final Duration tick;
  final DateTime Function() _clock;

  final _speedController = StreamController<double>.broadcast();
  final _windowController = StreamController<TelemetryWindow>.broadcast();
  Timer? _timer;
  List<ReplayWindow> _windows = const [];
  int _nextWindow = 0;
  int _nextGps = 0;
  double _logicalMs = 0;
  bool _finished = false;

  @override
  Stream<double> get speedMps => _speedController.stream;

  @override
  Stream<TelemetryWindow> get windows => _windowController.stream;

  /// Số cửa sổ đầy đủ trong log.
  int get windowCount => buildReplayWindows(log, baseEpochMs: 0).length;

  /// Đã phát hết log.
  bool get finished => _finished;

  /// Vị trí phát hiện tại trong log (ms).
  int get positionMs => _logicalMs.round();

  @override
  void start() {
    stop();
    _windows = buildReplayWindows(log, baseEpochMs: _clock().millisecondsSinceEpoch);
    _nextWindow = 0;
    _nextGps = 0;
    _logicalMs = 0;
    _finished = false;
    _timer = Timer.periodic(tick, (_) => _advance());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _advance() {
    _logicalMs += tick.inMicroseconds / 1000 * speedFactor;

    while (_nextGps < log.gps.length && log.gps[_nextGps].tMs <= _logicalMs) {
      final speed = log.gps[_nextGps].speedMps;
      if (speed >= 0) _speedController.add(speed);
      _nextGps++;
    }
    while (_nextWindow < _windows.length && _windows[_nextWindow].endTMs <= _logicalMs) {
      _windowController.add(_windows[_nextWindow].window);
      _nextWindow++;
    }
    if (_nextGps >= log.gps.length && _nextWindow >= _windows.length) {
      _finished = true;
      stop();
    }
  }

  void dispose() {
    stop();
    _speedController.close();
    _windowController.close();
  }
}
