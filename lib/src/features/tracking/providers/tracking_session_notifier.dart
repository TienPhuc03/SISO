import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../data/device_telemetry_source.dart';
import '../data/pause_reminder.dart';
import '../data/replay_telemetry_source.dart';
import '../data/simulated_telemetry_source.dart';
import '../data/telemetry_repository.dart';
import '../domain/telemetry_source_choice.dart';
import '../domain/telemetry_window.dart';

const _rejectionCodes = {
  SisoErrorCodes.mockGpsDetected,
  SisoErrorCodes.vehicleSpeedMismatch,
  SisoErrorCodes.invalidSignature,
};

// Ngưỡng tự Tạm dừng theo tốc độ GPS (~1 lần/giây). shortcut: ngưỡng ước lượng, chỉnh lại theo dữ liệu
// thực địa (GPS đứng yên hay rung 0,3–0,8 m/s; đi bộ ~1,3 m/s).
const autoPauseBelowMps = 0.6;
const autoPauseAfter = Duration(seconds: 10);
const autoResumeAboveMps = 1.2;
const autoResumeAfter = Duration(seconds: 3);

/// Tạm dừng tới mốc này thì nhắc Sinh viên; tới mốc sau thì tự kết thúc Phiên chạy.
/// Mốc kết thúc trùng ngưỡng 30 phút của Phiên bỏ dở (pg_cron `finish_stale_sessions`).
const defaultPauseReminderAfter = Duration(minutes: 25);
const defaultPauseAutoFinishAfter = Duration(minutes: 30);

/// Mã báo Phiên đã tự kết thúc vì Tạm dừng quá lâu (server đã đóng trước khi app kịp gọi `finish`).
const pauseTimeoutCode = 'ERR_PAUSE_TIMEOUT';

/// Trạng thái Phiên chạy phía client (Idle -> Tracking -> EvaluatingLoop | Rejected).
enum TrackingStatus { idle, tracking, evaluatingLoop, rejected }

class RunState {
  const RunState({
    this.status = TrackingStatus.idle,
    this.sessionId,
    this.speedKmh = 0,
    this.cadenceSpm,
    this.windowWarning = false,
    this.connectionIssue = false,
    this.gpsSearching = false,
    this.addedKm,
    this.errorCode,
    this.errorMessage,
    this.route = const [],
    this.paused = false,
    this.autoPaused = false,
    this.pauseExpiring = false,
  });

  final TrackingStatus status;
  final String? sessionId;

  /// Tạm dừng: Phiên chạy vẫn mở ([status] = tracking) nhưng không gửi Cửa sổ, không tính thời gian, quãng đường.
  final bool paused;

  /// Tạm dừng do đứng yên (tự Tiếp tục khi chạy lại); false = Sinh viên bấm Tạm dừng.
  final bool autoPaused;

  /// Đã Tạm dừng tới mốc nhắc (25 phút): sắp tự kết thúc Phiên chạy.
  final bool pauseExpiring;

  /// Tốc độ tức thời từ nguồn dữ liệu, cập nhật liên tục.
  final double speedKmh;

  /// Nhịp bước do server tính, cập nhật mỗi cửa sổ (~5 s); null khi chưa có kết quả.
  final int? cadenceSpm;

  /// Cửa sổ gần nhất không qua Cổng Sinh trắc (cảnh báo vàng, chưa bị loại).
  final bool windowWarning;

  /// Cửa sổ gần nhất không gửi được vì lỗi mạng; Phiên chạy vẫn tiếp tục.
  final bool connectionIssue;

  /// Cửa sổ gần nhất bị server trả ERR_203 (chưa có tín hiệu vệ tinh); Phiên chạy vẫn tiếp tục.
  final bool gpsSearching;

  /// Km server đã cộng khi kết thúc Phiên chạy tự do; null khi chưa kết thúc.
  final double? addedKm;

  final String? errorCode;
  final String? errorMessage;

  /// Đường chạy đã đi trong Phiên này (điểm GPS sai số ≤ 20 m), để bản đồ vẽ và bám theo.
  final List<LatLng> route;

  RunState copyWith({
    TrackingStatus? status,
    String? sessionId,
    double? speedKmh,
    int? cadenceSpm,
    bool? windowWarning,
    bool? connectionIssue,
    bool? gpsSearching,
    double? addedKm,
    String? errorCode,
    String? errorMessage,
    List<LatLng>? route,
    bool? paused,
    bool? autoPaused,
    bool? pauseExpiring,
  }) =>
      RunState(
        paused: paused ?? this.paused,
        autoPaused: autoPaused ?? this.autoPaused,
        pauseExpiring: pauseExpiring ?? this.pauseExpiring,
        status: status ?? this.status,
        sessionId: sessionId ?? this.sessionId,
        speedKmh: speedKmh ?? this.speedKmh,
        cadenceSpm: cadenceSpm ?? this.cadenceSpm,
        windowWarning: windowWarning ?? this.windowWarning,
        connectionIssue: connectionIssue ?? this.connectionIssue,
        gpsSearching: gpsSearching ?? this.gpsSearching,
        addedKm: addedKm ?? this.addedKm,
        errorCode: errorCode ?? this.errorCode,
        errorMessage: errorMessage ?? this.errorMessage,
        route: route ?? this.route,
      );
}

/// Điều phối một Phiên chạy: nhận cửa sổ từ [TelemetryWindowSource], gửi lần lượt lên server,
/// và cập nhật HUD / cảnh báo / màn hình bị loại theo phản hồi. Server là nơi quyết định.
class TrackingSessionNotifier extends StateNotifier<RunState> {
  TrackingSessionNotifier({
    required TelemetryWindowSource source,
    required TelemetryRepository repository,
    PauseReminder? reminder,
    DateTime Function()? clock,
    this.pauseReminderAfter = defaultPauseReminderAfter,
    this.pauseAutoFinishAfter = defaultPauseAutoFinishAfter,
  })  : _source = source,
        _repository = repository,
        _reminder = reminder,
        _clock = clock ?? DateTime.now,
        super(const RunState());

  final TelemetryWindowSource _source;
  final TelemetryRepository _repository;
  final PauseReminder? _reminder;
  final DateTime Function() _clock;
  final Duration pauseReminderAfter;
  final Duration pauseAutoFinishAfter;

  /// Hẹn giờ nhắc (25') và tự kết thúc (30') của lần Tạm dừng hiện tại.
  final _pauseTimers = <Timer>[];

  /// Mốc bắt đầu đứng yên / bắt đầu chạy lại liên tục, để tự Tạm dừng / tự Tiếp tục.
  DateTime? _stillSince;
  DateTime? _movingSince;

  /// Lần kết thúc này do Tạm dừng quá lâu (không phải Sinh viên bấm).
  bool _pauseTimedOut = false;
  StreamSubscription<double>? _speedSub;
  StreamSubscription<TelemetryWindow>? _windowSub;
  StreamSubscription<GpsFix>? _positionSub;

  /// Hàng đợi gửi tuần tự: mỗi cửa sổ cần sessionId do cửa sổ trước trả về.
  Future<void> _pending = Future.value();

  /// Khoá ký và số thứ tự của Phiên chạy hiện tại; không đưa vào state vì UI không cần.
  String? _signingKey;
  int _seq = 0;

  /// Đang chờ gửi cửa sổ cuối và `finish`; chặn bấm Dừng/Bắt đầu chồng lên nhau.
  bool _stopping = false;

  void startRun() {
    if (_stopping) return;
    _cancelSubscriptions();
    _resetPause();
    _signingKey = null;
    _seq = 0;
    _pauseTimedOut = false;
    state = const RunState(status: TrackingStatus.tracking);
    _speedSub = _source.speedMps.listen(_onSpeed);
    _positionSub = _source.positions.listen((fix) {
      if (mounted && state.status == TrackingStatus.tracking && !state.paused && fix.trusted) {
        state = state.copyWith(route: [...state.route, LatLng(fix.lat, fix.lng)]);
      }
    });
    _windowSub = _source.windows.listen(
      (window) {
        // Đang Tạm dừng: không gửi Cửa sổ nên server không cộng thời gian, quãng đường (mất tối đa ~5 s lúc bấm).
        if (state.paused) return;
        _pending = _pending.then((_) => _verify(window));
      },
      onError: _onSourceError,
    );
    _source.start();
  }

  void _onSpeed(double mps) {
    if (!mounted || state.status != TrackingStatus.tracking || _stopping) return;
    if (!state.paused) state = state.copyWith(speedKmh: mps * 3.6);
    final now = _clock();
    if (!state.paused) {
      if (mps >= autoPauseBelowMps) {
        _stillSince = null;
      } else if (now.difference(_stillSince ??= now) >= autoPauseAfter) {
        _pause(auto: true);
      }
    } else if (state.autoPaused) {
      if (mps < autoResumeAboveMps) {
        _movingSince = null;
      } else if (now.difference(_movingSince ??= now) >= autoResumeAfter) {
        resumeRun();
      }
    }
  }

  /// Tạm dừng bằng tay: chỉ Tiếp tục khi Sinh viên bấm (không tự Tiếp tục khi di chuyển).
  void pauseRun() => _pause(auto: false);

  /// Giữ cảm biến chạy khi Tạm dừng: để nhận ra lúc chạy lại (tự Tiếp tục), và để app còn chạy ở nền
  /// (iOS chỉ giữ app sống khi đang nhận vị trí) nên hẹn giờ nhắc / tự kết thúc vẫn chạy đúng giờ.
  void _pause({required bool auto}) {
    if (_stopping || state.status != TrackingStatus.tracking || state.paused) return;
    _stillSince = null;
    _movingSince = null;
    state = state.copyWith(paused: true, autoPaused: auto, speedKmh: 0);
    _pauseTimers
      ..add(Timer(pauseReminderAfter, _remindPause))
      ..add(Timer(pauseAutoFinishAfter, _finishAfterLongPause));
  }

  /// Tiếp tục cùng Phiên chạy: Cửa sổ sau dùng tiếp sessionId, khoá ký và seq.
  void resumeRun() {
    if (_stopping || state.status != TrackingStatus.tracking || !state.paused) return;
    _resetPause();
    state = state.copyWith(paused: false, autoPaused: false, pauseExpiring: false);
    // Khởi động lại nguồn để xoá đệm: Cửa sổ đầu sau khi chạy tiếp chỉ có dữ liệu mới.
    _source
      ..stop()
      ..start();
  }

  void _remindPause() {
    if (!mounted || !state.paused) return;
    state = state.copyWith(pauseExpiring: true);
    _reminder?.show().catchError((Object _) {});
  }

  void _finishAfterLongPause() {
    if (!mounted || !state.paused) return;
    _pauseTimedOut = true;
    stopRun();
  }

  /// Huỷ hẹn giờ của lần Tạm dừng và gỡ lời nhắc (nếu đã hiện).
  void _resetPause() {
    for (final t in _pauseTimers) {
      t.cancel();
    }
    _pauseTimers.clear();
    _stillSince = null;
    _movingSince = null;
    _reminder?.cancel().catchError((Object _) {});
  }

  /// Không đọc được cảm biến (chưa cấp quyền vị trí, GPS tắt giữa chừng): dừng chạy, vẫn cộng km đã kiểm định.
  void _onSourceError(Object error) {
    if (!mounted || state.status != TrackingStatus.tracking) return;
    state = error is SisoException
        ? state.copyWith(errorCode: error.code, errorMessage: error.message)
        : state.copyWith(errorCode: 'ERR_SENSOR', errorMessage: 'Không đọc được cảm biến: $error');
    stopRun();
  }

  /// Dừng nguồn dữ liệu, chờ các cửa sổ đã nhận được kiểm định xong rồi gọi `finish` để server cộng km.
  Future<void> stopRun() async {
    if (_stopping) return;
    _stopping = true;
    _cancelSubscriptions();
    _resetPause();
    _source.stop();
    try {
      // Cửa sổ cuối phải được cộng quãng đường trước khi Phiên chạy chuyển COMPLETED.
      await _pending;
      if (!mounted || state.status != TrackingStatus.tracking) return;
      final sessionId = state.sessionId;
      if (sessionId == null) {
        state = state.copyWith(status: TrackingStatus.idle);
        return;
      }
      try {
        final km = await _repository.finishSession(sessionId);
        if (mounted) state = state.copyWith(status: TrackingStatus.idle, addedKm: km);
      } on SisoException catch (e) {
        if (!mounted) return;
        // Tạm dừng 30': pg_cron có thể đã đóng Phiên (và cộng km) ngay trước khi app gọi finish.
        state = _pauseTimedOut && e.code == SisoErrorCodes.sessionNotFound
            ? state.copyWith(
                status: TrackingStatus.idle,
                errorCode: pauseTimeoutCode,
                errorMessage: 'Phiên chạy đã tự kết thúc vì tạm dừng quá 30 phút. Quãng đường đã kiểm định vẫn được cộng.',
              )
            : state.copyWith(status: TrackingStatus.idle, errorCode: e.code, errorMessage: e.message);
      } catch (_) {
        // Không cần gửi lại: Phiên còn ACTIVE thì pg_cron finish_stale_sessions tự kết thúc và cộng km sau 30 phút.
        if (mounted) {
          state = state.copyWith(
            status: TrackingStatus.idle,
            errorCode: 'ERR_NETWORK',
            errorMessage:
                'Không gửi được kết quả Phiên chạy. Quãng đường đã kiểm định sẽ được tự cộng trong khoảng 30 phút.',
          );
        }
      }
    } finally {
      _stopping = false;
      // Giữ cờ Tạm dừng tới lúc có kết quả để màn hình không nháy lại giao diện đang chạy.
      if (mounted && state.paused) state = state.copyWith(paused: false, autoPaused: false, pauseExpiring: false);
    }
  }

  /// Chờ các cửa sổ đã nhận được gửi xong (dùng cho test).
  Future<void> flush() => _pending;

  Future<void> _verify(TelemetryWindow window) async {
    if (!mounted || state.status != TrackingStatus.tracking) return;
    try {
      final signingKey = _signingKey;
      final result = await _repository.verifyWindow(
        window,
        sessionId: state.sessionId,
        signingKey: signingKey,
        seq: signingKey == null ? null : ++_seq,
      );
      if (!mounted || state.status != TrackingStatus.tracking) return;
      _signingKey = result.signingKey ?? _signingKey;
      state = state.copyWith(
        sessionId: result.sessionId,
        cadenceSpm: result.cadenceSpm,
        windowWarning: !result.windowPassed,
        connectionIssue: false,
        gpsSearching: false,
      );
    } on SisoException catch (e) {
      if (!mounted) return;
      // ERR_203: server chỉ bỏ cửa sổ này (mất tín hiệu vệ tinh), Phiên chạy vẫn tiếp tục.
      if (e.code == SisoErrorCodes.gpsAccuracyLow) {
        state = state.copyWith(gpsSearching: true, connectionIssue: false);
        return;
      }
      // ERR_206/ERR_207: server cũng chỉ bỏ cửa sổ này (vệt GPS lệch giờ, cửa sổ đến sớm), Phiên chạy tiếp tục.
      if (e.code == SisoErrorCodes.invalidGpsPoints || e.code == SisoErrorCodes.windowTooEarly) return;
      _cancelSubscriptions();
      _resetPause();
      _source.stop();
      // Chỉ các mã Anti-GIGO này là Phiên bị loại. Các lỗi khác (ERR_204 Phiên đã kết thúc,
      // chưa đăng nhập, dữ liệu sai định dạng) chỉ dừng Phiên chạy, không phải bị loại.
      final rejected = _rejectionCodes.contains(e.code);
      state = state.copyWith(
        status: rejected ? TrackingStatus.rejected : TrackingStatus.idle,
        errorCode: e.code,
        errorMessage: e.message,
      );
    } catch (_) {
      // Lỗi mạng: bỏ cửa sổ này, Phiên chạy tiếp tục với cửa sổ sau.
      if (mounted) state = state.copyWith(connectionIssue: true);
    }
  }

  void _cancelSubscriptions() {
    _speedSub?.cancel();
    _windowSub?.cancel();
    _positionSub?.cancel();
    _speedSub = null;
    _windowSub = null;
    _positionSub = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _resetPause();
    _source.stop();
    super.dispose();
  }
}

/// Bản build Demo Simulator (Ngày 29): `flutter build ipa --dart-define=SISO_DEMO=true`.
const kSisoDemo = bool.fromEnvironment('SISO_DEMO');

/// Có được dùng nguồn giả lập / phát lại log không: chỉ khi debug hoặc bản demo.
/// Bản phát hành luôn dùng cảm biến thật. Override được trong test.
final allowFakeSourcesProvider = Provider<bool>((ref) => kDebugMode || kSisoDemo);

/// Nguồn đang chọn trên màn Chạy: cảm biến thật (mặc định), giả lập, hoặc phát lại log (issue #8).
final telemetrySourceChoiceProvider =
    StateProvider<TelemetrySourceChoice>((ref) => const DeviceSourceChoice());

final telemetryWindowSourceProvider = Provider<TelemetryWindowSource>((ref) {
  // Chặn cả ở đây, không chỉ ẩn bộ chọn: bản phát hành không bao giờ gửi dữ liệu giả lên server.
  final choice =
      ref.watch(allowFakeSourcesProvider) ? ref.watch(telemetrySourceChoiceProvider) : const DeviceSourceChoice();
  switch (choice) {
    case DeviceSourceChoice():
      final source = DeviceTelemetrySource();
      ref.onDispose(source.dispose);
      return source;
    case SimulatedSourceChoice():
      final source = SimulatedTelemetrySource();
      ref.onDispose(source.dispose);
      return source;
    case ReplaySourceChoice(:final name, :final log, :final speedFactor):
      final source = ReplayTelemetrySource(log: log, name: name, speedFactor: speedFactor);
      ref.onDispose(source.dispose);
      return source;
  }
});

final telemetryRepositoryProvider = Provider<TelemetryRepository>((ref) => TelemetryRepository());

final trackingSessionNotifierProvider =
    StateNotifierProvider.autoDispose<TrackingSessionNotifier, RunState>((ref) {
  return TrackingSessionNotifier(
    source: ref.watch(telemetryWindowSourceProvider),
    repository: ref.watch(telemetryRepositoryProvider),
    reminder: ref.watch(pauseReminderProvider),
  );
});
