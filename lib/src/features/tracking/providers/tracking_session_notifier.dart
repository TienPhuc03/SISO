import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../data/device_telemetry_source.dart';
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
  });

  final TrackingStatus status;
  final String? sessionId;

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
  }) =>
      RunState(
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
  })  : _source = source,
        _repository = repository,
        super(const RunState());

  final TelemetryWindowSource _source;
  final TelemetryRepository _repository;
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
    _signingKey = null;
    _seq = 0;
    state = const RunState(status: TrackingStatus.tracking);
    _speedSub = _source.speedMps.listen((mps) {
      if (mounted && state.status == TrackingStatus.tracking) {
        state = state.copyWith(speedKmh: mps * 3.6);
      }
    });
    _positionSub = _source.positions.listen((fix) {
      if (mounted && state.status == TrackingStatus.tracking && fix.trusted) {
        state = state.copyWith(route: [...state.route, LatLng(fix.lat, fix.lng)]);
      }
    });
    _windowSub = _source.windows.listen(
      (window) => _pending = _pending.then((_) => _verify(window)),
      onError: _onSourceError,
    );
    _source.start();
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
        if (mounted) {
          state = state.copyWith(status: TrackingStatus.idle, errorCode: e.code, errorMessage: e.message);
        }
      } catch (_) {
        // shortcut: không thử gửi lại, km lần này mất; thêm hàng đợi gửi lại nếu field test thấy mất mạng thường xuyên.
        if (mounted) {
          state = state.copyWith(
            status: TrackingStatus.idle,
            errorCode: 'ERR_NETWORK',
            errorMessage: 'Không gửi được kết quả Phiên chạy, quãng đường lần này chưa được cộng.',
          );
        }
      }
    } finally {
      _stopping = false;
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
      _cancelSubscriptions();
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
  );
});
