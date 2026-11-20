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
  final pos = StreamController<GpsFix>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Stream<double> get speedMps => speed.stream;
  @override
  Stream<TelemetryWindow> get windows => win.stream;
  @override
  Stream<GpsFix> get positions => pos.stream;
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
    calls.add('verify');
    final next = responses.removeAt(0);
    if (next is VerifyWindowResult) return next;
    throw next;
  }

  /// Thứ tự gọi API ('verify' / 'finish:<sessionId>').
  final calls = <String>[];

  /// Kết quả của `finish`: số km, hoặc lỗi để ném.
  Object finishResponse = 1.5;

  @override
  Future<double> finishSession(String sessionId) async {
    calls.add('finish:$sessionId');
    final next = finishResponse;
    if (next is double) return next;
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
    await notifier.stopRun();

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

  test('Đường chạy: nối điểm GPS tốt, bỏ điểm sai số âm hoặc > 20 m, Phiên mới bắt đầu lại', () async {
    GpsFix fix(double lat, double accuracy) => GpsFix(lat: lat, lng: 106.7, timestampMs: 0, accuracy: accuracy);
    notifier.startRun();
    source.pos
      ..add(fix(10.80, 5))
      ..add(fix(10.81, -1))
      ..add(fix(10.82, 35))
      ..add(fix(10.83, 8));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.route.map((p) => p.latitude), [10.80, 10.83]);

    await notifier.stopRun();
    notifier.startRun();
    expect(notifier.state.route, isEmpty);
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

  test('ERR_204 (Phiên đã kết thúc trên server) chỉ dừng chạy, không phải bị loại', () async {
    repo.responses.add(const SisoException(code: 'ERR_204', message: 'SESSION_NOT_FOUND'));
    notifier.startRun();

    await sendWindow();

    expect(notifier.state.status, TrackingStatus.idle);
    expect(notifier.state.errorCode, 'ERR_204');
  });

  test('nguồn báo lỗi (chưa cấp quyền vị trí): dừng chạy, hiện lỗi, không bị loại', () async {
    notifier.startRun();

    source.win.addError(const SisoException(code: 'ERR_LOCATION', message: 'Chưa cấp quyền vị trí.'));
    await Future<void>.delayed(Duration.zero);
    await notifier.flush();

    expect(notifier.state.status, TrackingStatus.idle);
    expect(notifier.state.errorCode, 'ERR_LOCATION');
    expect(notifier.state.errorMessage, 'Chưa cấp quyền vị trí.');
    expect(source.stops, greaterThanOrEqualTo(1));
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

  test('server trả ERR_203 (mất tín hiệu vệ tinh): báo đang tìm tín hiệu, Phiên chạy tiếp tục', () async {
    repo.responses.addAll([
      const SisoException(code: 'ERR_203', message: 'GPS_ACCURACY_LOW'),
      _ok(),
    ]);
    notifier.startRun();

    await sendWindow();
    expect(notifier.state.status, TrackingStatus.tracking);
    expect(notifier.state.gpsSearching, isTrue);
    expect(source.stops, 0);

    await sendWindow();
    expect(notifier.state.gpsSearching, isFalse);
  });

  test('dừng chạy khi chưa có Phiên chạy: tắt nguồn dữ liệu, về idle, không gọi finish', () async {
    notifier.startRun();
    await notifier.stopRun();

    expect(notifier.state.status, TrackingStatus.idle);
    expect(source.stops, greaterThanOrEqualTo(1));
    expect(repo.calls, isEmpty);
  });

  test('dừng chạy: chờ cửa sổ đang gửi xong rồi mới finish, hiện km đã cộng', () async {
    repo.responses.add(_ok(key: 'k1'));
    notifier.startRun();
    source.win.add(_window);
    await Future<void>.delayed(Duration.zero);

    await notifier.stopRun();

    expect(repo.calls, ['verify', 'finish:sess-1']);
    expect(notifier.state.status, TrackingStatus.idle);
    expect(notifier.state.addedKm, 1.5);
  });

  test('dừng chạy sau khi bị loại: không gọi finish', () async {
    repo.responses.add(const SisoException(code: 'ERR_202', message: 'x'));
    notifier.startRun();
    await sendWindow();

    await notifier.stopRun();

    expect(repo.calls, ['verify']);
    expect(notifier.state.status, TrackingStatus.rejected);
  });

  test('finish lỗi mạng: về idle và báo km lần này chưa được cộng', () async {
    repo.responses.add(_ok(key: 'k1'));
    repo.finishResponse = DioException(requestOptions: RequestOptions(path: '/api/v1/telemetry/finish'));
    notifier.startRun();
    await sendWindow();

    await notifier.stopRun();

    expect(notifier.state.status, TrackingStatus.idle);
    expect(notifier.state.errorCode, 'ERR_NETWORK');
    expect(notifier.state.addedKm, isNull);
  });
}
