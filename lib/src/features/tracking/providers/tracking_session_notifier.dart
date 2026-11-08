import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../data/simulated_telemetry_source.dart';
import '../data/telemetry_repository.dart';
import '../domain/telemetry_window.dart';

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
    this.errorCode,
    this.errorMessage,
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

  final String? errorCode;
  final String? errorMessage;

  RunState copyWith({
    TrackingStatus? status,
    String? sessionId,
    double? speedKmh,
    int? cadenceSpm,
    bool? windowWarning,
    bool? connectionIssue,
    String? errorCode,
    String? errorMessage,
  }) =>
      RunState(
        status: status ?? this.status,
        sessionId: sessionId ?? this.sessionId,
        speedKmh: speedKmh ?? this.speedKmh,
        cadenceSpm: cadenceSpm ?? this.cadenceSpm,
        windowWarning: windowWarning ?? this.windowWarning,
        connectionIssue: connectionIssue ?? this.connectionIssue,
        errorCode: errorCode ?? this.errorCode,
        errorMessage: errorMessage ?? this.errorMessage,
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

  /// Hàng đợi gửi tuần tự: mỗi cửa sổ cần sessionId do cửa sổ trước trả về.
  Future<void> _pending = Future.value();

  void startRun() {
    _cancelSubscriptions();
    state = const RunState(status: TrackingStatus.tracking);
    _speedSub = _source.speedMps.listen((mps) {
      if (mounted && state.status == TrackingStatus.tracking) {
        state = state.copyWith(speedKmh: mps * 3.6);
      }
    });
    _windowSub = _source.windows.listen((window) {
      _pending = _pending.then((_) => _verify(window));
    });
    _source.start();
  }

  void stopRun() {
    _cancelSubscriptions();
    _source.stop();
    if (mounted && state.status != TrackingStatus.rejected) {
      state = state.copyWith(status: TrackingStatus.idle);
    }
  }

  /// Chờ các cửa sổ đã nhận được gửi xong (dùng cho test).
  Future<void> flush() => _pending;

  Future<void> _verify(TelemetryWindow window) async {
    if (!mounted || state.status != TrackingStatus.tracking) return;
    try {
      final result = await _repository.verifyWindow(window, sessionId: state.sessionId);
      if (!mounted || state.status != TrackingStatus.tracking) return;
      state = state.copyWith(
        sessionId: result.sessionId,
        cadenceSpm: result.cadenceSpm,
        windowWarning: !result.windowPassed,
        connectionIssue: false,
      );
    } on SisoException catch (e) {
      if (!mounted) return;
      _cancelSubscriptions();
      _source.stop();
      // Mã ERR_2xx là kết luận của Anti-GIGO: Phiên bị loại. Các lỗi khác (chưa đăng nhập,
      // dữ liệu sai định dạng) chỉ dừng Phiên chạy, không phải bị loại.
      final rejected = e.code.startsWith('ERR_2');
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
    _speedSub = null;
    _windowSub = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _source.stop();
    super.dispose();
  }
}

/// Mặc định dùng nguồn GIẢ LẬP. Khi DEV 1 xong cảm biến thật, đổi provider này sang nguồn thật.
final telemetryWindowSourceProvider = Provider<TelemetryWindowSource>((ref) {
  final source = SimulatedTelemetrySource();
  ref.onDispose(source.dispose);
  return source;
});

final telemetryRepositoryProvider = Provider<TelemetryRepository>((ref) => TelemetryRepository());

final trackingSessionNotifierProvider =
    StateNotifierProvider.autoDispose<TrackingSessionNotifier, RunState>((ref) {
  return TrackingSessionNotifier(
    source: ref.watch(telemetryWindowSourceProvider),
    repository: ref.watch(telemetryRepositoryProvider),
  );
});
