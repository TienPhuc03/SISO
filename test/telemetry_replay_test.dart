import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/tracking/data/replay_log_assets.dart';
import 'package:siso_project/src/features/tracking/data/replay_telemetry_source.dart';
import 'package:siso_project/src/features/tracking/data/simulated_telemetry_source.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_log.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_source_choice.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_window.dart';
import 'package:siso_project/src/features/tracking/data/telemetry_repository.dart';
import 'package:siso_project/src/features/tracking/presentation/active_run_screen.dart';
import 'package:siso_project/src/features/tracking/presentation/telemetry_source_picker.dart';
import 'package:siso_project/src/features/tracking/providers/tracking_session_notifier.dart';

final header = TelemetryLogHeader(
  startedAt: DateTime.utc(2026, 11, 12, 1, 2, 3),
  label: TelemetryLogLabel.running,
  note: 'sân HUTECH',
  device: 'iOS 18',
  platform: 'ios',
);

/// Log tổng hợp: [accelCount] mẫu ở 50 Hz (20 ms/mẫu) + các lần GPS cho trước.
TelemetryLog makeLog(int accelCount, List<GpsRecord> gps) => TelemetryLog(
      header: header,
      accel: [
        for (var i = 0; i < accelCount; i++) AccelRecord(tMs: i * 20, x: 0.1, y: -0.2, z: 9.8 + i % 3),
      ],
      gps: gps,
    );

GpsRecord gpsAt(int t, {double spd = 3, double acc = 5, bool mock = false}) =>
    GpsRecord(tMs: t, lat: 10.80, lng: 106.71, accuracyM: acc, speedMps: spd, isMocked: mock);

/// Nội dung file JSONL như app ghi ra.
String encodeLog(TelemetryLog log) => [
      encodeLogLine(log.header.toJson()),
      for (final a in log.accel) encodeLogLine(a.toJson()),
      for (final g in log.gps) encodeLogLine(g.toJson()),
    ].join();

void main() {
  group('TelemetryLog: định dạng JSON Lines', () {
    test('ghi rồi đọc lại giữ nguyên header, gia tốc, GPS', () {
      final log = makeLog(3, [gpsAt(0, spd: -1, acc: 12.345, mock: true)]);
      final parsed = TelemetryLog.parse(encodeLog(log));

      expect(parsed.header.label, TelemetryLogLabel.running);
      expect(parsed.header.note, 'sân HUTECH');
      expect(parsed.header.startedAt, header.startedAt);
      expect(parsed.accel.map((a) => [a.tMs, a.x, a.y, a.z]), [
        [0, 0.1, -0.2, 9.8],
        [20, 0.1, -0.2, 10.8],
        [40, 0.1, -0.2, 11.8],
      ]);
      expect(parsed.gps.single.speedMps, -1);
      expect(parsed.gps.single.accuracyM, 12.35);
      expect(parsed.gps.single.isMocked, isTrue);
    });

    test('mỗi bản ghi đúng 1 dòng, khoá ngắn gọn', () {
      expect(encodeLogLine(const AccelRecord(tMs: 5, x: 1.234567, y: 0, z: 9.81).toJson()),
          '{"k":"a","t":5,"x":1.2346,"y":0.0,"z":9.81}\n');
    });

    test('bản ghi xen kẽ, không theo thứ tự: sắp lại theo t', () {
      final content = [
        encodeLogLine(header.toJson()),
        encodeLogLine(gpsAt(1000).toJson()),
        encodeLogLine(const AccelRecord(tMs: 40, x: 0, y: 0, z: 9.8).toJson()),
        encodeLogLine(const AccelRecord(tMs: 20, x: 0, y: 0, z: 9.8).toJson()),
        encodeLogLine(gpsAt(0).toJson()),
      ].join();
      final log = TelemetryLog.parse(content);
      expect(log.accel.map((a) => a.tMs), [20, 40]);
      expect(log.gps.map((g) => g.tMs), [0, 1000]);
    });

    test('bỏ qua dòng trống và loại bản ghi lạ', () {
      final content = '${encodeLogLine(header.toJson())}\n{"k":"magnet","t":1}\n';
      expect(TelemetryLog.parse(content).accel, isEmpty);
    });

    test('thiếu header: FormatException', () {
      expect(() => TelemetryLog.parse(encodeLogLine(gpsAt(0).toJson())), throwsFormatException);
    });

    test('dòng hỏng: FormatException nêu số dòng', () {
      final content = '${encodeLogLine(header.toJson())}{"k":"a","t":1}\n';
      expect(
        () => TelemetryLog.parse(content),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Dòng 2'))),
      );
    });

    test('độ dài log và tần số IMU thực tế', () {
      final log = makeLog(501, [gpsAt(12000)]);
      expect(log.durationMs, 12000);
      expect(log.accelRateHz, closeTo(50, 0.001));
      expect(makeLog(1, const []).accelRateHz, 0);
    });

    test('tên file theo nhãn và giờ', () {
      expect(telemetryLogFileName(TelemetryLogLabel.motorbike, DateTime(2026, 11, 2, 7, 5, 9)),
          'siso_motorbike_20261102-070509.jsonl');
    });

    test('nhãn lạ đọc thành Khác', () {
      expect(TelemetryLogLabel.fromCode('bike'), TelemetryLogLabel.other);
    });
  });

  group('buildReplayWindows', () {
    test('cắt thành cửa sổ 256 mẫu liên tiếp, bỏ phần lẻ cuối', () {
      final windows = buildReplayWindows(makeLog(600, [gpsAt(0)]), baseEpochMs: 0);
      expect(windows, hasLength(2));
      expect(windows.every((w) => w.window.samples.length == TelemetryWindow.size), isTrue);
      expect(windows[0].startTMs, 0);
      expect(windows[0].endTMs, 255 * 20);
      expect(windows[1].startTMs, 256 * 20);
    });

    test('mẫu giữ nguyên trục và cộng mốc thời gian', () {
      final w = buildReplayWindows(makeLog(256, [gpsAt(0)]), baseEpochMs: 1000000).single.window;
      expect(w.samples[1].az, 10.8);
      expect(w.samples[1].ax, 0.1);
      expect(w.samples[1].timestampMs, 1000020);
    });

    test('tốc độ = trung bình GPS hợp lệ trong cửa sổ (bỏ -1); sai số = tệ nhất; mock nếu có', () {
      final w = buildReplayWindows(
        makeLog(256, [
          gpsAt(1000, spd: 2, acc: 4),
          gpsAt(2000, spd: -1, acc: 30),
          gpsAt(3000, spd: 4, acc: 6, mock: true),
          gpsAt(9000, spd: 99, acc: 1), // ngoài cửa sổ (cửa sổ kết thúc ở 5100 ms)
        ]),
        baseEpochMs: 0,
      ).single.window;
      expect(w.averageSpeedMps, 3);
      expect(w.horizontalAccuracy, 30);
      expect(w.isMocked, isTrue);
    });

    test('cửa sổ không có GPS: dùng lần GPS gần nhất trước đó', () {
      final windows = buildReplayWindows(makeLog(512, [gpsAt(0, spd: 2.5, acc: 7)]), baseEpochMs: 0);
      expect(windows[1].window.averageSpeedMps, 2.5);
      expect(windows[1].window.horizontalAccuracy, 7);
    });

    test('log không có GPS: tốc độ 0, sai số 999 (server sẽ báo ERR_203)', () {
      final w = buildReplayWindows(makeLog(256, const []), baseEpochMs: 0).single.window;
      expect(w.averageSpeedMps, 0);
      expect(w.horizontalAccuracy, noGpsAccuracyM);
      expect(w.isMocked, isFalse);
    });

    test('ít hơn 256 mẫu: không có cửa sổ nào', () {
      expect(buildReplayWindows(makeLog(255, [gpsAt(0)]), baseEpochMs: 0), isEmpty);
    });
  });

  group('ReplayTelemetrySource: phát theo thời gian của log', () {
    testWidgets('1x: tốc độ theo từng lần GPS, cửa sổ phát khi tới mẫu cuối, hết log thì dừng', (tester) async {
      final source = ReplayTelemetrySource(
        name: 'log.jsonl',
        log: makeLog(512, [gpsAt(0, spd: 3), gpsAt(1000, spd: -1), gpsAt(2000, spd: 3.5)]),
      );
      addTearDown(source.dispose);
      final speeds = <double>[];
      final windows = <TelemetryWindow>[];
      source.speedMps.listen(speeds.add);
      source.windows.listen(windows.add);

      source.start();
      await tester.pump(const Duration(milliseconds: 100));
      expect(speeds, [3]);

      await tester.pump(const Duration(milliseconds: 2000));
      expect(speeds, [3, 3.5], reason: 'bỏ tốc độ -1 (iOS chưa có tốc độ)');
      expect(windows, isEmpty);

      await tester.pump(const Duration(milliseconds: 3000)); // t = 5,1 s: mẫu 255 ở 5100 ms
      expect(windows, hasLength(1));
      expect(source.finished, isFalse);

      await tester.pump(const Duration(milliseconds: 5200));
      expect(windows, hasLength(2));
      expect(source.finished, isTrue);
    });

    testWidgets('4x: cửa sổ đầu tới sau ~1,3 s', (tester) async {
      final source = ReplayTelemetrySource(name: 'x', log: makeLog(256, [gpsAt(0)]), speedFactor: 4);
      addTearDown(source.dispose);
      final windows = <TelemetryWindow>[];
      source.windows.listen(windows.add);

      source.start();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(windows, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(windows, hasLength(1));
    });

    testWidgets('stop giữa chừng thì không phát nữa; start lại phát từ đầu', (tester) async {
      final source = ReplayTelemetrySource(name: 'x', log: makeLog(256, [gpsAt(0, spd: 3)]));
      addTearDown(source.dispose);
      final speeds = <double>[];
      source.speedMps.listen(speeds.add);

      source.start();
      await tester.pump(const Duration(milliseconds: 100));
      source.stop();
      await tester.pump(const Duration(seconds: 10));
      expect(speeds, [3]);
      expect(source.finished, isFalse);

      source.start();
      await tester.pump(const Duration(milliseconds: 100));
      expect(speeds, [3, 3]);
      source.stop();
    });
  });

  group('Chọn nguồn dữ liệu (TelemetrySourcePicker)', () {
    final logA = makeLog(600, [gpsAt(0), gpsAt(1000)]);

    Future<ProviderContainer> pumpPicker(WidgetTester tester, List<String> assets) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            replayLogAssetsProvider.overrideWith((ref) async => assets),
            replayLogLoaderProvider.overrideWithValue(
              (String path, [AssetBundle? bundle]) async => logA,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TelemetrySourcePicker()))),
        ),
      );
      await tester.pump();
      return ProviderScope.containerOf(tester.element(find.byType(TelemetrySourcePicker)));
    }

    testWidgets('mặc định là nguồn giả lập', (tester) async {
      final container = await pumpPicker(tester, const []);
      expect(container.read(telemetrySourceChoiceProvider), isA<SimulatedSourceChoice>());
      expect(container.read(telemetryWindowSourceProvider), isA<SimulatedTelemetrySource>());
    });

    testWidgets('chưa có log trong assets: hiện hướng dẫn', (tester) async {
      await pumpPicker(tester, const []);
      await tester.tap(find.text('Phát lại log'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replay_empty')), findsOneWidget);
    });

    testWidgets('chọn log: nguồn thành phát lại, hiện tóm tắt, đổi tốc độ, quay về giả lập', (tester) async {
      final container =
          await pumpPicker(tester, ['${telemetryLogAssetDir}siso_run_a.jsonl', '${telemetryLogAssetDir}siso_walk_b.jsonl']);
      await tester.tap(find.text('Phát lại log'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('siso_run_a.jsonl'));
      await tester.pumpAndSettle();

      final source = container.read(telemetryWindowSourceProvider);
      expect(source, isA<ReplayTelemetrySource>());
      expect((source as ReplayTelemetrySource).name, 'siso_run_a.jsonl');
      expect(source.speedFactor, 1);
      expect(find.byKey(const Key('replay_summary')), findsOneWidget);
      expect(find.textContaining('2 cửa sổ'), findsOneWidget);

      await tester.tap(find.byKey(const Key('replay_speed_4')));
      await tester.pumpAndSettle();
      expect((container.read(telemetryWindowSourceProvider) as ReplayTelemetrySource).speedFactor, 4);

      await tester.tap(find.text('Giả lập'));
      await tester.pumpAndSettle();
      expect(container.read(telemetryWindowSourceProvider), isA<SimulatedTelemetrySource>());
    });

    testWidgets('log hỏng: báo lỗi, giữ nguồn cũ', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            replayLogAssetsProvider.overrideWith((ref) async => ['${telemetryLogAssetDir}hong.jsonl']),
            replayLogLoaderProvider.overrideWithValue(
              (String path, [AssetBundle? bundle]) async => throw const FormatException('Dòng 2 hỏng'),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TelemetrySourcePicker()))),
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(tester.element(find.byType(TelemetrySourcePicker)));
      await tester.tap(find.text('Phát lại log'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('hong.jsonl'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Không đọc được log'), findsOneWidget);
      expect(container.read(telemetrySourceChoiceProvider), isA<SimulatedSourceChoice>());
    });

    testWidgets('đang chạy (enabled = false): không đổi được nguồn', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [replayLogAssetsProvider.overrideWith((ref) async => const [])],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: TelemetrySourcePicker(enabled: false))),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Phát lại log'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replay_empty')), findsNothing);
    });
  });

  testWidgets('màn Chạy + phát lại log 10x: gửi đủ các cửa sổ 256 mẫu lên server, giữ sessionId',
      (tester) async {
    final repo = _RecordingRepository();
    final log = makeLog(600, [for (var t = 0; t <= 12000; t += 1000) gpsAt(t, spd: 3.2)]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replayLogAssetsProvider.overrideWith((ref) async => ['${telemetryLogAssetDir}siso_run_a.jsonl']),
          replayLogLoaderProvider.overrideWithValue((String path, [AssetBundle? bundle]) async => log),
          telemetryRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: ActiveRunScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Phát lại log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('siso_run_a.jsonl'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay_speed_10')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bắt đầu chạy'));
    await tester.pump();
    // Nguồn đang chạy: không đổi được nguồn dữ liệu
    await tester.tap(find.text('Giả lập'));
    await tester.pump();
    expect(find.byKey(const Key('replay_summary')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2)); // 10x: ~20 s log, đủ 2 cửa sổ (5,1 s và 10,2 s)
    await tester.pump();

    expect(repo.windows, hasLength(2));
    expect(repo.windows.every((w) => w.samples.length == TelemetryWindow.size), isTrue);
    expect(repo.windows.first.averageSpeedMps, closeTo(3.2, 1e-9));
    expect(repo.sessionIds, [null, 'sess-1']);

    await tester.tap(find.text('Dừng chạy'));
    await tester.pump();
  });

  test('assetFileName lấy tên file', () {
    expect(assetFileName('assets/telemetry_logs/siso_run_x.jsonl'), 'siso_run_x.jsonl');
  });
}

/// Repository giả: ghi lại cửa sổ đã gửi, luôn trả "đạt" với cùng sessionId.
class _RecordingRepository extends TelemetryRepository {
  final windows = <TelemetryWindow>[];
  final sessionIds = <String?>[];

  @override
  Future<VerifyWindowResult> verifyWindow(TelemetryWindow window, {String? sessionId}) async {
    windows.add(window);
    sessionIds.add(sessionId);
    return const VerifyWindowResult(
      sessionId: 'sess-1',
      windowPassed: true,
      consecutiveFailures: 0,
      biometricApplied: true,
      cadenceSpm: 162,
      message: 'ok',
    );
  }
}
