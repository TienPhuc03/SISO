import 'dart:async';
import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../../map/domain/play_area.dart';
import '../domain/biometric_model.dart';
import '../domain/telemetry_window.dart';

/// Dáng di chuyển mà nguồn giả lập tạo ra.
enum SimulatedGait {
  running('Chạy bộ'),
  walking('Đi bộ'),
  motorbike('Xe máy');

  const SimulatedGait(this.label);
  final String label;
}

/// Nguồn dữ liệu GIẢ LẬP: sinh mẫu gia tốc tổng hợp (m/s²) và tốc độ, theo thời gian thực.
///
/// Dùng khi dev trên Chrome (không có cảm biến) và làm nền cho Demo Simulator (Ngày 29).
/// Không phải dữ liệu thật; công thức giống `synthetic-imu.fixture.ts` ở backend.
class SimulatedTelemetrySource implements TelemetryWindowSource {
  SimulatedTelemetrySource({
    this.gait = SimulatedGait.running,
    this.sampleRateHz = 50,
    this.startAt = PlayArea.landmark81,
    Random? random,
  }) : _random = random ?? Random();

  static const double _gravity = 9.80665;

  /// Đổi được giữa chừng để thử luật "2 cửa sổ liên tiếp".
  SimulatedGait gait;
  final int sampleRateHz;
  final Random _random;

  /// Điểm xuất phát của vệt GPS giả; mỗi giây đi một đoạn theo tốc độ, hướng xoay dần thành vòng.
  final LatLng startAt;

  final _speedController = StreamController<double>.broadcast();
  final _windowController = StreamController<TelemetryWindow>.broadcast();
  final _positionController = StreamController<GpsFix>.broadcast();
  Timer? _speedTimer;
  Timer? _windowTimer;
  int _clockMs = 0;
  int _fixClockMs = 0;
  late LatLng _position = startAt;
  double _headingRad = 0;

  /// Điểm GPS giả chưa gửi kèm cửa sổ nào.
  final _pendingFixes = <GpsFix>[];

  @override
  Stream<double> get speedMps => _speedController.stream;

  @override
  Stream<TelemetryWindow> get windows => _windowController.stream;

  @override
  Stream<GpsFix> get positions => _positionController.stream;

  @override
  void start() {
    stop();
    _clockMs = DateTime.now().millisecondsSinceEpoch;
    _fixClockMs = _clockMs;
    _position = startAt;
    _headingRad = 0;
    _pendingFixes.clear();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _speedController.add(_speedFor(gait) + (_random.nextDouble() - 0.5) * 0.2);
      _positionController.add(nextFix());
    });
    final windowDuration = Duration(milliseconds: TelemetryWindow.size * 1000 ~/ sampleRateHz);
    _windowTimer = Timer.periodic(windowDuration, (_) => _windowController.add(buildWindow()));
  }

  @override
  void stop() {
    _speedTimer?.cancel();
    _windowTimer?.cancel();
    _speedTimer = null;
    _windowTimer = null;
  }

  /// Đi tiếp 1 giây theo tốc độ của [gait]; hướng xoay 2°/giây nên vệt là một vòng bán kính ~90 m.
  GpsFix nextFix() {
    const metersPerDegLat = 111320.0;
    final meters = _speedFor(gait);
    _position = LatLng(
      _position.latitude + meters * cos(_headingRad) / metersPerDegLat,
      _position.longitude + meters * sin(_headingRad) / (metersPerDegLat * cos(_position.latitude * pi / 180)),
    );
    _headingRad += 2 * pi / 180;
    _fixClockMs += 1000;
    final fix = GpsFix(lat: _position.latitude, lng: _position.longitude, timestampMs: _fixClockMs, accuracy: 6);
    _pendingFixes.add(fix);
    return fix;
  }

  /// Một cửa sổ 256 mẫu theo [gait] hiện tại.
  TelemetryWindow buildWindow() {
    final (stepHz, stepAmpG, vibHz, vibAmpG, noiseG) = switch (gait) {
      SimulatedGait.running => (2.7, 0.8, 0.0, 0.0, 0.1),
      SimulatedGait.walking => (1.9, 0.4, 0.0, 0.0, 0.05),
      SimulatedGait.motorbike => (0.0, 0.0, 10.0, 0.05, 0.03),
    };
    double noise() => _random.nextDouble() - 0.5;

    final samples = List.generate(TelemetryWindow.size, (i) {
      final t = i / sampleRateHz;
      final verticalG = 1 +
          stepAmpG * sin(2 * pi * stepHz * t) +
          vibAmpG * sin(2 * pi * vibHz * t) +
          noiseG * noise();
      return ImuSample(
        ax: _gravity * noiseG * noise(),
        ay: _gravity * noiseG * noise(),
        az: _gravity * verticalG,
        timestampMs: _clockMs + (i * 1000 ~/ sampleRateHz),
      );
    });
    final windowStart = _clockMs;
    _clockMs += TelemetryWindow.size * 1000 ~/ sampleRateHz;
    final gpsPoints = _pendingFixes.where((f) => f.timestampMs >= windowStart && f.timestampMs <= _clockMs).toList();
    _pendingFixes.removeWhere((f) => f.timestampMs <= _clockMs);

    return TelemetryWindow(
      samples: samples,
      averageSpeedMps: _speedFor(gait),
      horizontalAccuracy: 6,
      isMocked: false,
      gpsPoints: capGpsPoints(gpsPoints),
    );
  }

  static double _speedFor(SimulatedGait gait) => switch (gait) {
        SimulatedGait.running => 3.2,
        SimulatedGait.walking => 1.6,
        SimulatedGait.motorbike => 3.4,
      };

  void dispose() {
    stop();
    _speedController.close();
    _windowController.close();
    _positionController.close();
  }
}
