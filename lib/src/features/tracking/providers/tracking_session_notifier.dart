import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [Dev A + Dev B] Quản lý trạng thái phiên chạy (Idle -> Tracking -> EvaluatingLoop)
enum TrackingStatus { idle, tracking, evaluatingLoop, rejected }

class TrackingSessionNotifier extends StateNotifier<TrackingStatus> {
  TrackingSessionNotifier() : super(TrackingStatus.idle);

  void startRun() => state = TrackingStatus.tracking;
  void stopRun() => state = TrackingStatus.idle;
}

final trackingSessionNotifierProvider =
    StateNotifierProvider<TrackingSessionNotifier, TrackingStatus>((ref) {
  return TrackingSessionNotifier();
});
