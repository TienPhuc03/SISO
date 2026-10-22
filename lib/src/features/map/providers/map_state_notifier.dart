import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [Dev A] Quản lý trạng thái các ô lục giác H3 trên bản đồ & Realtime WebSocket
class MapStateNotifier extends StateNotifier<Map<String, String>> {
  /// Map lưu cặp (h3_index -> owner_university_id)
  MapStateNotifier() : super(const {});

  void updateHexOwner(String h3Index, String universityId) {
    state = {...state, h3Index: universityId};
  }
}

final mapStateNotifierProvider =
    StateNotifierProvider<MapStateNotifier, Map<String, String>>((ref) {
  return MapStateNotifier();
});
