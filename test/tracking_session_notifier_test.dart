import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/features/tracking/data/pause_reminder.dart';
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

  for (final code in ['ERR_206', 'ERR_207']) {
    test('server trả $code (chỉ bỏ cửa sổ): Phiên chạy tiếp tục, không dừng nguồn', () async {
      repo.responses.addAll([_ok(key: 'k1'), SisoException(code: code, message: 'x'), _ok()]);
      notifier.startRun();

      await sendWindow();
      await sendWindow();
      expect(notifier.state.status, TrackingStatus.tracking);
      expect(notifier.state.errorCode, isNull);
      expect(source.stops, 0);

      await sendWindow();
      expect(repo.calls, ['verify', 'verify', 'verify']);
    });
  }

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

  group('Tạm dừng / Tiếp tục', () {
    test('Tạm dừng: giữ cảm biến chạy nhưng không gửi Cửa sổ, Phiên vẫn đang chạy, tốc độ về 0', () async {
      repo.responses.add(_ok(key: 'k1'));
      notifier.startRun();
      source.speed.add(3.0);
      await sendWindow();

      notifier.pauseRun();
      await sendWindow(); // Cửa sổ sinh ra lúc Tạm dừng

      expect(source.stops, 0, reason: 'giữ GPS để tự Tiếp tục và để app không bị hệ điều hành treo ở nền');
      expect(repo.calls, ['verify']);
      expect(notifier.state.paused, isTrue);
      expect(notifier.state.autoPaused, isFalse);
      expect(notifier.state.status, TrackingStatus.tracking);
      expect(notifier.state.sessionId, 'sess-1');
      expect(notifier.state.speedKmh, 0);
    });

    test('đang Tạm dừng: tốc độ và điểm GPS không được tính', () async {
      notifier.startRun();
      notifier.pauseRun();
      source.speed.add(3.0);
      source.pos.add(const GpsFix(lat: 10.8, lng: 106.7, timestampMs: 0, accuracy: 5));
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.speedKmh, 0);
      expect(notifier.state.route, isEmpty);
    });

    test('Tiếp tục: khởi động lại nguồn (xoá đệm), Cửa sổ sau vẫn thuộc Phiên cũ, seq nối tiếp', () async {
      repo.responses.addAll([_ok(key: 'k1'), _ok(), _ok()]);
      notifier.startRun();
      await sendWindow();
      await sendWindow();

      notifier.pauseRun();
      notifier.resumeRun();
      await sendWindow();

      expect(source.stops, 1);
      expect(source.starts, 2);
      expect(notifier.state.paused, isFalse);
      expect(repo.sentSessionIds, [null, 'sess-1', 'sess-1']);
      expect(repo.sentKeys, [null, 'k1', 'k1']);
      expect(repo.sentSeqs, [null, 1, 2]);
    });

    test('Kết thúc khi đang Tạm dừng: vẫn gọi finish và cộng km', () async {
      repo.responses.add(_ok(key: 'k1'));
      notifier.startRun();
      await sendWindow();
      notifier.pauseRun();

      await notifier.stopRun();

      expect(repo.calls, ['verify', 'finish:sess-1']);
      expect(notifier.state.status, TrackingStatus.idle);
      expect(notifier.state.paused, isFalse);
      expect(notifier.state.addedKm, 1.5);
    });

    test('chưa chạy thì Tạm dừng / Tiếp tục không làm gì', () {
      notifier.pauseRun();
      notifier.resumeRun();

      expect(source.starts, 0);
      expect(source.stops, 0);
      expect(notifier.state.paused, isFalse);
      expect(notifier.state.status, TrackingStatus.idle);
    });

    test('bấm Tạm dừng hai lần hoặc Tiếp tục khi không Tạm dừng: không khởi động lại nguồn', () {
      notifier.startRun();
      notifier.resumeRun();
      notifier.pauseRun();
      notifier.pauseRun();

      expect(source.starts, 1);
      expect(source.stops, 0);
    });

    test('Phiên chạy mới không còn trạng thái Tạm dừng của Phiên trước', () async {
      notifier.startRun();
      notifier.pauseRun();
      await notifier.stopRun();

      notifier.startRun();

      expect(notifier.state.paused, isFalse);
    });
  });

  group('Tự Tạm dừng khi đứng yên', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 11, 23, 18);
      notifier = TrackingSessionNotifier(source: source, repository: repo, clock: () => now);
    });

    Future<void> speedAt(int second, double mps) async {
      now = DateTime(2026, 11, 23, 18).add(Duration(seconds: second));
      source.speed.add(mps);
      await Future<void>.delayed(Duration.zero);
    }

    test('đứng yên liên tục ${autoPauseAfter.inSeconds} s: tự Tạm dừng', () async {
      notifier.startRun();
      for (var s = 0; s < autoPauseAfter.inSeconds; s++) {
        await speedAt(s, 0.2);
      }
      expect(notifier.state.paused, isFalse);

      await speedAt(autoPauseAfter.inSeconds, 0.3);

      expect(notifier.state.paused, isTrue);
      expect(notifier.state.autoPaused, isTrue);
    });

    test('đứng yên một lúc rồi chạy tiếp trước ${autoPauseAfter.inSeconds} s: không Tạm dừng', () async {
      notifier.startRun();
      await speedAt(0, 0.1);
      await speedAt(5, 0.1);
      await speedAt(6, 2.5); // chạy lại, đếm lại từ đầu
      await speedAt(7, 0.1);
      await speedAt(15, 0.1);

      expect(notifier.state.paused, isFalse);
    });

    test('tự Tạm dừng rồi chạy lại liên tục ${autoResumeAfter.inSeconds} s: tự Tiếp tục cùng Phiên', () async {
      notifier.startRun();
      await speedAt(0, 0);
      await speedAt(autoPauseAfter.inSeconds, 0);
      expect(notifier.state.autoPaused, isTrue);

      await speedAt(30, 2.8);
      await speedAt(31, 0.4); // GPS nhiễu một nhịp: chưa tính
      await speedAt(32, 2.8);
      await speedAt(33, 2.9);
      expect(notifier.state.paused, isTrue);
      await speedAt(32 + autoResumeAfter.inSeconds, 3.0);

      expect(notifier.state.paused, isFalse);
      expect(source.starts, 2);
    });

    test('Tạm dừng bằng tay thì không tự Tiếp tục khi di chuyển', () async {
      notifier.startRun();
      notifier.pauseRun();
      for (var s = 0; s <= 10; s++) {
        await speedAt(s, 3.0);
      }

      expect(notifier.state.paused, isTrue);
    });
  });

  group('Tạm dừng lâu: nhắc ở phút 25, tự kết thúc ở phút 30', () {
    late FakeReminder reminder;

    setUp(() {
      reminder = FakeReminder();
      notifier = TrackingSessionNotifier(
        source: source,
        repository: repo,
        reminder: reminder,
        pauseReminderAfter: const Duration(milliseconds: 20),
        pauseAutoFinishAfter: const Duration(milliseconds: 60),
      );
    });

    test('mặc định là 25 và 30 phút', () {
      expect(defaultPauseReminderAfter, const Duration(minutes: 25));
      expect(defaultPauseAutoFinishAfter, const Duration(minutes: 30));
    });

    test('Tạm dừng tới mốc nhắc: bắn một thông báo, màn hình báo sắp tự kết thúc', () async {
      notifier.startRun();
      notifier.pauseRun();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(reminder.shows, 1);
      expect(notifier.state.pauseExpiring, isTrue);
      expect(notifier.state.status, TrackingStatus.tracking);
    });

    test('chạy tiếp sau khi được nhắc: không tự kết thúc, gỡ thông báo, chạy bình thường', () async {
      repo.responses.addAll([_ok(key: 'k1'), _ok()]);
      notifier.startRun();
      await sendWindow();
      notifier.pauseRun();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      notifier.resumeRun();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sendWindow();

      expect(reminder.cancels, greaterThanOrEqualTo(1));
      expect(notifier.state.pauseExpiring, isFalse);
      expect(notifier.state.status, TrackingStatus.tracking);
      expect(repo.calls, ['verify', 'verify']);
    });

    test('không tương tác tới mốc kết thúc: tự kết thúc Phiên, cộng km, gỡ thông báo', () async {
      repo.responses.add(_ok(key: 'k1'));
      notifier.startRun();
      await sendWindow();
      notifier.pauseRun();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repo.calls, ['verify', 'finish:sess-1']);
      expect(notifier.state.status, TrackingStatus.idle);
      expect(notifier.state.addedKm, 1.5);
      expect(notifier.state.paused, isFalse);
      expect(reminder.cancels, greaterThanOrEqualTo(1));
    });

    test('tự kết thúc nhưng server đã tự đóng Phiên (ERR_204): báo đã tự kết thúc, không coi là lỗi lạ', () async {
      repo.responses.add(_ok(key: 'k1'));
      repo.finishResponse = const SisoException(code: 'ERR_204', message: 'SESSION_NOT_FOUND');
      notifier.startRun();
      await sendWindow();
      notifier.pauseRun();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.state.status, TrackingStatus.idle);
      expect(notifier.state.errorCode, pauseTimeoutCode);
    });

    test('tự Tạm dừng cũng được nhắc và tự kết thúc', () async {
      var now = DateTime(2026);
      notifier = TrackingSessionNotifier(
        source: source,
        repository: repo,
        reminder: reminder,
        clock: () => now,
        pauseReminderAfter: const Duration(milliseconds: 20),
        pauseAutoFinishAfter: const Duration(milliseconds: 60),
      );
      notifier.startRun();
      source.speed.add(0);
      await Future<void>.delayed(Duration.zero);
      now = now.add(autoPauseAfter);
      source.speed.add(0);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(reminder.shows, 1);
      expect(notifier.state.status, TrackingStatus.idle);
    });

    test('Kết thúc bằng tay khi đang Tạm dừng: không còn hẹn giờ nhắc / tự kết thúc', () async {
      notifier.startRun();
      notifier.pauseRun();
      await notifier.stopRun();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(reminder.shows, 0);
      expect(repo.calls, isEmpty);
    });
  });
}

class FakeReminder implements PauseReminder {
  int shows = 0;
  int cancels = 0;
  @override
  Future<void> show() async => shows++;
  @override
  Future<void> cancel() async => cancels++;
}
