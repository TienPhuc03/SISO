import 'dart:async';
import 'dart:math';

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
    Random? random,
  }) : _random = random ?? Random();

  static const double _gravity = 9.80665;

  /// Đổi được giữa chừng để thử luật "2 cửa sổ liên tiếp".
  SimulatedGait gait;
  final int sampleRateHz;
  final Random _random;

  final _speedController = StreamController<double>.broadcast();
  final _windowController = StreamController<TelemetryWindow>.broadcast();
  Timer? _speedTimer;
  Timer? _windowTimer;
  int _clockMs = 0;

  @override
  Stream<double> get speedMps => _speedController.stream;

  @override
  Stream<TelemetryWindow> get windows => _windowController.stream;

  @override
  void start() {
    stop();
    _clockMs = DateTime.now().millisecondsSinceEpoch;
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _speedController.add(_speedFor(gait) + (_random.nextDouble() - 0.5) * 0.2);
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
    _clockMs += TelemetryWindow.size * 1000 ~/ sampleRateHz;

    return TelemetryWindow(
      samples: samples,
      averageSpeedMps: _speedFor(gait),
      horizontalAccuracy: 6,
      isMocked: false,
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
  }
}
