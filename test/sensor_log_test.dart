import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/map/data/user_location_source.dart';
import 'package:siso_project/src/features/map/presentation/map_screen.dart';
import 'package:siso_project/src/features/map/providers/map_state_notifier.dart';
import 'package:siso_project/src/features/tracking/data/raw_sensor_streams.dart';
import 'package:siso_project/src/features/tracking/data/telemetry_log_recorder.dart';
import 'package:siso_project/src/features/tracking/data/telemetry_log_store.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_log.dart';
import 'package:siso_project/src/features/tracking/presentation/sensor_log_screen.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, student;
import 'map_location_perf_test.dart' show FakeLocationSource;
import 'map_state_notifier_test.dart' show FakeHexagonRepository;

/// Cảm biến giả: test tự đẩy sự kiện.
class FakeSensors implements RawSensorStreams {
  final accel = StreamController<AccelReading>.broadcast();
  final gpsCtrl = StreamController<GpsReading>.broadcast();
  String? permissionError;

  @override
  Stream<AccelReading> accelerometer() => accel.stream;

  @override
  Stream<GpsReading> gps() => gpsCtrl.stream;

  @override
  Future<String?> ensureLocationPermission() async => permissionError;
}

class MemorySink implements LogSink {
  final lines = <String>[];
  bool closed = false;

  @override
  void writeLine(String line) => lines.add(line);

  @override
  Future<void> close() async => closed = true;
}

class FakeScreenAwake implements ScreenAwake {
  bool on = false;

  @override
  Future<void> enable() async => on = true;

  @override
  Future<void> disable() async => on = false;
}

class _BlankTileProvider extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

final t0 = DateTime(2026, 11, 12, 7);

AccelReading accelAt(DateTime ts, {double z = 9.8}) => AccelReading(x: 0.1, y: 0.2, z: z, timestamp: ts);

GpsReading gpsAt(DateTime ts, {double acc = 5, double spd = 3}) => GpsReading(
      lat: 10.8,
      lng: 106.71,
      accuracyM: acc,
      speedMps: spd,
      isMocked: false,
      timestamp: ts,
    );

void main() {
  group('TelemetryLogRecorder', () {
    late FakeSensors sensors;
    late MemorySink sink;
    late DateTime now;
    late TelemetryLogRecorder recorder;

    setUp(() {
      sensors = FakeSensors();
      sink = MemorySink();
      now = t0;
      recorder = TelemetryLogRecorder(sensors: sensors, clock: () => now);
    });

    tearDown(() => recorder.dispose());

    TelemetryLogHeader header() => TelemetryLogHeader(startedAt: t0, label: TelemetryLogLabel.walking);

    test('ghi header trước, rồi gia tốc và GPS; đọc lại được bằng TelemetryLog.parse', () async {
      recorder.start(header: header(), sink: sink);
      now = t0.add(const Duration(milliseconds: 300)); // sự kiện đầu tới sau 300 ms
      // Đồng hồ cảm biến có gốc khác hẳn đồng hồ máy: chỉ khoảng cách giữa các mẫu có ý nghĩa.
      final sensorBase = DateTime(2000);
      for (var i = 0; i < 3; i++) {
        sensors.accel.add(accelAt(sensorBase.add(Duration(milliseconds: 20 * i)), z: 9.8 + i));
      }
      await pumpEventQueue();
      now = t0.add(const Duration(milliseconds: 1000));
      sensors.gpsCtrl.add(gpsAt(DateTime(1999)));
      await pumpEventQueue();
      final stats = await recorder.stop();

      final log = TelemetryLog.parse(sink.lines.join());
      expect(sink.lines.first, contains('"k":"h"'));
      expect(log.header.label, TelemetryLogLabel.walking);
      expect(log.accel.map((a) => a.tMs), [300, 320, 340]);
      expect(log.accel.map((a) => a.z), [9.8, 10.8, 11.8]);
      expect(log.gps.single.tMs, 1000);
      expect(stats.accelCount, 3);
      expect(stats.gpsCount, 1);
      expect(sink.closed, isTrue);
      expect(recorder.isRecording, isFalse);
    });

    test('sau khi dừng không ghi thêm', () async {
      recorder.start(header: header(), sink: sink);
      await recorder.stop();
      sensors.accel.add(accelAt(t0));
      await pumpEventQueue();
      expect(sink.lines, hasLength(1));
    });

    test('đang ghi mà bấm bắt đầu lần nữa: lỗi', () {
      recorder.start(header: header(), sink: sink);
      expect(() => recorder.start(header: header(), sink: MemorySink()), throwsStateError);
    });

    test('lỗi luồng cảm biến được giữ lại để hiện lên màn hình', () async {
      recorder.start(header: header(), sink: sink);
      sensors.gpsCtrl.addError(Exception('GPS tắt'));
      await pumpEventQueue();
      expect(recorder.error.toString(), contains('GPS tắt'));
    });

    testWidgets('số liệu: tần số IMU, sai số và tốc độ GPS gần nhất', (tester) async {
      recorder.start(header: header(), sink: sink);
      for (var i = 0; i < 101; i++) {
        sensors.accel.add(accelAt(t0.add(Duration(milliseconds: 20 * i))));
      }
      sensors.gpsCtrl.add(gpsAt(t0, acc: 8.5, spd: 2.5));
      await tester.pump();
      now = t0.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));

      expect(recorder.stats.accelCount, 101);
      expect(recorder.stats.accelRateHz, closeTo(50, 0.01));
      expect(recorder.stats.lastAccuracyM, 8.5);
      expect(recorder.stats.lastSpeedMps, 2.5);
      expect(recorder.stats.elapsed, const Duration(seconds: 2));
      unawaited(recorder.stop()); // huỷ Timer trong vùng thời gian giả của testWidgets
      await tester.pump();
    });
  });

  group('TelemetryLogStore (thư mục tạm)', () {
    late Directory tmp;
    late TelemetryLogStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('siso_logs_');
      store = TelemetryLogStore(baseDir: () async => tmp);
    });

    tearDown(() => tmp.delete(recursive: true));

    test('tạo file, ghi, liệt kê (mới nhất trước), xoá', () async {
      final a = await store.create('siso_run_a.jsonl');
      a.writeLine('{"k":"h"}\n');
      await a.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final b = await store.create('siso_walk_b.jsonl');
      b.writeLine('{"k":"h"}\n');
      await b.close();
      await File('${(await store.directory()).path}/ghichu.txt').writeAsString('x');

      final files = await store.list();
      expect(files.map((f) => f.name), ['siso_walk_b.jsonl', 'siso_run_a.jsonl']);
      expect(files.first.sizeBytes, 10);
      expect(await File(files.first.file.path).readAsString(), '{"k":"h"}\n');

      await store.delete(files.first);
      expect((await store.list()).map((f) => f.name), ['siso_run_a.jsonl']);
    });
  });

  group('SensorLogScreen', () {
    late FakeSensors sensors;
    late FakeScreenAwake awake;
    late Directory tmp;

    setUp(() async {
      sensors = FakeSensors();
      awake = FakeScreenAwake();
      tmp = await Directory.systemTemp.createTemp('siso_screen_');
    });

    tearDown(() => tmp.delete(recursive: true));

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rawSensorStreamsProvider.overrideWithValue(sensors),
            telemetryLogStoreProvider.overrideWithValue(TelemetryLogStore(baseDir: () async => tmp)),
            screenAwakeProvider.overrideWithValue(awake),
          ],
          child: const MaterialApp(home: SensorLogScreen()),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    testWidgets('ghi xong: lưu file .jsonl đúng nhãn, giữ màn hình sáng khi ghi, hiện trong danh sách',
        (tester) async {
      await pumpScreen(tester);
      expect(find.text('Chưa có file nào.'), findsOneWidget);

      await tester.tap(find.text('Xe máy'));
      await tester.enterText(find.byKey(const Key('log_note')), 'đường D2, kẹp ghi đông');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('log_start')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(awake.on, isTrue);
      expect(find.byKey(const Key('log_stats')), findsOneWidget);

      await tester.runAsync(() async {
        for (var i = 0; i < 5; i++) {
          sensors.accel.add(accelAt(t0.add(Duration(milliseconds: 20 * i))));
        }
        sensors.gpsCtrl.add(gpsAt(t0, acc: 25));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.textContaining('Sai số GPS > 20 m'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('log_stop')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(awake.on, isFalse);
      expect(find.textContaining('Đã lưu: 5 mẫu IMU, 1 lần GPS'), findsOneWidget);
      final file = tmp.listSync(recursive: true).whereType<File>().single;
      expect(file.path, contains('siso_motorbike_'));
      final log = TelemetryLog.parse(await tester.runAsync(file.readAsString) ?? '');
      expect(log.header.label, TelemetryLogLabel.motorbike);
      expect(log.header.note, 'đường D2, kẹp ghi đông');
      expect(log.accel, hasLength(5));
      expect(find.textContaining('siso_motorbike_'), findsOneWidget);
    });

    testWidgets('chưa cấp quyền vị trí: báo lỗi, không ghi', (tester) async {
      sensors.permissionError = 'SISO chưa được cấp quyền vị trí.';
      await pumpScreen(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('log_start')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text('SISO chưa được cấp quyền vị trí.'), findsOneWidget);
      expect(find.byKey(const Key('log_stats')), findsNothing);
      expect(awake.on, isFalse);
    });
  });

  testWidgets('bản đồ: nhấn giữ nút "Chạy" mở màn Ghi log; nhấn thường mở màn Chạy', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()..restoredUser = student),
          hexagonRepositoryProvider.overrideWithValue(FakeHexagonRepository([])),
          userLocationSourceProvider.overrideWithValue(FakeLocationSource(null)),
          telemetryLogStoreProvider.overrideWithValue(
            TelemetryLogStore(baseDir: () async => Directory.systemTemp),
          ),
        ],
        child: MaterialApp(home: MapScreen(tileProvider: _BlankTileProvider())),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('Chạy'));
    await tester.pumpAndSettle();
    expect(find.text('Ghi log cảm biến'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chạy'));
    await tester.pumpAndSettle();
    expect(find.text('Phiên Chạy Đang Diễn Ra'), findsOneWidget);
  });
}
