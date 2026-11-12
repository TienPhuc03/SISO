import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/features/tracking/data/telemetry_repository.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_window.dart';
import 'package:siso_project/src/features/tracking/providers/tracking_session_notifier.dart';

/// Nguồn giả: test tự đẩy tốc độ và cửa sổ.
class FakeSource implements TelemetryWindowSource {
  final speed = StreamController<double>.broadcast();
  final win = StreamController<TelemetryWindow>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Stream<double> get speedMps => speed.stream;
  @override
  Stream<TelemetryWindow> get windows => win.stream;
  @override
  void start() => starts++;
  @override
  void stop() => stops++;
}

/// Repository giả: trả lần lượt các phản hồi đã xếp sẵn, ghi lại sessionId đã gửi.
class FakeRepository extends TelemetryRepository {
  final responses = <Object>[];
  final sentSessionIds = <String?>[];
  final sentKeys = <String?>[];
  final sentSeqs = <int?>[];

  @override
  Future<VerifyWindowResult> verifyWindow(
    TelemetryWindow window, {
    String? sessionId,
    String? signingKey,
    int? seq,
  }) async {
    sentSessionIds.add(sessionId);
    sentKeys.add(signingKey);
    sentSeqs.add(seq);
    final next = responses.removeAt(0);
    if (next is VerifyWindowResult) return next;
    throw next;
  }
}

const _window = TelemetryWindow(samples: [], averageSpeedMps: 3.2, horizontalAccuracy: 6, isMocked: false);

VerifyWindowResult _ok({bool passed = true, int failures = 0, int cadence = 162, String? key}) => VerifyWindowResult(
      sessionId: 'sess-1',
      signingKey: key,
      windowPassed: passed,
      consecutiveFailures: failures,
      biometricApplied: true,
      cadenceSpm: cadence,
      message: '',
    );

void main() {
  late FakeSource source;
  late FakeRepository repo;
  late TrackingSessionNotifier notifier;

  setUp(() {
    source = FakeSource();
    repo = FakeRepository();
    notifier = TrackingSessionNotifier(source: source, repository: repo);
  });

  Future<void> sendWindow() async {
    source.win.add(_window);
    await Future<void>.delayed(Duration.zero);
    await notifier.flush();
  }

  test('ký từ cửa sổ thứ hai, seq tăng dần, giữ khoá của cửa sổ đầu', () async {
    repo.responses.addAll([_ok(key: 'k1'), _ok(), _ok()]);
    notifier.startRun();

    await sendWindow();
    await sendWindow();
    await sendWindow();

    expect(repo.sentKeys, [null, 'k1', 'k1']);
    expect(repo.sentSeqs, [null, 1, 2]);
  });

  test('Phiên chạy mới bỏ khoá và đếm lại seq', () async {
    repo.responses.addAll([_ok(key: 'k1'), _ok(), _ok(key: 'k2'), _ok()]);
    notifier.startRun();
    await sendWindow();
    await sendWindow();
    notifier.stopRun();

    notifier.startRun();
    await sendWindow();
    await sendWindow();

    expect(repo.sentKeys, [null, 'k1', null, 'k2']);
    expect(repo.sentSeqs, [null, 1, null, 1]);
  });

  test('bắt đầu chạy: bật nguồn dữ liệu và chuyển sang tracking', () {
    notifier.startRun();

    expect(source.starts, 1);
    expect(notifier.state.status, TrackingStatus.tracking);
  });

  test('tốc độ từ nguồn hiện lên HUD theo km/h', () async {
    notifier.startRun();
    source.speed.add(3.0);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.speedKmh, closeTo(10.8, 0.01));
  });

  test('cửa sổ qua: cập nhật Nhịp bước và nhớ sessionId cho cửa sổ sau', () async {
    repo.responses.addAll([_ok(), _ok(cadence: 170)]);
    notifier.startRun();

    await sendWindow();
    expect(notifier.state.cadenceSpm, 162);
    expect(notifier.state.sessionId, 'sess-1');

    await sendWindow();
    expect(repo.sentSessionIds, [null, 'sess-1']);
    expect(notifier.state.cadenceSpm, 170);
  });

  test('một cửa sổ không qua: hiện cảnh báo vàng, vẫn đang chạy', () async {
    repo.responses.add(_ok(passed: false, failures: 1));
    notifier.startRun();

    await sendWindow();

    expect(notifier.state.windowWarning, isTrue);
    expect(notifier.state.status, TrackingStatus.tracking);
  });

  test('cửa sổ sau qua thì tắt cảnh báo vàng', () async {
    repo.responses.addAll([_ok(passed: false, failures: 1), _ok()]);
    notifier.startRun();

    await sendWindow();
    await sendWindow();

    expect(notifier.state.windowWarning, isFalse);
  });

  test('server trả ERR_202: Phiên chạy bị loại, dừng nguồn dữ liệu', () async {
    repo.responses.add(const SisoException(code: 'ERR_202', message: 'nghi đi xe máy'));
    notifier.startRun();

    await sendWindow();

    expect(notifier.state.status, TrackingStatus.rejected);
    expect(notifier.state.errorCode, 'ERR_202');
    expect(source.stops, greaterThanOrEqualTo(1));
  });

  test('sau khi bị loại, cửa sổ còn tới không được gửi nữa', () async {
    repo.responses.add(const SisoException(code: 'ERR_202', message: 'x'));
    notifier.startRun();
    await sendWindow();

    source.win.add(_window);
    await Future<void>.delayed(Duration.zero);
    await notifier.flush();

    expect(repo.sentSessionIds, hasLength(1));
  });

  test('lỗi không phải Anti-GIGO (chưa đăng nhập) chỉ dừng chạy, không coi là bị loại', () async {
    repo.responses.add(const SisoException(code: 'HTTP_401', message: 'Unauthorized'));
    notifier.startRun();

    await sendWindow();

    expect(notifier.state.status, TrackingStatus.idle);
    expect(notifier.state.errorCode, 'HTTP_401');
  });

  test('lỗi mạng: bỏ cửa sổ đó, báo mất kết nối, vẫn tiếp tục chạy', () async {
    repo.responses.addAll([
      DioException(requestOptions: RequestOptions(path: '/api/v1/telemetry/verify')),
      _ok(),
    ]);
    notifier.startRun();

    await sendWindow();
    expect(notifier.state.connectionIssue, isTrue);
    expect(notifier.state.status, TrackingStatus.tracking);

    await sendWindow();
    expect(notifier.state.connectionIssue, isFalse);
  });

  test('dừng chạy: tắt nguồn dữ liệu và về idle', () {
    notifier.startRun();
    notifier.stopRun();

    expect(notifier.state.status, TrackingStatus.idle);
    expect(source.stops, greaterThanOrEqualTo(1));
  });
}
