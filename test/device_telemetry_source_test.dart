import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/features/tracking/data/device_telemetry_source.dart';
import 'package:siso_project/src/features/tracking/data/raw_sensor_streams.dart';
import 'package:siso_project/src/features/tracking/data/replay_telemetry_source.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_window.dart';

/// Cảm biến giả: test tự đẩy mẫu gia tốc và GPS.
class FakeStreams implements RawSensorStreams {
  FakeStreams({this.permissionError});

  final String? permissionError;
  final accel = StreamController<AccelReading>.broadcast();
  final gpsCtrl = StreamController<GpsReading>.broadcast();

  @override
  Stream<AccelReading> accelerometer() => accel.stream;
  @override
  Stream<GpsReading> gps() => gpsCtrl.stream;
  @override
  Future<String?> ensureLocationPermission() async => permissionError;
}

final _t0 = DateTime.utc(2026, 11, 12, 7);

AccelReading _a(int ms, {double z = 9.8}) =>
    AccelReading(x: 0.1, y: 0.2, z: z, timestamp: _t0.add(Duration(milliseconds: ms)));

GpsReading _g(int ms, {double spd = 3, double acc = 5, bool mock = false}) => GpsReading(
      lat: 10.8,
      lng: 106.7,
      accuracyM: acc,
      speedMps: spd,
      isMocked: mock,
      timestamp: _t0.add(Duration(milliseconds: ms)),
    );

void main() {
  late FakeStreams streams;
  late DeviceTelemetrySource source;
  late List<TelemetryWindow> windows;
  late List<double> speeds;
  late List<Object> errors;

  Future<void> start([String? permissionError]) async {
    streams = FakeStreams(permissionError: permissionError);
    source = DeviceTelemetrySource(streams: streams);
    windows = [];
    speeds = [];
    errors = [];
    source.windows.listen(windows.add, onError: errors.add);
    source.speedMps.listen(speeds.add);
    source.start();
    await Future<void>.delayed(Duration.zero); // chờ xin quyền xong
  }

  Future<void> pushAccel(int count, {int fromMs = 0}) async {
    for (var i = 0; i < count; i++) {
      streams.accel.add(_a(fromMs + i * 20));
    }
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() => source.dispose());

  test('đủ 256 mẫu thì phát một cửa sổ, số liệu GPS lấy trong khoảng của cửa sổ', () async {
    await start();
    streams.gpsCtrl
      ..add(_g(1000, spd: 3, acc: 5))
      ..add(_g(2000, spd: 4, acc: 12));
    await pushAccel(255);
    expect(windows, isEmpty);

    await pushAccel(1, fromMs: 255 * 20);

    expect(windows, hasLength(1));
    final w = windows.single;
    expect(w.samples, hasLength(TelemetryWindow.size));
    expect(w.samples.first.timestampMs, _t0.millisecondsSinceEpoch);
    expect(w.averageSpeedMps, 3.5);
    expect(w.horizontalAccuracy, 12, reason: 'lấy sai số tệ nhất');
    expect(w.isMocked, isFalse);
  });

  test('cửa sổ không chồng nhau: 512 mẫu ra 2 cửa sổ, cửa sổ sau không có GPS mới dùng lần gần nhất', () async {
    await start();
    streams.gpsCtrl.add(_g(0, spd: 2.5, acc: 8));
    await pushAccel(512);

    expect(windows, hasLength(2));
    expect(windows[1].samples.first.timestampMs, _t0.millisecondsSinceEpoch + 256 * 20);
    expect(windows[1].averageSpeedMps, 2.5);
    expect(windows[1].horizontalAccuracy, 8);
  });

  test('iOS trả tốc độ -1: không lên HUD, không tính vào trung bình', () async {
    await start();
    streams.gpsCtrl
      ..add(_g(0, spd: -1))
      ..add(_g(1000, spd: 3));
    await pushAccel(256);

    expect(speeds, [3]);
    expect(windows.single.averageSpeedMps, 3);
  });

  test('chưa có GPS nào: sai số > 20 m để server báo ERR_203 (đang tìm tín hiệu)', () async {
    await start();
    await pushAccel(256);

    expect(windows.single.horizontalAccuracy, noGpsAccuracyM);
    expect(windows.single.averageSpeedMps, 0);
  });

  test('GPS bị đánh dấu giả trong cửa sổ: isMocked = true', () async {
    await start();
    streams.gpsCtrl.add(_g(500, mock: true));
    await pushAccel(256);

    expect(windows.single.isMocked, isTrue);
  });

  test('chưa cấp quyền vị trí: báo lỗi ERR_LOCATION, không nghe cảm biến', () async {
    await start('SISO chưa được cấp quyền vị trí.');

    expect(errors.single, isA<SisoException>().having((e) => e.code, 'code', locationUnavailableCode));
    expect(streams.accel.hasListener, isFalse);
  });

  test('stop: xoá đệm, ngừng nghe; start lại bắt đầu cửa sổ mới', () async {
    await start();
    await pushAccel(200);
    source.stop();
    expect(streams.accel.hasListener, isFalse);

    source.start();
    await Future<void>.delayed(Duration.zero);
    await pushAccel(200, fromMs: 10000);
    expect(windows, isEmpty, reason: '200 mẫu cũ đã bị xoá khi stop');
    await pushAccel(56, fromMs: 14000);
    expect(windows, hasLength(1));
  });
}
