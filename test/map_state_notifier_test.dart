import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:siso_project/src/core/constants/colors.dart';
import 'package:siso_project/src/features/map/data/hexagon_repository.dart';
import 'package:siso_project/src/features/map/providers/map_state_notifier.dart';

/// Repository giả: trả dữ liệu cố định, giữ lại callback socket để test tự bắn sự kiện.
class FakeHexagonRepository extends HexagonRepository {
  FakeHexagonRepository(this.rows);

  final List<Map<String, dynamic>> rows;
  void Function(dynamic event)? onClaimed;

  /// Callback đã đăng ký và đã gỡ, để kiểm tra notifier gỡ đúng listener của mình.
  Function(dynamic event)? subscribed;
  Function(dynamic event)? unsubscribed;

  @override
  Future<List<Map<String, dynamic>>> fetchArenaHexagons([String? arenaId]) async => rows;

  @override
  void subscribeHexClaimed(Function(dynamic event) onClaimed) {
    subscribed = onClaimed;
    this.onClaimed = (e) => onClaimed(e);
  }

  @override
  void unsubscribeHexClaimed(Function(dynamic event) onClaimed) {
    unsubscribed = onClaimed;
  }
}

const _hutech = 'uni-hutech';
const _uef = 'uni-uef';

List<Map<String, dynamic>> _rows() => [
      {'h3Index': '8a65b5600007fff', 'ownerUniversityId': _hutech, 'hexColor': '#FFCC00', 'shieldHp': 80},
      {'h3Index': '8a65b560000ffff', 'ownerUniversityId': null, 'hexColor': '#44FFFFFF', 'shieldHp': 100},
      {'h3Index': '8a65b5600017fff', 'ownerUniversityId': null, 'hexColor': 'không-phải-màu', 'shieldHp': 100},
    ];

/// Ranh giới giả: mọi ô hợp lệ trừ ô bắt đầu bằng `bad`.
Future<Map<String, List<LatLng>>> _fakeBoundaries(List<String> h3Indexes) async => {
      for (final h in h3Indexes)
        if (!h.startsWith('bad')) h: const [LatLng(10.8, 106.7)],
    };

Future<MapStateNotifier> _loaded(FakeHexagonRepository repo) async {
  final notifier = MapStateNotifier(repository: repo, boundariesOf: _fakeBoundaries);
  await notifier.loadHexagons();
  return notifier;
}

void main() {
  group('MapStateNotifier: tải ô', () {
    test('tải toàn bộ ô từ repository, kèm ranh giới đã tính', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));

      expect(notifier.state.keys, ['8a65b5600007fff', '8a65b560000ffff', '8a65b5600017fff']);
      expect(notifier.state['8a65b5600007fff']!.boundary, isNotEmpty);
      expect(notifier.state['8a65b5600007fff']!.shieldHp, 80);
    });

    test('ô có chủ mang màu trường; ô không có chủ là trung lập', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));

      final owned = notifier.state['8a65b5600007fff']!;
      expect(owned.isNeutral, isFalse);
      expect(owned.color, const Color(0xFFFFCC00));
      expect(notifier.state['8a65b560000ffff']!.isNeutral, isTrue);
    });

    test('đọc được màu #AARRGGBB; màu sai định dạng thành màu trung lập', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));

      expect(notifier.state['8a65b560000ffff']!.color, const Color(0x44FFFFFF));
      expect(notifier.state['8a65b5600017fff']!.color, CampusColors.neutralHex);
    });

    test('bỏ qua dòng thiếu h3Index', () async {
      final notifier = await _loaded(FakeHexagonRepository([
        {'ownerUniversityId': _hutech, 'hexColor': '#FFCC00'},
        ..._rows(),
      ]));

      expect(notifier.state, hasLength(3));
    });

    test('bỏ qua ô có h3Index không hợp lệ (không tính được ranh giới)', () async {
      final notifier = await _loaded(FakeHexagonRepository([
        {'h3Index': 'bad-index', 'ownerUniversityId': null, 'hexColor': '#44FFFFFF'},
        ..._rows(),
      ]));

      expect(notifier.state, hasLength(3));
      expect(notifier.state.containsKey('bad-index'), isFalse);
    });

    test('tính ranh giới cả lô trong một lần gọi', () async {
      var calls = 0;
      final notifier = MapStateNotifier(
        repository: FakeHexagonRepository(_rows()),
        boundariesOf: (ids) {
          calls++;
          return _fakeBoundaries(ids);
        },
      );
      await notifier.loadHexagons();

      expect(calls, 1);
      expect(notifier.state, hasLength(3));
    });

    test('backend rỗng hoặc lỗi (repository trả mảng rỗng) thì không có ô nào', () async {
      final notifier = await _loaded(FakeHexagonRepository([]));

      expect(notifier.state, isEmpty);
    });
  });

  group('MapStateNotifier: sự kiện hex_claimed', () {
    Map<String, dynamic> claimed(List<String> hexes) => {
          'universityId': _uef,
          'universityCode': 'UEF',
          'hexColor': '#ED1C24',
          'claimedHexes': hexes,
          'arenaId': 'arena-1',
          'claimedAt': '2026-11-04T10:00:00.000Z',
        };

    test('đổi chủ, màu và hồi shieldHp về 100 đúng các ô được chiếm', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));

      notifier.applyHexClaimed(claimed(['8a65b5600007fff']));

      final cell = notifier.state['8a65b5600007fff']!;
      expect(cell.universityId, _uef);
      expect(cell.color, const Color(0xFFED1C24));
      expect(cell.shieldHp, 100);
    });

    test('ô không nằm trong sự kiện giữ nguyên', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));

      notifier.applyHexClaimed(claimed(['8a65b5600007fff']));

      expect(notifier.state['8a65b560000ffff']!.isNeutral, isTrue);
    });

    test('ô chưa có trên bản đồ bị bỏ qua, không được thêm vào', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));

      notifier.applyHexClaimed(claimed(['8a65b56ffffffff', '8a65b560000ffff']));

      expect(notifier.state, hasLength(3));
      expect(notifier.state.containsKey('8a65b56ffffffff'), isFalse);
      expect(notifier.state['8a65b560000ffff']!.universityId, _uef);
    });

    test('payload sai định dạng bị bỏ qua', () async {
      final notifier = await _loaded(FakeHexagonRepository(_rows()));
      final before = notifier.state;

      notifier.applyHexClaimed('không phải map');
      notifier.applyHexClaimed({'universityId': _uef});
      notifier.applyHexClaimed({'universityId': 1, 'claimedHexes': ['8a65b5600007fff']});

      expect(notifier.state, same(before));
    });

    test('sự kiện từ socket (qua subscribeRealtime) cập nhật bản đồ', () async {
      final repo = FakeHexagonRepository(_rows());
      final notifier = await _loaded(repo);
      notifier.subscribeRealtime();

      repo.onClaimed!(claimed(['8a65b560000ffff']));

      expect(notifier.state['8a65b560000ffff']!.universityId, _uef);
    });

    test('sự kiện tới sau khi notifier bị huỷ không gây lỗi', () async {
      final repo = FakeHexagonRepository(_rows());
      final notifier = await _loaded(repo);
      notifier.subscribeRealtime();
      notifier.dispose();

      expect(() => repo.onClaimed!(claimed(['8a65b560000ffff'])), returnsNormally);
    });

    test('dispose gỡ đúng listener đã đăng ký khỏi socket', () async {
      final repo = FakeHexagonRepository(_rows());
      final notifier = await _loaded(repo);
      notifier.subscribeRealtime();
      expect(repo.unsubscribed, isNull);

      notifier.dispose();

      expect(repo.subscribed, isNotNull);
      expect(repo.unsubscribed, same(repo.subscribed));
    });
  });
}
