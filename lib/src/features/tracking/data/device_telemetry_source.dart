import 'dart:async';

import '../../../core/errors/siso_exceptions.dart';
import '../domain/telemetry_log.dart';
import '../domain/telemetry_window.dart';
import 'raw_sensor_streams.dart';
import 'replay_telemetry_source.dart';

/// Mã lỗi phía client khi không dùng được định vị (chưa cấp quyền hoặc Location Services tắt).
const locationUnavailableCode = 'ERR_LOCATION';

/// Nguồn CẢM BIẾN THẬT của máy: gia tốc kế 50 Hz + GPS (Module 4).
///
/// Gom đủ 256 mẫu gia tốc thì phát một [TelemetryWindow] rồi bắt đầu cửa sổ mới (không chồng nhau).
/// Số liệu GPS của cửa sổ tính giống hệt khi phát lại log ([buildWindow]).
/// Tốc độ HUD phát theo từng lần GPS (khoảng 1 lần/giây), bỏ giá trị âm của iOS.
/// Lỗi quyền vị trí hoặc lỗi cảm biến được đẩy vào [windows] dưới dạng lỗi của stream.
class DeviceTelemetrySource implements TelemetryWindowSource {
  DeviceTelemetrySource({this.streams = const DeviceSensorStreams()});

  final RawSensorStreams streams;

  final _speedController = StreamController<double>.broadcast();
  final _windowController = StreamController<TelemetryWindow>.broadcast();
  final _positionController = StreamController<GpsFix>.broadcast();
  final _accel = <AccelRecord>[];
  final _gps = <GpsRecord>[];
  StreamSubscription<AccelReading>? _accelSub;
  StreamSubscription<GpsReading>? _gpsSub;

  /// Tăng ở mỗi lần stop: bỏ kết quả xin quyền về muộn của lần chạy trước.
  int _run = 0;

  @override
  Stream<double> get speedMps => _speedController.stream;

  @override
  Stream<TelemetryWindow> get windows => _windowController.stream;

  @override
  Stream<GpsFix> get positions => _positionController.stream;

  @override
  void start() {
    stop();
    _listen(_run);
  }

  Future<void> _listen(int run) async {
    String? error;
    try {
      error = await streams.ensureLocationPermission();
    } catch (e) {
      error = 'Không kiểm tra được quyền vị trí: $e';
    }
    if (run != _run) return;
    if (error != null) {
      _windowController.addError(SisoException(code: locationUnavailableCode, message: error));
      return;
    }
    _gpsSub = streams.gps().listen(_onGps, onError: _windowController.addError);
    _accelSub = streams.accelerometer().listen(_onAccel, onError: _windowController.addError);
  }

  @override
  void stop() {
    _run++;
    _accelSub?.cancel();
    _gpsSub?.cancel();
    _accelSub = null;
    _gpsSub = null;
    _accel.clear();
    _gps.clear();
  }

  void _onGps(GpsReading g) {
    _gps.add(GpsRecord(
      tMs: g.timestamp.millisecondsSinceEpoch,
      lat: g.lat,
      lng: g.lng,
      accuracyM: g.accuracyM,
      speedMps: g.speedMps,
      isMocked: g.isMocked,
    ));
    if (g.speedMps >= 0) _speedController.add(g.speedMps);
    _positionController.add(GpsFix(
      lat: g.lat,
      lng: g.lng,
      timestampMs: g.timestamp.millisecondsSinceEpoch,
      accuracy: g.accuracyM,
    ));
  }

  void _onAccel(AccelReading a) {
    _accel.add(AccelRecord(tMs: a.timestamp.millisecondsSinceEpoch, x: a.x, y: a.y, z: a.z));
    if (_accel.length < TelemetryWindow.size) return;

    // tMs đã là epoch ms nên baseEpochMs = 0.
    _windowController.add(buildWindow(_accel, _gps, baseEpochMs: 0));
    // Bỏ GPS đã dùng, giữ lần cuối để cửa sổ sau (nếu chưa có GPS mới) vẫn có số liệu gần nhất.
    final lastUsed = _gps.lastIndexWhere((g) => g.tMs <= _accel.last.tMs);
    if (lastUsed > 0) _gps.removeRange(0, lastUsed);
    _accel.clear();
  }

  void dispose() {
    stop();
    _speedController.close();
    _windowController.close();
    _positionController.close();
  }
}
