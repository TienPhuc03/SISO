import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/telemetry_log.dart';
import 'raw_sensor_streams.dart';

/// Nơi bộ ghi đẩy từng dòng log (file trên máy thật, bộ nhớ trong test).
abstract class LogSink {
  void writeLine(String line);
  Future<void> close();
}

/// Số liệu trực tiếp hiện trên màn Ghi log.
@immutable
class RecorderStats {
  const RecorderStats({
    this.elapsed = Duration.zero,
    this.accelCount = 0,
    this.gpsCount = 0,
    this.accelRateHz = 0,
    this.lastAccuracyM,
    this.lastSpeedMps,
  });

  final Duration elapsed;
  final int accelCount;
  final int gpsCount;

  /// Tần số gia tốc kế đo được trong ~2 giây gần nhất.
  final double accelRateHz;
  final double? lastAccuracyM;
  final double? lastSpeedMps;
}

/// Ghi luồng GPS + gia tốc kế thô ra JSON Lines (định dạng ở `telemetry_log.dart`).
///
/// Mốc thời gian: mỗi luồng lấy khoảng cách giữa các timestamp của cảm biến, neo vào giờ nhận
/// sự kiện đầu tiên của luồng đó. Nhờ vậy giữ được nhịp 50 Hz chính xác của cảm biến mà
/// không phụ thuộc đồng hồ cảm biến có cùng gốc với đồng hồ máy hay không.
class TelemetryLogRecorder extends ChangeNotifier {
  TelemetryLogRecorder({
    required RawSensorStreams sensors,
    DateTime Function()? clock,
  })  : _sensors = sensors,
        _clock = clock ?? DateTime.now;

  final RawSensorStreams _sensors;
  final DateTime Function() _clock;

  LogSink? _sink;
  StreamSubscription<AccelReading>? _accelSub;
  StreamSubscription<GpsReading>? _gpsSub;
  Timer? _ticker;
  DateTime? _startedAt;
  _StreamClock? _accelClock;
  _StreamClock? _gpsClock;
  final List<int> _recentAccelT = [];
  RecorderStats _stats = const RecorderStats();
  Object? _error;

  bool get isRecording => _sink != null;
  RecorderStats get stats => _stats;

  /// Lỗi của luồng cảm biến (nếu có) trong lần ghi gần nhất.
  Object? get error => _error;

  void start({required TelemetryLogHeader header, required LogSink sink}) {
    if (isRecording) throw StateError('Đang ghi log.');
    _sink = sink;
    _startedAt = _clock();
    _accelClock = null;
    _gpsClock = null;
    _recentAccelT.clear();
    _error = null;
    _stats = const RecorderStats();
    sink.writeLine(encodeLogLine(header.toJson()));

    _accelSub = _sensors.accelerometer().listen(_onAccel, onError: _onError);
    _gpsSub = _sensors.gps().listen(_onGps, onError: _onError);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _publish());
    notifyListeners();
  }

  /// Dừng ghi, đóng file. Trả số liệu cuối cùng.
  Future<RecorderStats> stop() async {
    final sink = _sink;
    if (sink == null) return _stats;
    // Ngừng ghi ngay (đồng bộ), rồi mới chờ huỷ luồng và đóng file.
    _ticker?.cancel();
    _ticker = null;
    _sink = null;
    final accelSub = _accelSub;
    final gpsSub = _gpsSub;
    _accelSub = null;
    _gpsSub = null;
    _publish(notify: false);
    await accelSub?.cancel();
    await gpsSub?.cancel();
    await sink.close();
    notifyListeners();
    return _stats;
  }

  void _onAccel(AccelReading r) {
    final sink = _sink;
    if (sink == null) return;
    final t = (_accelClock ??= _StreamClock(r.timestamp, _sinceStartMs())).tMs(r.timestamp);
    sink.writeLine(encodeLogLine(AccelRecord(tMs: t, x: r.x, y: r.y, z: r.z).toJson()));
    _stats = _copy(accelCount: _stats.accelCount + 1);
    _recentAccelT.add(t);
    while (_recentAccelT.isNotEmpty && t - _recentAccelT.first > 2000) {
      _recentAccelT.removeAt(0);
    }
  }

  void _onGps(GpsReading r) {
    final sink = _sink;
    if (sink == null) return;
    final t = (_gpsClock ??= _StreamClock(r.timestamp, _sinceStartMs())).tMs(r.timestamp);
    sink.writeLine(encodeLogLine(GpsRecord(
      tMs: t,
      lat: r.lat,
      lng: r.lng,
      accuracyM: r.accuracyM,
      speedMps: r.speedMps,
      isMocked: r.isMocked,
    ).toJson()));
    _stats = _copy(gpsCount: _stats.gpsCount + 1, lastAccuracyM: r.accuracyM, lastSpeedMps: r.speedMps);
    notifyListeners();
  }

  void _onError(Object error) {
    _error = error;
    notifyListeners();
  }

  int _sinceStartMs() => _clock().difference(_startedAt!).inMilliseconds;

  void _publish({bool notify = true}) {
    final rate = _recentAccelT.length < 2
        ? 0.0
        : (_recentAccelT.length - 1) * 1000 / (_recentAccelT.last - _recentAccelT.first);
    _stats = _copy(
      elapsed: _startedAt == null ? Duration.zero : _clock().difference(_startedAt!),
      accelRateHz: rate.isFinite ? rate : 0,
    );
    if (notify) notifyListeners();
  }

  RecorderStats _copy({
    Duration? elapsed,
    int? accelCount,
    int? gpsCount,
    double? accelRateHz,
    double? lastAccuracyM,
    double? lastSpeedMps,
  }) =>
      RecorderStats(
        elapsed: elapsed ?? _stats.elapsed,
        accelCount: accelCount ?? _stats.accelCount,
        gpsCount: gpsCount ?? _stats.gpsCount,
        accelRateHz: accelRateHz ?? _stats.accelRateHz,
        lastAccuracyM: lastAccuracyM ?? _stats.lastAccuracyM,
        lastSpeedMps: lastSpeedMps ?? _stats.lastSpeedMps,
      );

  @override
  void dispose() {
    _accelSub?.cancel();
    _gpsSub?.cancel();
    _ticker?.cancel();
    _sink?.close();
    super.dispose();
  }
}

/// Đổi timestamp cảm biến thành ms kể từ lúc bấm Bắt đầu.
class _StreamClock {
  _StreamClock(this._firstSensorTs, this._firstOffsetMs);

  final DateTime _firstSensorTs;
  final int _firstOffsetMs;

  int tMs(DateTime sensorTs) => _firstOffsetMs + sensorTs.difference(_firstSensorTs).inMilliseconds;
}
