import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hexagon_repository.dart';
import '../domain/h3_boundary.dart';
import '../domain/hex_cell.dart';

/// Quản lý trạng thái các ô lục giác H3 trên bản đồ (h3Index → HexCell).
///
/// Tải toàn bộ ô một lần, giữ sẵn ranh giới; sự kiện `hex_claimed` chỉ đổi chủ và màu
/// của các ô đã tải (quyết định ở ticket wayfinder #6).
class MapStateNotifier extends StateNotifier<Map<String, HexCell>> {
  MapStateNotifier({
    required HexagonRepository repository,
    required HexBoundaryFn boundaryOf,
  })  : _repository = repository,
        _boundaryOf = boundaryOf,
        super(const {});

  final HexagonRepository _repository;
  final HexBoundaryFn _boundaryOf;

  /// Tải toàn bộ ô từ backend (chưa lọc theo Đấu trường).
  Future<void> loadHexagons() async {
    final rows = await _repository.fetchArenaHexagons();
    if (!mounted) return;

    final cells = <String, HexCell>{};
    for (final row in rows) {
      final h3Index = row['h3Index'];
      if (h3Index is! String || h3Index.isEmpty) continue;
      cells[h3Index] = HexCell(
        h3Index: h3Index,
        universityId: row['ownerUniversityId'] as String?,
        color: parseHexColor(row['hexColor']),
        shieldHp: (row['shieldHp'] as num?)?.toInt() ?? 100,
        boundary: _boundaryOf(h3Index),
      );
    }
    state = cells;
  }

  /// Áp sự kiện `hex_claimed` từ WebSocket:
  /// `{ universityId, universityCode, hexColor, claimedHexes, arenaId, claimedAt }`.
  /// Ô chưa có trên bản đồ bị bỏ qua; payload sai định dạng bị bỏ qua.
  void applyHexClaimed(dynamic event) {
    if (!mounted || event is! Map) return;
    final universityId = event['universityId'];
    final claimedHexes = event['claimedHexes'];
    if (universityId is! String || claimedHexes is! List) return;

    final color = parseHexColor(event['hexColor']);
    final next = Map<String, HexCell>.of(state);
    var changed = false;
    for (final h3Index in claimedHexes) {
      if (h3Index is! String) continue;
      final cell = next[h3Index];
      if (cell == null) continue;
      // Server đặt shield_hp = 100 khi chiếm (TurfService.claimLoop).
      next[h3Index] = cell.copyWith(universityId: universityId, color: color, shieldHp: 100);
      changed = true;
    }
    if (changed) state = next;
  }

  /// Lắng nghe `hex_claimed` qua socket đã khởi tạo trong `main`.
  void subscribeRealtime() => _repository.subscribeHexClaimed(applyHexClaimed);
}

final hexagonRepositoryProvider = Provider<HexagonRepository>((ref) => HexagonRepository());

final mapStateNotifierProvider =
    StateNotifierProvider<MapStateNotifier, Map<String, HexCell>>((ref) {
  final notifier = MapStateNotifier(
    repository: ref.watch(hexagonRepositoryProvider),
    boundaryOf: h3BoundaryOf,
  );
  notifier.loadHexagons();
  notifier.subscribeRealtime();
  return notifier;
});
