import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart';

import '../../../core/constants/colors.dart';
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
    required HexBoundariesFn boundariesOf,
    SyntheticCellsFn syntheticCells = syntheticCellsAround,
  })  : _repository = repository,
        _boundariesOf = boundariesOf,
        _syntheticCells = syntheticCells,
        super(const {});

  final HexagonRepository _repository;
  final HexBoundariesFn _boundariesOf;
  final SyntheticCellsFn _syntheticCells;

  /// Các ô giả đang hiển thị (chỉ có khi bật chế độ đo hiệu năng).
  final Set<String> _syntheticIds = {};
  int get syntheticCount => _syntheticIds.length;

  /// Tải toàn bộ ô từ backend (tất cả Đấu trường đang có, chưa lọc).
  /// Ranh giới của cả lô được tính một lượt trong Isolate phụ; ô có `h3Index` không hợp lệ bị bỏ.
  Future<void> loadHexagons() async {
    final rows = await _repository.fetchArenaHexagons();
    if (!mounted) return;

    final validRows = [
      for (final row in rows)
        if (row['h3Index'] case final String h3Index when h3Index.isNotEmpty) (h3Index, row),
    ];
    final boundaries = await _boundariesOf([for (final (h3Index, _) in validRows) h3Index]);
    if (!mounted) return;

    final cells = <String, HexCell>{};
    for (final (h3Index, row) in validRows) {
      final boundary = boundaries[h3Index];
      if (boundary == null || boundary.isEmpty) continue;
      cells[h3Index] = HexCell(
        h3Index: h3Index,
        universityId: row['ownerUniversityId'] as String?,
        color: parseHexColor(row['hexColor']),
        shieldHp: (row['shieldHp'] as num?)?.toInt() ?? 100,
        boundary: boundary,
      );
    }
    // Giữ các ô đã thêm trước đó (vd. ô giả của bảng đo hiệu năng) nếu tải xong muộn hơn.
    state = {...state, ...cells};
  }

  /// Chế độ đo hiệu năng: thêm ô giả quanh [center] cho tới khi bản đồ có đủ [targetTotal] ô.
  /// Ô giả trùng ô thật bị bỏ qua (ô thật giữ nguyên). Chỉ nằm trong bộ nhớ, không gửi backend.
  Future<void> addSyntheticCells({required LatLng center, int targetTotal = 500}) async {
    removeSyntheticCells();
    final missing = targetTotal - state.length;
    if (missing <= 0) return;

    // Xin dư để bù các ô trùng với ô thật.
    final generated = await _syntheticCells(center, missing + state.length);
    if (!mounted) return;

    final next = Map<String, HexCell>.of(state);
    for (final MapEntry(key: h3Index, value: boundary) in generated.entries) {
      if (next.length >= targetTotal) break;
      if (next.containsKey(h3Index) || boundary.isEmpty) continue;
      next[h3Index] = HexCell(
        h3Index: h3Index,
        universityId: null,
        color: CampusColors.neutralHex,
        shieldHp: 100,
        boundary: boundary,
      );
      _syntheticIds.add(h3Index);
    }
    state = next;
  }

  /// Gỡ toàn bộ ô giả, trả bản đồ về dữ liệu thật.
  void removeSyntheticCells() {
    if (_syntheticIds.isEmpty || !mounted) return;
    state = {
      for (final entry in state.entries)
        if (!_syntheticIds.contains(entry.key)) entry.key: entry.value,
    };
    _syntheticIds.clear();
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
    boundariesOf: h3BoundariesInIsolate,
  );
  notifier.loadHexagons();
  notifier.subscribeRealtime();
  return notifier;
});
